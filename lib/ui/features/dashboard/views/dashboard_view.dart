import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import '../../../core/theme.dart';
import '../../../widgets/rpm_bar.dart';
import '../../../widgets/sensor_grid.dart';
import '../../../widgets/telltale_item.dart';
import '../../../widgets/value_tooltip.dart';
import '../view_models/dashboard_view_model.dart';

class DashboardView extends StatelessWidget {
  final DashboardViewModel viewModel;

  const DashboardView({
    super.key,
    required this.viewModel,
  });

  Color _getRpmColor(double rpm) {
    final ratio = (rpm / 8500.0).clamp(0.0, 1.0);
    if (ratio < 0.4) {
      final t = ratio / 0.4;
      return Color.lerp(const Color(0xFFFFCC00), const Color(0xFFFF6600), t)!;
    } else if (ratio < 0.7) {
      final t = (ratio - 0.4) / 0.3;
      return Color.lerp(const Color(0xFFFF6600), const Color(0xFFFF1A1A), t)!;
    } else {
      final t = (ratio - 0.7) / 0.3;
      return Color.lerp(const Color(0xFFFF1A1A), const Color(0xFF990000), t)!;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: viewModel,
      builder: (context, _) {
        final telemetry = viewModel.data;

        // Avvolgiamo l'intera Dashboard nel ValueTooltipLayer per abilitare i popup informativi
        return ValueTooltipLayer(
          child: Stack(
            children: [
              // ── BACKGROUND LAYOUT FLOW ─────────────────────────────
              Column(
                children: [
                  // Top black header
                  Container(
                    color: AppTheme.bgColor,
                    padding: EdgeInsets.only(
                      top: MediaQuery.of(context).padding.top + 4.0,
                      left: 12,
                      right: 16,
                      bottom: 10,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Logo (top-left, big) + Title
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // Logo grande in alto a sinistra
                            Image.asset(
                              'assets/ducati_logo.png',
                              height: 76,
                              fit: BoxFit.contain,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'MONSTERSYNC',
                                style: AppTheme.orbitronTitle,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Telltale indicators row (Tappable for tooltips)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // 1. VELOCITÀ
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) {
                                ValueTooltipLayer.of(context)?.show(
                                  label: 'VELOCITÀ',
                                  value: '${telemetry.speed.toInt()}',
                                  unit: 'KM/H',
                                  explanation: 'Velocità istantanea calcolata in tempo reale dai sensori ruota. Rispetta i limiti di velocità stradali!',
                                  globalPosition: details.globalPosition,
                                );
                              },
                              child: TelltaleItem(
                                type: TelltaleType.speed,
                                value: '${telemetry.speed.toInt()}',
                                unit: 'KM/H',
                                isActive: true,
                              ),
                            ),
                            // 2. TEMPERATURA OLIO
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) {
                                ValueTooltipLayer.of(context)?.show(
                                  label: 'TEMP. OLIO',
                                  value: '${telemetry.oilTemp.toInt()}',
                                  unit: '°C',
                                  explanation: 'Temperatura dell\'olio motore (raffreddamento aria/olio). Temperatura ottimale di funzionamento: 80°C - 115°C.',
                                  globalPosition: details.globalPosition,
                                );
                              },
                              child: TelltaleItem(
                                type: TelltaleType.temp,
                                value: '${telemetry.oilTemp.toInt()}',
                                unit: '°C',
                                isAlert: telemetry.oilTemp >= 115.0,
                              ),
                            ),
                            // 3. TENSIONE BATTERIA
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) {
                                ValueTooltipLayer.of(context)?.show(
                                  label: 'VOLTAGGIO',
                                  value: telemetry.voltage.toStringAsFixed(1),
                                  unit: 'V',
                                  explanation: 'Tensione dell\'impianto elettrico. Spento: ~12.5V. Acceso: 13.5V - 14.5V (indica l\'alternatore in carica).',
                                  globalPosition: details.globalPosition,
                                );
                              },
                              child: TelltaleItem(
                                type: TelltaleType.voltage,
                                value: telemetry.voltage.toStringAsFixed(1),
                                unit: 'V',
                              ),
                            ),
                            // 4. BENZINA
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (details) {
                                final pct = (telemetry.fuelBars / 7 * 100).toInt();
                                ValueTooltipLayer.of(context)?.show(
                                  label: 'CARBURANTE',
                                  value: '$pct',
                                  unit: '%',
                                  explanation: 'Livello del carburante stimato nel serbatoio. Capacità: 14 litri (inclusa riserva di 3.5 litri).',
                                  globalPosition: details.globalPosition,
                                );
                              },
                              child: TelltaleItem(
                                type: TelltaleType.fuel,
                                fuelBars: telemetry.fuelBars,
                                isActive: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Transparent spacer — 3D model floats over this
                  SizedBox(
                    height: (MediaQuery.of(context).size.height * 0.53 - 110.0)
                        .clamp(180.0, 360.0),
                  ),

                  // Bottom metallic-red section
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF0A0A0A),
                            Color(0xFF3F0002),
                            Color(0xFF7A0002),
                          ],
                          stops: [0.0, 0.40, 1.0],
                        ),
                      ),
                      padding: const EdgeInsets.only(
                        left: 16,
                        right: 16,
                        top: 24,
                        bottom: 95, // Clear above floating nav bar
                      ),
                      child: Stack(
                        children: [
                          // Vertical RPM Bar on the left
                          Positioned(
                            left: 0,
                            top: 0,
                            bottom: 0,
                            child: SizedBox(
                              width: 20,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 50),
                                child: RpmBar(rpm: telemetry.rpm),
                              ),
                            ),
                          ),
                          // RPM number + sensor grid (shifted right)
                          Padding(
                            padding: const EdgeInsets.only(left: 36),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Text(
                                  'GIRI MOTORE',
                                  style: AppTheme.orbitronLabel
                                      .copyWith(fontSize: 14),
                                ),
                                // Giri motore cliccabili
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (details) {
                                    ValueTooltipLayer.of(context)?.show(
                                      label: 'GIRI MOTORE',
                                      value: '${telemetry.rpm.toInt()}',
                                      unit: 'RPM',
                                      explanation: 'Regime di rotazione del motore Desmodromico L-twin. Coppia massima erogata a 6.750 RPM. Limitatore a 8.500 RPM.',
                                      globalPosition: details.globalPosition,
                                    );
                                  },
                                  child: Text(
                                    '${telemetry.rpm.toInt()}',
                                    style: AppTheme.tekoHuge.copyWith(
                                      color: _getRpmColor(telemetry.rpm),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                SensorGrid(
                                  autonomy: telemetry.autonomy,
                                  consumption: telemetry.consumption,
                                  gForce: telemetry.gForce,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),

              // ── FLOATING 3D MODEL ────────────────────────────────────
              Positioned(
                top: 195,
                left: 0,
                right: 0,
                height: 295, // Slightly smaller
                child: IgnorePointer(
                  ignoring: false,
                  child: ModelViewer(
                    src: 'assets/ducati_monster_3d.glb',
                    alt: 'Ducati 3D Model',
                    cameraControls: true,
                    disableZoom: true,
                    autoRotate: false,
                    cameraOrbit: '165deg 75deg 70%', // User requested 70%
                    shadowIntensity: 1.0,
                    shadowSoftness: 0.5,
                    environmentImage: 'neutral',
                    backgroundColor: Colors.transparent,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
