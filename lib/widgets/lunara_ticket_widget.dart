import 'package:flutter/material.dart';
import '../core/theme.dart';

class LunaraTicketWidget extends StatelessWidget {
  final Widget topSection;
  final Widget bottomSection;
  final Gradient? gradient;
  final double borderRadius;
  final double cutoutRadius;
  final Color cutoutColor;
  final List<BoxShadow>? boxShadow;
  final double? width;

  const LunaraTicketWidget({
    super.key,
    required this.topSection,
    required this.bottomSection,
    this.gradient,
    this.borderRadius = 24.0,
    this.cutoutRadius = 12.0,
    this.cutoutColor = LunaraTheme.midnightBlack,
    this.boxShadow,
    this.width,
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
        gradient: gradient ?? defaultGradient,
        borderRadius: BorderRadius.circular(borderRadius),
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
                        (index) => const SizedBox(
                          width: 5,
                          height: 1.5,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.white54,
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
