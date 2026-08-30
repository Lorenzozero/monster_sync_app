#ifndef IMU_KINEMATIC_H
#define IMU_KINEMATIC_H

void IMU_Init();
void IMU_Update();
float IMU_GetLeanAngle();  // GRADI (positivo = un lato, negativo = l'altro)
float IMU_GetGForce();     // modulo dell'accelerazione misurata, in g
bool  IMU_IsReady();       // false se l'MPU-6050 non risponde sull'I2C

#endif // IMU_KINEMATIC_H
