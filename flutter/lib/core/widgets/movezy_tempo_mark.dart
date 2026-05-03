import 'package:flutter/material.dart';
import 'package:movezy/core/theme/app_theme.dart';

/// Branded “tempo carrying goods” mark — use instead of generic bolt/spark icons.
class MovezyTempoMark extends StatelessWidget {
  final double size;
  final Color? truckColor;
  final Color? goodsColor;

  const MovezyTempoMark({
    super.key,
    this.size = 24,
    this.truckColor,
    this.goodsColor,
  });

  @override
  Widget build(BuildContext context) {
    final t = truckColor ?? AppColors.primary;
    final g = goodsColor ?? AppColors.warning;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(
            Icons.local_shipping_rounded,
            size: size * 0.88,
            color: t,
          ),
          Positioned(
            right: -size * 0.04,
            bottom: -size * 0.02,
            child: Icon(
              Icons.inventory_2_rounded,
              size: size * 0.44,
              color: g,
            ),
          ),
        ],
      ),
    );
  }
}
