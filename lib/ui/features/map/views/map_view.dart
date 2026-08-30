import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../../core/theme.dart';
import '../../dashboard/view_models/dashboard_view_model.dart';
import '../../../widgets/value_tooltip.dart';
import '../../pacenotes/views/pace_notes_view.dart';

class TrailPoint {
  final LatLng coord;
  final double leanAngle;
  TrailPoint(this.coord, this.leanAngle);
}

class MapView extends StatefulWidget {
  final DashboardViewModel viewModel;

  const MapView({super.key, required this.viewModel});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  final MapController _mapController = MapController();
  final List<TrailPoint> _trail = [];
  bool _followBike = true;
  LatLng _lastCoord = const LatLng(43.9975, 11.3718);
  double _lastLean = 0.0;
  double _lastSpeed = 0.0;
  
  @override
  void initState() {
    super.initState();
    
    // Pre-populate with a beautiful mock route (Mugello/Futa track)
    // so it displays instantly before the BLE connects.
    _prepopulateMockTrail();

    // Listen to telemetry updates from viewmodel
    widget.viewModel.addListener(_onTelemetryUpdate);
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onTelemetryUpdate);
    _mapController.dispose();
    super.dispose();
  }

  void _prepopulateMockTrail() {
    // Generate circular path around Mugello circuit coordinates
    const double centerLat = 43.9975;
    const double centerLng = 11.3718;
    const int numPoints = 80;

    for (int i = 0; i < numPoints; i++) {
      final double angle = (i / numPoints) * 2 * math.pi;
      // Elliptical path simulation
      final double latOffset = 0.003 * math.sin(angle);
      final double lngOffset = 0.005 * math.cos(angle * 2);
      
      // Simulate lean angle based on turns
      double lean = 0.0;
      if (angle > 0.5 && angle < 2.0) {
        lean = -35 * math.sin((angle - 0.5) / 1.5 * math.pi); // Left lean
      } else if (angle > 3.5 && angle < 5.5) {
        lean = 42 * math.sin((angle - 3.5) / 2.0 * math.pi); // Right lean
      }

      _trail.add(
        TrailPoint(
          LatLng(centerLat + latOffset, centerLng + lngOffset),
          lean,
        ),
      );
    }
    
    _lastCoord = _trail.last.coord;
    _lastLean = _trail.last.leanAngle;
  }

  void _onTelemetryUpdate() {
    final telemetry = widget.viewModel.data;
    final newCoord = LatLng(telemetry.latitude, telemetry.longitude);

    // If coordinates are valid and different from last, append to trail
    if (telemetry.latitude != 0.0 && telemetry.longitude != 0.0) {
      // Avoid duplicated adjacent points
      if (_trail.isEmpty || _trail.last.coord.latitude != newCoord.latitude || _trail.last.coord.longitude != newCoord.longitude) {
        setState(() {
          _trail.add(TrailPoint(newCoord, telemetry.leanAngle));
          _lastCoord = newCoord;
          _lastLean = telemetry.leanAngle;
          _lastSpeed = telemetry.speed;

          // Cap the trail length to prevent memory bloating
          if (_trail.length > 500) {
            _trail.removeAt(0);
          }
        });

        if (_followBike) {
          _mapController.move(newCoord, _mapController.camera.zoom);
        }
      }
    } else {
      // If simulated fallback, update local variables to mirror simulation
      setState(() {
        _lastLean = telemetry.leanAngle;
        _lastSpeed = telemetry.speed;
        // In simulation, we orbit the track marker by sliding index of pre-populated track
        if (_trail.isNotEmpty) {
          final simIndex = (DateTime.now().millisecondsSinceEpoch ~/ 150) % _trail.length;
          _lastCoord = _trail[simIndex].coord;
        }
      });
      if (_followBike && _trail.isNotEmpty) {
        _mapController.move(_lastCoord, _mapController.camera.zoom);
      }
    }
  }

  List<Polyline> _buildHeatmapPolylines() {
    List<Polyline> segments = [];
    for (int i = 0; i < _trail.length - 1; i++) {
      final p1 = _trail[i];
      final p2 = _trail[i + 1];
      segments.add(
        Polyline(
          points: [p1.coord, p2.coord],
          color: _getLeanColor(p1.leanAngle),
          strokeWidth: 4.5,
        ),
      );
    }
    return segments;
  }

  Color _getLeanColor(double lean) {
    final absLean = lean.abs();
    if (absLean < 15) {
      return AppTheme.activeCyan; // Upright / slight lean (Cyan)
    } else if (absLean < 30) {
      return const Color(0xFFFFCC00); // Mild cornering (Yellow)
    } else {
      return AppTheme.alertRed; // Extreme knee-down lean (Red)
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueTooltipLayer(
      child: Builder(
        builder: (context) {
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'LIVE GPS MAP',
                  style: AppTheme.orbitronTitle.copyWith(fontSize: 32, fontStyle: FontStyle.normal),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Pace notes da un GPX
                    IconButton(
                      tooltip: 'Pace notes da un file GPX',
                      icon: const Icon(Icons.route, color: AppTheme.activeCyan),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const PaceNotesView()),
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        _followBike ? Icons.my_location : Icons.location_searching,
                        color: _followBike ? AppTheme.activeCyan : Colors.white38,
                      ),
                      onPressed: () {
                        setState(() {
                          _followBike = !_followBike;
                        });
                        if (_followBike) {
                          _mapController.move(_lastCoord, 14.5);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Tracciamento percorso. Colore scia in base all\'inclinazione dell\'IMU.',
              style: AppTheme.interLabel.copyWith(color: AppTheme.textMuted, fontSize: 10),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: Column(
                children: [
                  // Real OSM Map Widget
                  Expanded(
                    flex: 3,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _lastCoord,
                            initialZoom: 14.5,
                            maxZoom: 18.0,
                            minZoom: 10.0,
                          ),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.monstersync.app',
                            ),
                            PolylineLayer(
                              polylines: _buildHeatmapPolylines(),
                            ),
                            MarkerLayer(
                              markers: [
                                // Posizione attuale: modello 3D reale della moto,
                                // stesso rig del cruscotto landscape.
                                Marker(
                                  point: _lastCoord,
                                  width: 90,
                                  height: 90,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      // Alone di localizzazione sotto la moto
                                      Container(
                                        width: 44,
                                        height: 44,
                                        decoration: BoxDecoration(
                                          color: AppTheme.activeCyan.withOpacity(0.18),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: AppTheme.activeCyan.withOpacity(0.7), width: 2),
                                          boxShadow: [
                                            BoxShadow(
                                              color: AppTheme.activeCyan.withOpacity(0.5),
                                              blurRadius: 12,
                                              spreadRadius: 2,
                                            )
                                          ],
                                        ),
                                      ),
                                      const IgnorePointer(
                                        child: SizedBox(
                                          width: 70,
                                          height: 70,
                                          child: ModelViewer(
                                            src: 'assets/ducati_monster_3d.glb',
                                            alt: 'Ducati 3D Model',
                                            cameraControls: false,
                                            disableZoom: true,
                                            autoRotate: false,
                                            cameraOrbit: '165deg 75deg 70%',
                                            shadowIntensity: 0.0,
                                            backgroundColor: Colors.transparent,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Live Stats display (tappable for tooltips)
                  Expanded(
                    flex: 2,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.panelBg,
                        border: Border.all(color: Colors.white.withOpacity(0.05)),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) {
                                    final side = _lastLean == 0.0
                                        ? 'DIR.'
                                        : (_lastLean > 0 ? 'DX' : 'SX');
                                    ValueTooltipLayer.of(context)?.show(
                                      label: 'PIEGA',
                                      value: '${_lastLean.abs().toStringAsFixed(0)}°',
                                      unit: side,
                                      explanation: 'MPU-6050 sull\'ESP32. Misura accelerazione e giroscopio su 3 assi → calcola angolo di piega, pitch (impennate) e yaw.',
                                      globalPosition: details.globalPosition,
                                    );
                                  },
                                  child: _buildMiniStat(
                                    'PIEGA',
                                    '${_lastLean.abs().toStringAsFixed(0)}°',
                                    _lastLean == 0.0
                                        ? 'DIR.'
                                        : (_lastLean > 0 ? 'DX' : 'SX'),
                                    _getLeanColor(_lastLean),
                                  ),
                                ),
                              ),
                              Container(width: 1, height: 40, color: Colors.white10),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) {
                                    ValueTooltipLayer.of(context)?.show(
                                      label: 'VELOCITÀ',
                                      value: '${_lastSpeed.toStringAsFixed(0)}',
                                      unit: 'KM/H',
                                      explanation: 'Velocità reale rilevata tramite il chip GPS a 10Hz Beitian, indipendente dal tachimetro analogico della moto.',
                                      globalPosition: details.globalPosition,
                                    );
                                  },
                                  child: _buildMiniStat(
                                    'VELOCITÀ',
                                    '${_lastSpeed.toStringAsFixed(0)}',
                                    'KM/H',
                                    Colors.white,
                                  ),
                                ),
                              ),
                              Container(width: 1, height: 40, color: Colors.white10),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) {
                                    ValueTooltipLayer.of(context)?.show(
                                      label: 'TRAIL',
                                      value: '${_trail.length}',
                                      unit: 'PUNTI',
                                      explanation: '98 mm. Distanza tra asse sterzo e contatto ruota ant. Alto trail = più stabilità rettilinea, meno agilità in curva stretta.',
                                      globalPosition: details.globalPosition,
                                    );
                                  },
                                  child: _buildMiniStat(
                                    'TRAIL',
                                    '${_trail.length}',
                                    'PUNTI',
                                    AppTheme.activeCyan,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  ),
);
  }

  Widget _buildMiniStat(String label, String value, String sub, Color valColor) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          label,
          textAlign: TextAlign.center,
          style: AppTheme.orbitronLabel.copyWith(fontSize: 10, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: AppTheme.tekoHuge.copyWith(fontSize: 36, height: 1, color: valColor),
            ),
            const SizedBox(width: 3),
            Text(
              sub,
              style: AppTheme.interLabel.copyWith(fontSize: 10, color: AppTheme.textMuted),
            ),
          ],
        ),
      ],
    );
  }
}
