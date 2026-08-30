#include "gps_parser.h"
#include <Arduino.h>
#include <TinyGPS++.h>

TinyGPSPlus gps;

// Usiamo Serial1 o Serial2 per il GPS
#define GPS_SERIAL Serial1
#define GPS_RX_PIN 16
#define GPS_TX_PIN 17
#define GPS_BAUD 115200 // Il Beitian 10Hz di solito usa baud rate elevati

void GPS_Init() {
    Serial.println("Inizializzazione GPS...");
    GPS_SERIAL.begin(GPS_BAUD, SERIAL_8N1, GPS_RX_PIN, GPS_TX_PIN);
}

void GPS_Update() {
    while (GPS_SERIAL.available() > 0) {
        gps.encode(GPS_SERIAL.read());
    }
}

float GPS_GetSpeed() {
    if (gps.speed.isValid()) {
        return gps.speed.kmph();
    }
    return 0.0f;
}

double GPS_GetLatitude() {
    return gps.location.isValid() ? gps.location.lat() : 0.0;
}

double GPS_GetLongitude() {
    return gps.location.isValid() ? gps.location.lng() : 0.0;
}

bool GPS_HasFix() {
    return gps.location.isValid();
}
