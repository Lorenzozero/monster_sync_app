#include "imu_kinematic.h"
#include "gps_parser.h"
#include <Arduino.h>
#include <Wire.h>
#include <math.h>

// ─────────────────────────────────────────────────────────────────────────────
// Driver MPU-6050 + stima dell'angolo di piega
//
// PERCHÉ NON SI USA MADGWICK / L'ACCELEROMETRO COME RIFERIMENTO
// In curva stabilizzata la risultante fra gravità e accelerazione centripeta è
// allineata con l'asse verticale DELLA MOTO: l'accelerometro legge (0,0,-g)
// esattamente come da fermo in verticale. Ogni filtro AHRS che usa l'accelerometro
// come riferimento di gravità converge a 0° mentre sei a 40° di piega.
// Qui si usa invece:
//   - alta frequenza  -> integrazione del rateo di rollio del giroscopio
//   - bassa frequenza -> riferimento CINEMATICO  theta = atan(v * psi_dot / g)
//   - accelerometro   -> SOLO da fermo, per l'allineamento statico
// ─────────────────────────────────────────────────────────────────────────────

#define MPU_ADDR        0x68
#define REG_SMPLRT_DIV  0x19
#define REG_CONFIG      0x1A
#define REG_GYRO_CONFIG 0x1B
#define REG_ACCEL_CONFIG 0x1C
#define REG_ACCEL_XOUT  0x3B
#define REG_PWR_MGMT_1  0x6B
#define REG_WHO_AM_I    0x75

// Pin I2C. Su ESP32-S3-DevKitC i default sono questi; cambiali qui se la tua
// scheda usa altri pin (GPIO 4/5 sono già occupati da iniettore e riserva,
// GPIO 16/17 dal GPS).
#define IMU_SDA_PIN 8
#define IMU_SCL_PIN 9

// Fondo scala: ±500 °/s copre anche una piegata veloce (±250 può saturare),
// ±4 g basta per la dinamica. Per la crash detection servirà ±8 o ±16 g.
#define GYRO_LSB_PER_DPS 65.5f   // ±500 °/s
#define ACCEL_LSB_PER_G  8192.0f // ±4 g

#define GRAVITY 9.81f
#define ALPHA   0.98f   // filtro complementare, tarato per ~100 Hz
#define DEG_PER_RAD 57.29577951f

volatile float currentLeanAngle = 0.0f; // radianti, internamente
volatile float currentGForce = 1.0f;

static bool  imuReady = false;
static float gyroBiasX = 0.0f, gyroBiasY = 0.0f, gyroBiasZ = 0.0f;
static uint32_t lastUpdateUs = 0;

// ── I2C helpers ─────────────────────────────────────────────────────────────

static void mpuWrite(uint8_t reg, uint8_t value) {
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(reg);
    Wire.write(value);
    Wire.endTransmission();
}

static uint8_t mpuRead(uint8_t reg) {
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(reg);
    Wire.endTransmission(false);
    Wire.requestFrom((uint8_t)MPU_ADDR, (uint8_t)1);
    return Wire.available() ? Wire.read() : 0xFF;
}

// Legge in un colpo solo accelerometro (3), temperatura (1) e giroscopio (3).
static bool mpuReadRaw(int16_t *ax, int16_t *ay, int16_t *az,
                       int16_t *gx, int16_t *gy, int16_t *gz) {
    Wire.beginTransmission(MPU_ADDR);
    Wire.write(REG_ACCEL_XOUT);
    if (Wire.endTransmission(false) != 0) return false;
    if (Wire.requestFrom((uint8_t)MPU_ADDR, (uint8_t)14) != 14) return false;

    // Letture in due passi: in C++ l'ordine di valutazione degli operandi di `|`
    // non è garantito, quindi `(Wire.read()<<8) | Wire.read()` può invertire i byte.
    uint8_t b[14];
    for (uint8_t i = 0; i < 14; i++) b[i] = Wire.read();

    *ax = (int16_t)((b[0]  << 8) | b[1]);
    *ay = (int16_t)((b[2]  << 8) | b[3]);
    *az = (int16_t)((b[4]  << 8) | b[5]);
    // b[6], b[7] = temperatura, scartata
    *gx = (int16_t)((b[8]  << 8) | b[9]);
    *gy = (int16_t)((b[10] << 8) | b[11]);
    *gz = (int16_t)((b[12] << 8) | b[13]);
    return true;
}

// ── Calibrazione ────────────────────────────────────────────────────────────

// Il giroscopio dell'MPU-6050 ha un offset non trascurabile: senza rimuoverlo
// l'integrazione deriva di parecchi gradi al minuto.
static void calibrateGyro(uint16_t samples = 500) {
    Serial.println("IMU: calibrazione giroscopio, NON muovere la moto...");
    double sx = 0, sy = 0, sz = 0;
    uint16_t taken = 0;
    for (uint16_t i = 0; i < samples; i++) {
        int16_t ax, ay, az, gx, gy, gz;
        if (mpuReadRaw(&ax, &ay, &az, &gx, &gy, &gz)) {
            sx += gx; sy += gy; sz += gz;
            taken++;
        }
        delay(3);
    }
    if (taken > 0) {
        gyroBiasX = (float)(sx / taken);
        gyroBiasY = (float)(sy / taken);
        gyroBiasZ = (float)(sz / taken);
    }
    Serial.printf("IMU: bias giroscopio  X=%.1f  Y=%.1f  Z=%.1f LSB\n",
                  gyroBiasX, gyroBiasY, gyroBiasZ);
}

// ── API pubblica ────────────────────────────────────────────────────────────

void IMU_Init() {
    Serial.println("Inizializzazione IMU (MPU-6050)...");
    Wire.begin(IMU_SDA_PIN, IMU_SCL_PIN);
    Wire.setClock(400000);

    uint8_t who = mpuRead(REG_WHO_AM_I);
    if (who != 0x68) {
        Serial.printf("IMU: NON TROVATA (WHO_AM_I=0x%02X). Controlla SDA=%d SCL=%d e l'alimentazione.\n",
                      who, IMU_SDA_PIN, IMU_SCL_PIN);
        imuReady = false;
        return;
    }

    mpuWrite(REG_PWR_MGMT_1, 0x00);   // sveglia il sensore
    delay(100);
    // DLPF a 21 Hz: il bicilindrico vibra parecchio e la dinamica della moto sta
    // sotto i 10 Hz. Filtrare qui evita che le vibrazioni entrino per aliasing.
    mpuWrite(REG_CONFIG, 0x04);
    mpuWrite(REG_SMPLRT_DIV, 0x09);   // 1 kHz / (1+9) = 100 Hz, come il task
    mpuWrite(REG_GYRO_CONFIG, 0x08);  // ±500 °/s
    mpuWrite(REG_ACCEL_CONFIG, 0x08); // ±4 g
    delay(50);

    calibrateGyro();
    lastUpdateUs = micros();
    imuReady = true;
    Serial.println("IMU: pronta.");
}

void IMU_Update() {
    if (!imuReady) return;

    int16_t rax, ray, raz, rgx, rgy, rgz;
    if (!mpuReadRaw(&rax, &ray, &raz, &rgx, &rgy, &rgz)) return;

    // Assi: X longitudinale (avanti), Y laterale, Z verticale.
    // Se l'angolo risulta invertito, cambia segno a gx e ay qui sotto.
    const float gx = ((rgx - gyroBiasX) / GYRO_LSB_PER_DPS) / DEG_PER_RAD; // roll rate  [rad/s]
    const float gy = ((rgy - gyroBiasY) / GYRO_LSB_PER_DPS) / DEG_PER_RAD; // pitch rate [rad/s]
    const float gz = ((rgz - gyroBiasZ) / GYRO_LSB_PER_DPS) / DEG_PER_RAD; // yaw rate   [rad/s]

    const float ax = rax / ACCEL_LSB_PER_G; // [g]
    const float ay = ray / ACCEL_LSB_PER_G;
    const float az = raz / ACCEL_LSB_PER_G;

    // dt reale, non una costante: il task gira a 100 Hz ma un dt sbagliato
    // scala direttamente l'integrazione del giroscopio.
    const uint32_t now = micros();
    float dt = (now - lastUpdateUs) / 1000000.0f;
    lastUpdateUs = now;
    if (dt <= 0.0f || dt > 0.2f) dt = 0.01f; // primo giro o task in ritardo

    const float speed_kmh = GPS_GetSpeed();
    const float v = speed_kmh / 3.6f;

    // Modulo dell'accelerazione misurata, in g
    currentGForce = sqrtf(ax * ax + ay * ay + az * az);

    if (v < 1.0f) {
        // Da fermo l'accelerometro è un riferimento valido: qui, e solo qui,
        // si può leggere il rollio dalla gravità. Se la moto è sul cavalletto
        // l'angolo risulterà davvero inclinato: è corretto, non è un errore.
        currentLeanAngle = atan2f(ay, az);
        return;
    }

    // Imbardata attorno alla verticale del mondo, ricostruita dagli assi IMU:
    //   psi_dot ≈ gy * sin(theta) + gz * cos(theta)
    const float psi_dot = gy * sinf(currentLeanAngle) + gz * cosf(currentLeanAngle);

    // Riferimento cinematico di bassa frequenza
    const float theta_kin = atanf((v * psi_dot) / GRAVITY);

    // Fusione complementare: giroscopio veloce + cinematica lenta
    currentLeanAngle = ALPHA * (currentLeanAngle + gx * dt) + (1.0f - ALPHA) * theta_kin;
}

// Restituisce GRADI: è ciò che l'app si aspetta nel pacchetto BLE
// (le soglie della heatmap sono 15° e 30°).
float IMU_GetLeanAngle() {
    return currentLeanAngle * DEG_PER_RAD;
}

float IMU_GetGForce() {
    return currentGForce;
}

bool IMU_IsReady() {
    return imuReady;
}
