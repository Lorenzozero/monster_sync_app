#ifndef GPS_PARSER_H
#define GPS_PARSER_H

void GPS_Init();
void GPS_Update();
float GPS_GetSpeed();
double GPS_GetLatitude();
double GPS_GetLongitude();
bool GPS_HasFix();

#endif // GPS_PARSER_H
