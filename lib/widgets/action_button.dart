import 'package:flutter/material.dart';
import '../core/theme.dart';

class LunaraActionButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  const LunaraActionButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final bool isDisabled = onPressed == null || isLoading;

    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        gradient: isDisabled ? null : LunaraTheme.purpleGradient,
        color: isDisabled ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.1) : null,
        borderRadius: BorderRadius.circular(16),
        boxShadow: isDisabled ? null : LunaraTheme.premiumCardShadow,
      ),
      child: ElevatedButton(
        onPressed: isDisabled ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          foregroundColor: isDisabled ? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
      ),
    );
  }
}
