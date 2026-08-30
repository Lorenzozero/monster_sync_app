#include "ble_server.h"
#include <Arduino.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLEUtils.h>
#include <BLE2902.h>
#include "imu_kinematic.h"
#include "gps_parser.h"
#include "sensors_io.h"

// Definizione uuid servizi e caratteristiche BLE
#define SERVICE_UUID        "4fafc201-1fb5-459e-8fcc-c5c9c331914b"
#define CHARACTERISTIC_UUID "beb5483e-36e1-4688-b7f5-ea07361b26a8"

BLEServer* pServer = NULL;
BLECharacteristic* pCharacteristic = NULL;
bool deviceConnected = false;

// Struttura pacchetto compatto binario
struct __attribute__((packed)) TelemetryPacket {
    float leanAngle;
    float speed;
    float lat;
    float lng;
    uint8_t fuelReserve;
};

class MyServerCallbacks: public BLEServerCallbacks {
    void onConnect(BLEServer* pServer) {
      deviceConnected = true;
      Serial.println("Telefono Connesso via BLE!");
    };

    void onDisconnect(BLEServer* pServer) {
      deviceConnected = false;
      Serial.println("Telefono Disconnesso. Riparto l'advertising...");
      BLEDevice::startAdvertising();
    }
};

void BLE_Setup() {
    Serial.println("Inizializzazione BLE...");
    BLEDevice::init("MonsterSync_BLE");
    pServer = BLEDevice::createServer();
    pServer->setCallbacks(new MyServerCallbacks());

    BLEService *pService = pServer->createService(SERVICE_UUID);
    pCharacteristic = pService->createCharacteristic(
                        CHARACTERISTIC_UUID,
                        BLECharacteristic::PROPERTY_READ   |
                        BLECharacteristic::PROPERTY_NOTIFY
                      );
    pCharacteristic->addDescriptor(new BLE2902());
    pService->start();

    BLEAdvertising *pAdvertising = BLEDevice::getAdvertising();
    
    // Configura i dati pubblicitari espliciti per iPhone/iOS (richiede i flag corretti)
    BLEAdvertisementData oAdvertisementData = BLEAdvertisementData();
    oAdvertisementData.setFlags(0x06); // General Discoverable | BR_EDR_NOT_SUPPORTED
    oAdvertisementData.setCompleteServices(BLEUUID(SERVICE_UUID));
    pAdvertising->setAdvertisementData(oAdvertisementData);

    // Metti il nome nel pacchetto di risposta alla scansione (Scan Response)
    // per rimanere entro i 31 byte del pacchetto primario ed essere visibile su iOS
    BLEAdvertisementData oScanResponseData = BLEAdvertisementData();
    oScanResponseData.setName("MonsterSync_BLE");
    pAdvertising->setScanResponseData(oScanResponseData);

    pAdvertising->setScanResponse(true);
    pAdvertising->setMinPreferred(0x06);  // Aiuta con i problemi di connessione su iOS
    pAdvertising->setMinPreferred(0x12);
    BLEDevice::startAdvertising();
    Serial.println("BLE Advertising attivato. In attesa di connessioni...");
}

void BLE_SendTelemetry() {
    if (deviceConnected) {
        TelemetryPacket packet;
        packet.leanAngle = IMU_GetLeanAngle();
        packet.speed = GPS_GetSpeed();
        packet.lat = (float)GPS_GetLatitude();
        packet.lng = (float)GPS_GetLongitude();
        packet.fuelReserve = Sensors_IsLowFuel() ? 1 : 0;
        
        pCharacteristic->setValue((uint8_t*)&packet, sizeof(packet));
        pCharacteristic->notify();
    }
}

bool BLE_IsConnected() {
    return deviceConnected;
}
