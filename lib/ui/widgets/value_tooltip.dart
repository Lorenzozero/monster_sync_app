import 'dart:async';
import 'package:flutter/material.dart';
import '../core/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ValueTooltip overlay
//
// Uso: avvolgi la radice della pagina con ValueTooltipLayer.
// Poi chiama ValueTooltipLayer.of(context).show(...) da qualsiasi widget figlio.
// ─────────────────────────────────────────────────────────────────────────────

class _TooltipData {
  final String label;
  final String value;
  final String unit;
  final String explanation;
  final Offset position; // posizione tap globale

  const _TooltipData({
    required this.label,
    required this.value,
    required this.unit,
    required this.explanation,
    required this.position,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
class ValueTooltipLayer extends StatefulWidget {
  final Widget child;

  const ValueTooltipLayer({super.key, required this.child});

  static ValueTooltipLayerState? of(BuildContext context) =>
      context.findAncestorStateOfType<ValueTooltipLayerState>();

  @override
  State<ValueTooltipLayer> createState() => ValueTooltipLayerState();
}

class ValueTooltipLayerState extends State<ValueTooltipLayer>
    with SingleTickerProviderStateMixin {
  _TooltipData? _data;
  Timer? _timer;
  late AnimationController _animCtrl;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 180));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  void show({
    required String label,
    required String value,
    required String unit,
    required String explanation,
    required Offset globalPosition,
  }) {
    _timer?.cancel();
    setState(() {
      _data = _TooltipData(
        label: label,
        value: value,
        unit: unit,
        explanation: explanation,
        position: globalPosition,
      );
    });
    _animCtrl.forward(from: 0);

    // Auto-dismiss dopo 2 secondi
    _timer = Timer(const Duration(seconds: 2), _dismiss);
  }

  void _dismiss() {
    _animCtrl.reverse().then((_) {
      if (mounted) setState(() => _data = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_data != null)
          // Sfondo scuro e cattura tap esterno per chiudere
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => _dismiss(),
              child: Container(
                color: Colors.black.withValues(alpha: 0.6), // Scurisce e focalizza lo schermo
                child: FadeTransition(
                  opacity: _fadeAnim,
                  child: Center(
                    child: _TooltipBubble(data: _data!),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// La bolla visiva (Centrata sul display)
// ─────────────────────────────────────────────────────────────────────────────
class _TooltipBubble extends StatelessWidget {
  final _TooltipData data;

  const _TooltipBubble({required this.data});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 290,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: AppTheme.activeCyan.withValues(alpha: 0.6),
                width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.85),
                blurRadius: 25,
                spreadRadius: 3,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: AppTheme.activeCyan.withValues(alpha: 0.12),
                blurRadius: 25,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Riga Titolo + Valore
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    data.label,
                    style: AppTheme.orbitronLabel.copyWith(
                        fontSize: 10,
                        color: AppTheme.activeCyan,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5),
                  ),
                  const Spacer(),
                  Text(
                    data.value,
                    style: AppTheme.tekoSensor.copyWith(fontSize: 28, height: 1),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    data.unit,
                    style: AppTheme.interLabel
                        .copyWith(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Container(
                  height: 1,
                  color: Colors.white.withValues(alpha: 0.1)),
              const SizedBox(height: 12),
              // Descrizione tecnica sintetica
              Text(
                data.explanation,
                style: AppTheme.interBody.copyWith(
                    fontSize: 12.0,
                    color: Colors.white.withValues(alpha: 0.85),
                    height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
