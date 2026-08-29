import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../models/telemetry_data.dart';

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  static const String serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  static const String characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";

  BluetoothDevice? _connectedDevice;
  StreamSubscription? _scanSubscription;
  StreamSubscription? _valueSubscription;

  final _connectionStateController = StreamController<BluetoothConnectionState>.broadcast();
  final _telemetryController = StreamController<TelemetryData>.broadcast();

  Stream<BluetoothConnectionState> get connectionState => _connectionStateController.stream;
  Stream<TelemetryData> get telemetryStream => _telemetryController.stream;

  bool get isConnected => _connectedDevice != null;

  Future<void> startScan(Function(BluetoothDevice) onDeviceFound) async {
    // Ensure BLE is turned on
    await FlutterBluePlus.adapterState.where((val) => val == BluetoothAdapterState.on).first;

    await _scanSubscription?.cancel();
    _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
      for (ScanResult r in results) {
        final name = r.device.platformName.trim();
        final advName = r.advertisementData.advName.trim();
        if (name == 'MonsterSync_BLE' || 
            advName == 'MonsterSync_BLE' || 
            r.advertisementData.serviceUuids.contains(Guid(serviceUuid))) {
          onDeviceFound(r.device);
        }
      }
    });

    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 15),
    );
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSubscription?.cancel();
    _scanSubscription = null;
  }

  Future<bool> connect(BluetoothDevice device) async {
    try {
      await device.connect(autoConnect: false);
      _connectedDevice = device;
      
      // Monitor connection state
      device.connectionState.listen((state) {
        _connectionStateController.add(state);
        if (state == BluetoothConnectionState.disconnected) {
          _cleanupConnection();
        }
      });

      List<BluetoothService> services = await device.discoverServices();
      for (BluetoothService s in services) {
        if (s.uuid == Guid(serviceUuid)) {
          for (BluetoothCharacteristic c in s.characteristics) {
            if (c.uuid == Guid(characteristicUuid)) {
              await c.setNotifyValue(true);
              
              _valueSubscription = c.lastValueStream.listen((value) {
                if (value.length >= 17) {
                  final parsedData = _parseTelemetry(Uint8List.fromList(value));
                  _telemetryController.add(parsedData);
                }
              });
              
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      _cleanupConnection();
      return false;
    }
  }

  Future<void> disconnect() async {
    if (_connectedDevice != null) {
      await _connectedDevice!.disconnect();
      _cleanupConnection();
    }
  }

  void _cleanupConnection() {
    _valueSubscription?.cancel();
    _valueSubscription = null;
    _connectedDevice = null;
    _connectionStateController.add(BluetoothConnectionState.disconnected);
  }

  TelemetryData _parseTelemetry(Uint8List bytes) {
    final byteData = ByteData.sublistView(bytes);
    
    // Parse structured 17-byte struct
    // 1. float leanAngle (4 bytes)
    final double leanAngle = byteData.getFloat32(0, Endian.little);
    // 2. float speed (4 bytes)
    final double speed = byteData.getFloat32(4, Endian.little);
    // 3. float lat (4 bytes)
    final double lat = byteData.getFloat32(8, Endian.little);
    // 4. float lng (4 bytes)
    final double lng = byteData.getFloat32(12, Endian.little);
    // 5. uint8_t fuelReserve (1 byte)
    final int fuelReserve = byteData.getUint8(16);

    // Map to TelemetryData model (supporting custom/default fuel bars & extra attributes)
    return TelemetryData(
      rpm: 0.0, // RPM is simulated in viewmodel if not received, or can be added to package in future
      speed: speed,
      oilTemp: 90.0, // Default safe values when not provided in basic packet
      voltage: 13.8,
      fuelBars: fuelReserve == 1 ? 1 : 7, // Map reserve to 1 bar, full to 7 bars
      autonomy: fuelReserve == 1 ? 25 : 142,
      consumption: 15.2,
      gForce: 1.0,
      latitude: lat,
      longitude: lng,
      leanAngle: leanAngle,
    );
  }
}
