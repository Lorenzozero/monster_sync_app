import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'value_tooltip.dart';

// Testi spiegazione per ogni sensore nella griglia
const _sensorExplanations = {
  'AUTONOMIA': 'Stima dei km rimanenti nel serbatoio (17,5 L totali) '
      'calcolata sul consumo medio degli ultimi km. '
      'A 0 km è ora di fare benzina.',
  'CONSUMO': 'Consumo istantaneo in km/L. '
      'La Monster 695 consuma mediamente 14–18 km/L '
      'in condizioni normali. Sopra 20 km/L stai andando piano; '
      'sotto 10 km/L stai spingendo forte.',
  'FORZA G': 'Accelerazione laterale in curva misurata dall\'IMU. '
      '1 G = 9.81 m/s² (il peso della moto sulla strada). '
      'A 0.8G stai spingendo forte in piega — il limite '
      'su gomme stradali è circa 0.85–1.0G.',
};

class SensorGrid extends StatelessWidget {
  final int autonomy;
  final double consumption;
  final double gForce;

  const SensorGrid({
    super.key,
    required this.autonomy,
    required this.consumption,
    required this.gForce,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.panelBg,
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TappableSensorItem(
              value: '$autonomy',
              unit: 'KM',
              label: 'AUTONOMIA',
              explanation: _sensorExplanations['AUTONOMIA']!,
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.1)),
          Expanded(
            child: _TappableSensorItem(
              value: consumption.toStringAsFixed(1),
              unit: 'K/L',
              label: 'CONSUMO',
              explanation: _sensorExplanations['CONSUMO']!,
            ),
          ),
          Container(width: 1, height: 40, color: Colors.white.withValues(alpha: 0.1)),
          Expanded(
            child: _TappableSensorItem(
              value: gForce.toStringAsFixed(1),
              unit: 'G',
              label: 'FORZA G',
              explanation: _sensorExplanations['FORZA G']!,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class _TappableSensorItem extends StatelessWidget {
  final String value;
  final String unit;
  final String label;
  final String explanation;

  const _TappableSensorItem({
    required this.value,
    required this.unit,
    required this.label,
    required this.explanation,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapUp: (details) {
        ValueTooltipLayer.of(context)?.show(
          label: label,
          value: value,
          unit: unit,
          explanation: explanation,
          globalPosition: details.globalPosition,
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value, style: AppTheme.tekoSensor),
              const SizedBox(width: 4),
              Text(
                unit,
                style: AppTheme.interLabel.copyWith(
                  fontSize: 11,
                  color: Colors.white.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: AppTheme.orbitronLabel.copyWith(
              fontSize: 8.0,
              letterSpacing: 0.2,
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
