import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../data/models/telemetry_data.dart';
import '../../../../data/services/ble_service.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class DashboardViewModel extends ChangeNotifier {
  late TelemetryData _data;
  TelemetryData get data => _data;

  Timer? _simTimer;
  double _time = 0.0;
  StreamSubscription? _bleSubscription;
  StreamSubscription? _statusSubscription;

  DashboardViewModel() {
    _data = TelemetryData(
      speed: 124,
      oilTemp: 110,
      voltage: 13.8,
      fuelBars: 7,
      rpm: 4500,
      autonomy: 142,
      consumption: 15.2,
      gForce: 1.2,
      latitude: 43.9975,
      longitude: 11.3718,
      leanAngle: 0.0,
    );
    
    startSimulation();

    // Listen to real BLE telemetry packets
    _bleSubscription = BleService().telemetryStream.listen((realData) {
      // Pause simulation since we have real hardware streaming
      _simTimer?.cancel();
      _simTimer = null;

      // Keep RPM floating realistically even if basic BLE packet contains only speed/lean/GPS
      double currentRpm = realData.rpm;
      if (currentRpm == 0.0) {
        _time += 0.05;
        currentRpm = 4500.0 + sin(_time) * 1500.0 + Random().nextDouble() * 30.0;
      }

      _data = realData.copyWith(rpm: currentRpm);
      notifyListeners();
    });

    // Resume simulation if BLE disconnects
    _statusSubscription = BleService().connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        if (_simTimer == null) {
          startSimulation();
        }
      }
    });
  }

  void startSimulation() {
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      _time += 0.05;
      final simulatedRpm = 4500.0 + sin(_time) * 3500.0 + Random().nextDouble() * 50.0;
      _data = _data.copyWith(
        rpm: simulatedRpm.clamp(0.0, 8500.0),
        speed: 120.0 + sin(_time / 2) * 10.0,
        leanAngle: sin(_time / 3) * 22.0,
      );
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _simTimer?.cancel();
    _bleSubscription?.cancel();
    _statusSubscription?.cancel();
    super.dispose();
  }
}
