import 'package:flutter/material.dart';
import '../core/theme.dart';

class RpmBar extends StatelessWidget {
  final double rpm;
  final double maxRpm;

  const RpmBar({
    super.key,
    required this.rpm,
    this.maxRpm = 8500,
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: rpm),
      duration: const Duration(milliseconds: 120), // Animazione reattiva e fluidissima
      curve: Curves.easeOutQuad,
      builder: (context, animRpm, child) {
        final percentage = (animRpm / maxRpm).clamp(0.0, 1.0);

        return Container(
          width: 20,
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F0F),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 8,
                offset: const Offset(3, 0),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // ── LIQUID FILL ANIMATO ──────────────────────────────────────
                FractionallySizedBox(
                  heightFactor: percentage,
                  widthFactor: 1.0,
                  child: Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      Container(
                        decoration: const BoxDecoration(
                          gradient: AppTheme.rpmGradient,
                        ),
                      ),
                      // ── CAPPUCCIO BIANCO ILLUMINATO AL TOP DELLA BARRA ──────────
                      if (percentage > 0.0)
                        Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withOpacity(0.95),
                                blurRadius: 8,
                                spreadRadius: 1.5,
                              ),
                              BoxShadow(
                                color: const Color(0xFFFF3333).withOpacity(0.6),
                                blurRadius: 12,
                                spreadRadius: 2.5,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                // ── LINEE DI SEPARAZIONE DEI SEGMENTI ────────────────────────
                Column(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: List.generate(24, (index) => Container(
                    height: 2.0,
                    color: const Color(0xFF0F0F0F), // Stesso colore dello sfondo barra
                  )),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
