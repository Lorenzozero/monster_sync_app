import 'package:flutter/material.dart';
import '../core/theme.dart';

class FuelBar extends StatelessWidget {
  final int activeBars; // 0 to 8

  const FuelBar({
    super.key,
    required this.activeBars,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      // Stack from bottom to top
      verticalDirection: VerticalDirection.up,
      children: List.generate(8, (index) {
        final isActive = index < activeBars;
        return Container(
          width: 16,
          height: 3,
          margin: EdgeInsets.only(bottom: index == 7 ? 0 : 1.5),
          decoration: BoxDecoration(
            color: isActive ? AppTheme.activeCyan : const Color(0xFF262626),
            borderRadius: BorderRadius.circular(0.75),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: AppTheme.activeCyan.withOpacity(0.5),
                      blurRadius: 5,
                      spreadRadius: 0.75,
                    )
                  ]
                : null,
          ),
        );
      }),
    );
  }
}
