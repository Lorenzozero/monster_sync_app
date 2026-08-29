import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/theme.dart';
import '../../../../data/services/ble_service.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool _isScanning = false;
  List<Map<String, dynamic>> _devices = [];
  StreamSubscription? _adapterStateSubscription;
  StreamSubscription? _connectionStateSubscription;

  @override
  void initState() {
    super.initState();

    // Lista vuota — nessun device finto pre-caricato.
    // I dispositivi vengono aggiunti SOLO dalla scansione BLE reale.
    _devices = [];

    // Monitora lo stato di connessione BLE in tempo reale
    _connectionStateSubscription = BleService().connectionState.listen((state) {
      if (mounted) {
        setState(() {
          for (var d in _devices) {
            if (d['name'] == 'MonsterSync_BLE') {
              d['connected'] = (state == BluetoothConnectionState.connected);
              d['live'] = (state == BluetoothConnectionState.connected);
            }
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _adapterStateSubscription?.cancel();
    _connectionStateSubscription?.cancel();
    BleService().stopScan();
    super.dispose();
  }

  void _startScan() async {
    // Richiedi permessi BLE + Localizzazione reali prima di scansionare
    final Map<Permission, PermissionStatus> statuses = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();

    final denied = statuses.values.any((s) => s.isDenied || s.isPermanentlyDenied);
    if (denied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Permessi Bluetooth e Localizzazione necessari. Abilitali nelle Impostazioni del telefono.',
            ),
            backgroundColor: AppTheme.alertRed,
            duration: Duration(seconds: 5),
          ),
        );
        await openAppSettings();
      }
      return;
    }

    setState(() => _isScanning = true);

    try {
      await BleService().startScan((device) {
        if (mounted) {
          setState(() {
            final alreadyExists =
                _devices.any((d) => d['mac'] == device.remoteId.str);
            if (!alreadyExists) {
              _devices.insert(0, {
                'name': device.platformName.isNotEmpty
                    ? device.platformName
                    : 'Dispositivo BLE',
                'mac': device.remoteId.str,
                'connected': false,
                'target': device.platformName.contains('MonsterSync'),
                'device': device,
              });
            }
          });
        }
      });

      Timer(const Duration(seconds: 10), () {
        if (mounted && _isScanning) {
          setState(() => _isScanning = false);
          BleService().stopScan();
        }
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isScanning = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore scansione BLE: $e'),
            backgroundColor: AppTheme.alertRed,
          ),
        );
      }
    }
  }

  void _toggleDevice(int index) async {
    final deviceMap = _devices[index];
    final isConnected = deviceMap['connected'] as bool;
    final BluetoothDevice? realDevice = deviceMap['device'];

    if (isConnected) {
      if (realDevice != null) await realDevice.disconnect();
      if (mounted) {
        setState(() => deviceMap['connected'] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Disconnesso da ${deviceMap['name']}'),
            backgroundColor: Colors.white24,
          ),
        );
      }
    } else {
      // Solo connessione BLE reale — nessun fallback simulato
      if (realDevice == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Dispositivo non ancora rilevato. Premi AVVIA SCANSIONE per cercarlo.',
              ),
              backgroundColor: AppTheme.alertRed,
            ),
          );
        }
        return;
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => const Center(
            child: CircularProgressIndicator(color: AppTheme.activeCyan),
          ),
        );
      }

      final success = await BleService().connect(realDevice);

      if (mounted) {
        Navigator.pop(context);
        if (success) {
          setState(() => deviceMap['connected'] = true);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Connesso a ${deviceMap['name']}!'),
              backgroundColor: AppTheme.activeCyan,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '❌ Connessione a ${deviceMap['name']} fallita. Assicurati che l\'ESP32 sia acceso e vicino.',
              ),
              backgroundColor: AppTheme.alertRed,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: const BoxDecoration(
        gradient: AppTheme.metallicDarkRed,
      ),
      padding: const EdgeInsets.only(left: 24, right: 24, top: 48, bottom: 95),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          Text(
            'CONNESSIONE BLE',
            style: AppTheme.orbitronTitle.copyWith(fontSize: 32, fontStyle: FontStyle.normal),
          ),
          const SizedBox(height: 20),
          // Stylized Bluetooth Scanner UI card
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.panelBg,
                border: Border.all(color: Colors.white.withOpacity(0.05)),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isScanning ? 'RICERCA DISPOSITIVI...' : 'DISPOSITIVI RILEVATI',
                        style: AppTheme.orbitronLabel.copyWith(
                          fontSize: 12,
                          color: _isScanning ? AppTheme.activeCyan : Colors.white,
                        ),
                      ),
                      if (_isScanning)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            color: AppTheme.activeCyan,
                            strokeWidth: 2,
                          ),
                        )
                      else
                        const Icon(
                          Icons.bluetooth,
                          color: Colors.white30,
                          size: 16,
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: _devices.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.bluetooth_searching,
                                    color: Colors.white12, size: 48),
                                const SizedBox(height: 12),
                                Text(
                                  'Nessun dispositivo rilevato.',
                                  style: AppTheme.interBody.copyWith(
                                      color: Colors.white30, fontSize: 13),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Accendi la moto e premi AVVIA SCANSIONE.',
                                  style: AppTheme.interLabel.copyWith(
                                      color: Colors.white.withValues(alpha: 0.20), fontSize: 11),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            itemCount: _devices.length,
                            separatorBuilder: (_, __) =>
                                const Divider(color: Colors.white10),
                            itemBuilder: (context, index) {
                              final device = _devices[index];
                              final isConnected = device['connected'] as bool;
                              final isLive = (device['live'] ?? false) as bool;
                              final hasRealDevice = device['device'] != null;

                              // Colore testo: ciano=connesso live, bianco=rilevato,
                              // grigio=mai connesso nella sessione
                              final Color nameColor = isConnected && isLive
                                  ? AppTheme.activeCyan
                                  : hasRealDevice
                                      ? Colors.white70
                                      : Colors.white30;
                              final Color macColor = isConnected && isLive
                                  ? Colors.white54
                                  : Colors.white24;

                              return InkWell(
                                onTap: () => _toggleDevice(index),
                                borderRadius: BorderRadius.circular(8),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12.0, horizontal: 8.0),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            device['name'],
                                            style: AppTheme.interBody.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color: nameColor,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            device['mac'],
                                            style: AppTheme.interLabel
                                                .copyWith(color: macColor),
                                          ),
                                          if (!hasRealDevice)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 2),
                                              child: Text(
                                                'non rilevato in questa sessione',
                                                style: AppTheme.interLabel
                                                    .copyWith(
                                                        color: Colors.white.withValues(alpha: 0.15),
                                                        fontSize: 9),
                                              ),
                                            ),
                                        ],
                                      ),
                                      Row(
                                        children: [
                                          if (isConnected && isLive)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                  right: 8),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppTheme.activeCyan
                                                    .withValues(alpha: 0.15),
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                'LIVE',
                                                style: AppTheme.orbitronLabel
                                                    .copyWith(
                                                  fontSize: 9,
                                                  color: AppTheme.activeCyan,
                                                ),
                                              ),
                                            ),
                                          Icon(
                                            isConnected && isLive
                                                ? Icons.bluetooth_connected
                                                : Icons.bluetooth,
                                            color: isConnected && isLive
                                                ? AppTheme.activeCyan
                                                : hasRealDevice
                                                    ? Colors.white38
                                                    : Colors.white12,
                                            size: 20,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isScanning
                            ? Colors.white10
                            : AppTheme.activeCyan.withOpacity(0.1),
                        foregroundColor: AppTheme.activeCyan,
                        side: BorderSide(
                          color: _isScanning ? Colors.white24 : AppTheme.activeCyan,
                          width: 1,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25),
                        ),
                      ),
                      onPressed: _isScanning ? null : _startScan,
                      child: Text(
                        _isScanning ? 'RICERCA IN CORSO...' : 'AVVIA SCANSIONE',
                        style: AppTheme.orbitronLabel.copyWith(
                          fontSize: 14,
                          color: _isScanning ? Colors.white30 : AppTheme.activeCyan,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
