#include "sensors_io.h"
#include <Arduino.h>

// Su ESP32-S3-WROOM-1 i pin GPIO 22, 23, 24, 25 e 26 sono riservati internamente 
// per la memoria Flash Octal-SPI e la PSRAM. Usarli causa "GPIO number error".
// Spostiamo i sensori su pin sicuri e liberi (GPIO 4 e GPIO 5).
#define FUEL_RESERVE_PIN 5
#define INJECTOR_PIN 4 // Per RPM / Consumo

volatile bool lowFuelState = false;
volatile uint32_t injectorPulses = 0;

// Interrupt Service Routine per il carburante
void IRAM_ATTR FuelReserveISR(void* arg) {
    lowFuelState = digitalRead(FUEL_RESERVE_PIN);
}

// ISR per conteggio RPM/Iniezioni
void IRAM_ATTR InjectorISR(void* arg) {
    injectorPulses++;
}

void Sensors_Init() {
    Serial.println("Inizializzazione Sensori I/O...");
    
    pinMode(FUEL_RESERVE_PIN, INPUT_PULLDOWN); // Dipende dall'optoisolatore
    
    // Usiamo attachInterruptArg nativo per evitare macro e digitalPinToInterrupt
    attachInterruptArg(FUEL_RESERVE_PIN, FuelReserveISR, NULL, CHANGE);

    pinMode(INJECTOR_PIN, INPUT_PULLDOWN);
    attachInterruptArg(INJECTOR_PIN, InjectorISR, NULL, FALLING);
}

void Sensors_Update() {
    // Lettura termocoppia o ADC, reset contatori RPM se necessario
}

bool Sensors_IsLowFuel() {
    return lowFuelState;
}

float Sensors_GetOilTemp() {
    return 90.5f;
}

uint32_t Sensors_GetRPM() {
    return 0; // Mock
}
