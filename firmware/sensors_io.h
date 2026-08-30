#ifndef SENSORS_IO_H
#define SENSORS_IO_H

#include <stdint.h>

void Sensors_Init();
void Sensors_Update();

bool Sensors_IsLowFuel();
float Sensors_GetOilTemp();
uint32_t Sensors_GetRPM();

#endif // SENSORS_IO_H
