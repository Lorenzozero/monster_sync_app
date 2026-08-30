#include "imu_kinematic.h"
#include <Arduino.h>

// Variabili globali per l'angolo di piega e le forze G
volatile float currentLeanAngle = 0.0f;
volatile float currentGForce = 1.0f;

void IMU_Init() {
    Serial.println("Inizializzazione IMU (ICM-42688-P / MPU6050)...");
    // TODO: Inizializzare bus SPI/I2C e configurare l'IMU (500Hz ODR)
}

#include "gps_parser.h"
#include <math.h>

#define GRAVITY 9.81f
#define ALPHA 0.98f  // Costante filtro complementare
#define DT 0.002f    // 500Hz -> 2ms

void IMU_Update() {
    // 1. Lettura dati grezzi IMU (mockup per ora, da sostituire con vere letture SPI/I2C)
    float gyro_x = 0.0f; // Roll rate (rad/s)
    float gyro_y = 0.0f; // Pitch rate (rad/s)
    float gyro_z = 0.0f; // Yaw rate IMU (rad/s)
    
    // 2. Acquisizione velocità dal GPS (in m/s)
    float speed_kmh = GPS_GetSpeed();
    float v = speed_kmh / 3.6f;
    
    // Se siamo fermi o quasi, usiamo solo l'accelerometro (o teniamo l'angolo a 0 per sicurezza)
    if (v < 1.0f) {
        // Fallback statico: in futuro qui si usa l'atan2() sull'accelerometro
        currentLeanAngle *= 0.95f; // Ritorna dolcemente a zero da fermo
        return;
    }

    // 3. Ricostruzione dell'imbardata reale (attorno all'asse Z del mondo)
    // ψ̇ ≈ ω_y * sin(θ) + ω_z * cos(θ)
    float psi_dot = gyro_y * sin(currentLeanAngle) + gyro_z * cos(currentLeanAngle);
    
    // 4. Riferimento a bassa frequenza (Cinematico)
    // θ_kin = atan(v * ψ̇ / g)
    float theta_kin = atan((v * psi_dot) / GRAVITY);
    
    // 5. Fusione Complementare (Alta frequenza giroscopio + Bassa frequenza cinematica)
    currentLeanAngle = ALPHA * (currentLeanAngle + gyro_x * DT) + (1.0f - ALPHA) * theta_kin;
    
    // 6. Calcolo G-Force (approssimata, andrebbe estratta dalla risultante accelerometrica reale)
    // Forza centrifuga + gravità
    currentGForce = sqrt(1.0f + pow((v * psi_dot) / GRAVITY, 2));
}

float IMU_GetLeanAngle() {
    return currentLeanAngle;
}

float IMU_GetGForce() {
    return currentGForce;
}
