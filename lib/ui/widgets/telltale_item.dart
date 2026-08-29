import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../core/theme.dart';
import 'fuel_bar.dart';

enum TelltaleType { speed, temp, voltage, fuel }

class TelltaleItem extends StatelessWidget {
  final TelltaleType type;
  final String value;
  final String unit;
  final bool isActive;
  final bool isAlert;
  final int fuelBars; // only for TelltaleType.fuel

  const TelltaleItem({
    super.key,
    required this.type,
    this.value = '',
    this.unit = '',
    this.isActive = false,
    this.isAlert = false,
    this.fuelBars = 7,
  });

  @override
  Widget build(BuildContext context) {
    // Determine colors
    Color color = AppTheme.inactiveGray;
    if (isAlert) {
      color = AppTheme.alertRed;
    } else if (isActive) {
      color = AppTheme.activeCyan;
    }

    // Get SVG string
    String svgString = '';
    switch (type) {
      case TelltaleType.speed:
        // Nessuna icona per velocità (rimossa per pulizia)
        svgString = '';
        break;
      case TelltaleType.temp:
        svgString =
            '<svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M19.428 15.428a2 2 0 00-1.022-.547l-2.387-.477a6 6 0 00-3.86.517l-.318.158a6 6 0 01-3.86.517L6.05 15.21a2 2 0 00-1.806.547M8 4h8l-1 1v5.172a2 2 0 00.586 1.414l5 5c1.26 1.26.367 3.414-1.415 3.414H4.828c-1.782 0-2.674-2.154-1.414-3.414l5-5A2 2 0 009 10.172V5L8 4z"></path></svg>';
        break;
      case TelltaleType.voltage:
        svgString =
            '<svg fill="none" stroke="currentColor" stroke-width="2" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M4 7h16a1 1 0 011 1v8a1 1 0 01-1 1H4a1 1 0 01-1-1V8a1 1 0 011-1zm6 4v2m4-2v2"></path><path stroke-linecap="round" stroke-linejoin="round" d="M22 11v2"></path></svg>';
        break;
      case TelltaleType.fuel:
        svgString =
            '<svg fill="none" stroke="currentColor" stroke-width="2.5" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" d="M4 21h10M6 21V6a2 2 0 012-2h4a2 2 0 012 2v15m-5-13h2m-6 9h8m3-2v-4a2 2 0 014 0v4m-4-2h4"></path></svg>';
        break;
    }

    final double iconSize = (type == TelltaleType.fuel) ? 26.0 : 20.0;

    Widget? finalIcon;
    if (svgString.isNotEmpty) {
      final iconWidget = SvgPicture.string(
        svgString,
        width: iconSize,
        height: iconSize,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );

      // Apply glow effect if active/alert
      finalIcon = iconWidget;
      if (isActive || isAlert) {
        finalIcon = Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withOpacity(0.4),
                blurRadius: 8,
                spreadRadius: 1,
              )
            ],
          ),
          child: iconWidget,
        );
      }
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (finalIcon != null) ...[
          finalIcon,
          const SizedBox(width: 6),
        ],
        if (type == TelltaleType.fuel)
          FuelBar(activeBars: fuelBars)
        else
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: AppTheme.tekoTelltale.copyWith(
                  color: isAlert ? AppTheme.alertRed : Colors.white,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                unit,
                style: AppTheme.interLabel.copyWith(
                  fontSize: 10,
                  color: isAlert ? AppTheme.alertRed : AppTheme.inactiveGray,
                ),
              ),
            ],
          ),
      ],
    );
  }
}
