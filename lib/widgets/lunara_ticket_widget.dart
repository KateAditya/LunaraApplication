import 'package:flutter/material.dart';
import '../core/theme.dart';

class LunaraTicketWidget extends StatelessWidget {
  final Widget topSection;
  final Widget bottomSection;
  final Gradient? gradient;
  final Color? cardColor;
  final double borderRadius;
  final double cutoutRadius;
  final Color cutoutColor;
  final Color dashColor;
  final List<BoxShadow>? boxShadow;
  final double? width;
  final Border? border;

  const LunaraTicketWidget({
    super.key,
    required this.topSection,
    required this.bottomSection,
    this.gradient,
    this.cardColor,
    this.borderRadius = 24.0,
    this.cutoutRadius = 12.0,
    this.cutoutColor = LunaraTheme.midnightBlack,
    this.dashColor = Colors.white54,
    this.boxShadow,
    this.width,
    this.border,
  });

  @override
  Widget build(BuildContext context) {
    final defaultGradient = const LinearGradient(
      colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9), Color(0xFF4C1D95)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final defaultShadows = [
      BoxShadow(
        color: LunaraTheme.electricViolet.withValues(alpha: 0.35),
        blurRadius: 20,
        offset: const Offset(0, 10),
      ),
    ];

    return Container(
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        color: gradient == null ? cardColor : null,
        gradient: cardColor == null ? (gradient ?? defaultGradient) : null,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
        boxShadow: boxShadow ?? defaultShadows,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Section
          topSection,

          // Dashed Divider line with left & right circular cutouts
          Row(
            children: [
              Container(
                width: cutoutRadius,
                height: cutoutRadius * 2,
                decoration: BoxDecoration(
                  color: cutoutColor,
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(cutoutRadius),
                  ),
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Flex(
                      direction: Axis.horizontal,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      mainAxisSize: MainAxisSize.max,
                      children: List.generate(
                        (constraints.constrainWidth() / 10).floor(),
                        (index) => SizedBox(
                          width: 5,
                          height: 1.5,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: dashColor,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Container(
                width: cutoutRadius,
                height: cutoutRadius * 2,
                decoration: BoxDecoration(
                  color: cutoutColor,
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(cutoutRadius),
                  ),
                ),
              ),
            ],
          ),

          // Bottom Section
          bottomSection,
        ],
      ),
    );
  }
}
