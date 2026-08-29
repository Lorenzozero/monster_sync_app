class TelemetryData {
  final double speed;
  final double oilTemp;
  final double voltage;
  final int fuelBars; // 0 to 8
  final double rpm;
  final int autonomy;
  final double consumption;
  final double gForce;

  final double latitude;
  final double longitude;
  final double leanAngle;

  TelemetryData({
    required this.speed,
    required this.oilTemp,
    required this.voltage,
    required this.fuelBars,
    required this.rpm,
    required this.autonomy,
    required this.consumption,
    required this.gForce,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.leanAngle = 0.0,
  });

  TelemetryData copyWith({
    double? speed,
    double? oilTemp,
    double? voltage,
    int? fuelBars,
    double? rpm,
    int? autonomy,
    double? consumption,
    double? gForce,
    double? latitude,
    double? longitude,
    double? leanAngle,
  }) {
    return TelemetryData(
      speed: speed ?? this.speed,
      oilTemp: oilTemp ?? this.oilTemp,
      voltage: voltage ?? this.voltage,
      fuelBars: fuelBars ?? this.fuelBars,
      rpm: rpm ?? this.rpm,
      autonomy: autonomy ?? this.autonomy,
      consumption: consumption ?? this.consumption,
      gForce: gForce ?? this.gForce,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      leanAngle: leanAngle ?? this.leanAngle,
    );
  }
}
