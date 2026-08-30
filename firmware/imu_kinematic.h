#ifndef IMU_KINEMATIC_H
#define IMU_KINEMATIC_H

void IMU_Init();
void IMU_Update();
float IMU_GetLeanAngle();
float IMU_GetGForce();

#endif // IMU_KINEMATIC_H
