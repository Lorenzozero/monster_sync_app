#include <Arduino.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include "imu_kinematic.h"
#include "gps_parser.h"
#include "ble_server.h"
#include "sensors_io.h"

// Task Handles e Mutex
TaskHandle_t TaskIMU;
TaskHandle_t TaskGPS;
TaskHandle_t TaskBLE;
TaskHandle_t TaskSensors;
TaskHandle_t TaskWiFi;
SemaphoreHandle_t gpsMutex; // Protegge i dati GPS condivisi

const char* ssid = "IlTuoHotspot";
const char* password = "LaTuaPassword";
const char* serverUrl = "http://192.168.1.100:8000/telemetry";

// Funzioni wrapper thread-safe per leggere i dati GPS
struct GPSData {
    double lat;
    double lng;
    float speed;
};

GPSData getSafeGPSData() {
    GPSData temp = {0.0, 0.0, 0.0};
    if (xSemaphoreTake(gpsMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
        temp.lat = GPS_GetLatitude();
        temp.lng = GPS_GetLongitude();
        temp.speed = GPS_GetSpeed();
        xSemaphoreGive(gpsMutex);
    }
    return temp;
}

void IMULoop(void *pvParameters) {
    TickType_t xLastWakeTime = xTaskGetTickCount();
    for (;;) {
        IMU_Update();
        vTaskDelayUntil(&xLastWakeTime, pdMS_TO_TICKS(10)); // 100Hz fisso
    }
}

void GPSLoop(void *pvParameters) {
    for (;;) {
        if (xSemaphoreTake(gpsMutex, pdMS_TO_TICKS(50)) == pdTRUE) {
            GPS_Update();
            xSemaphoreGive(gpsMutex);
        }
        vTaskDelay(pdMS_TO_TICKS(50));
    }
}

void BLELoop(void *pvParameters) {
    for (;;) {
        BLE_SendTelemetry();
        vTaskDelay(pdMS_TO_TICKS(100)); // 10Hz
    }
}

void SensorsLoop(void *pvParameters) {
    for (;;) {
        Sensors_Update();
        vTaskDelay(pdMS_TO_TICKS(200));
    }
}

void WiFiCloudLoop(void *pvParameters) {
    WiFiClient client;
    for (;;) {
        if (strcmp(ssid, "IlTuoHotspot") != 0 && !BLE_IsConnected() && GPS_HasFix()) {
            if (WiFi.status() != WL_CONNECTED) {
                WiFi.begin(ssid, password);
                int retries = 0;
                while (WiFi.status() != WL_CONNECTED && retries < 30) {
                    vTaskDelay(pdMS_TO_TICKS(500));
                    retries++;
                }
            }

            if (WiFi.status() == WL_CONNECTED) {
                HTTPClient http;
                http.begin(client, serverUrl);
                http.addHeader("Content-Type", "application/json");
                
                GPSData currentGPS = getSafeGPSData();
                
                String payload = "{\"lat\":" + String(currentGPS.lat, 6) + 
                                 ",\"lng\":" + String(currentGPS.lng, 6) + 
                                 ",\"speed\":" + String(currentGPS.speed) + "}";
                                 
                int httpResponseCode = http.POST(payload);
                http.end();
            }
        } else if (BLE_IsConnected() && WiFi.status() == WL_CONNECTED) {
            WiFi.disconnect(true);
        }
        
        vTaskDelay(pdMS_TO_TICKS(5000));
    }
}

void setup() {
    Serial.begin(115200);
    delay(2000); 
    Serial.println("--- Avvio MonsterSync ---");

    // Inizializza il driver WiFi in STA ma NON spegnere la radio (WIFI_OFF).
    // Su ESP32, spegnere completamente la radio disabilita anche il Bluetooth,
    // causando crash durante l'inizializzazione del BLE.
    WiFi.persistent(false);
    WiFi.mode(WIFI_STA);
    WiFi.disconnect(true);
    Serial.println("WiFi inizializzato in STA (disconnesso, radio ON per BLE).");

    // Inizializzazione MUTEX
    gpsMutex = xSemaphoreCreateMutex();
    if (gpsMutex == NULL) {
        Serial.println("Errore creazione Mutex!");
        while(1);
    }

    // Inizializzazione SEQUENZIALE dei sottosistemi nel thread principale.
    // In questo modo è chiaro quale modulo fallisce e si evitano conflitti di stack.
    Serial.println("Avvio IMU...");
    IMU_Init();
    Serial.println("IMU Inizializzata.");

    Serial.println("Avvio GPS...");
    GPS_Init();
    Serial.println("GPS Inizializzato.");

    Serial.println("Avvio BLE...");
    BLE_Setup();
    Serial.println("BLE Inizializzato.");

    Serial.println("Avvio Sensori I/O...");
    Sensors_Init();
    Serial.println("Sensori I/O Inizializzati.");

    // Avvio dei task FreeRTOS dopo che tutto è stato configurato con successo
    xTaskCreatePinnedToCore(IMULoop, "IMU", 4096, NULL, 5, &TaskIMU, 1);
    xTaskCreatePinnedToCore(GPSLoop, "GPS", 4096, NULL, 3, &TaskGPS, 1);
    xTaskCreatePinnedToCore(BLELoop, "BLE", 10240, NULL, 4, &TaskBLE, 0);
    xTaskCreatePinnedToCore(SensorsLoop, "Sensors", 2048, NULL, 2, &TaskSensors, 1);
    xTaskCreatePinnedToCore(WiFiCloudLoop, "WiFi", 8192, NULL, 1, &TaskWiFi, 0);
    
    Serial.println("Tutti i task FreeRTOS avviati con successo.");
}

void loop() {
    vTaskDelete(NULL);
}