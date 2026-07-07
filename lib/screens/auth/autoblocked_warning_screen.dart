import 'package:flutter/material.dart';
import '../../core/theme.dart';
import 'login_hub.dart';

class AutoblockedWarningScreen extends StatelessWidget {
  final String reason;

  const AutoblockedWarningScreen({
    super.key,
    required this.reason,
  });

  void _showSupportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.support_agent, color: LunaraTheme.primaryRich),
            const SizedBox(width: 10),
            Text(
              'ADMIN SUPPORT',
              style: LunaraTheme.headingStyle.copyWith(fontSize: 18),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Case Reference: #LUN-${DateTime.now().year}-${(10000 + DateTime.now().millisecond).toString()}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'To appeal this automatic suspension, please contact the Lunara Admin Team with your case details:\n\n'
              '• Email: support@lunara.com\n'
              '• Support Line: +1 (800) LUNARA-HELP\n\n'
              'The admin team will review the reports/blocks and manual appeals. If approved, your account will be instantly unblocked.',
              style: TextStyle(
                fontSize: 14,
                color: Theme.of(context).colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'CLOSE',
              style: TextStyle(
                color: LunaraTheme.primaryRich,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.redAccent.withValues(alpha: 0.05),
              Theme.of(context).scaffoldBackgroundColor,
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(),
                
                // Pulsing Warning Icon
                TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.8, end: 1.0),
                  duration: const Duration(seconds: 1),
                  curve: Curves.elasticOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: [Colors.deepOrange, Colors.redAccent],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.redAccent.withValues(alpha: 0.3),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.gavel_rounded,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
                
                const SizedBox(height: 32),
                
                Text(
                  'ACCOUNT SUSPENDED',
                  style: LunaraTheme.headingStyle.copyWith(
                    fontSize: 24,
                    color: Colors.redAccent,
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                
                const SizedBox(height: 16),
                
                // Warning Box (Glassmorphism card)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Autoblock Safety Flag Triggered',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: Colors.orange,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        reason,
                        style: TextStyle(
                          fontSize: 14,
                          color: Theme.of(context).colorScheme.onSurface,
                          height: 1.4,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 24),
                
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Text(
                    'To protect our community, accounts receiving 10 blocks from unique users are automatically logged out and suspended from accessing Lunara services pending review.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                
                const Spacer(),
                
                // Admin Support Button
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.primaryRich,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    onPressed: () => _showSupportDialog(context),
                    icon: const Icon(Icons.support_agent),
                    label: const Text(
                      'ADMIN SUPPORT',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                
                // Back to Login Button
                TextButton(
                  onPressed: () {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginHub()),
                      (route) => false,
                    );
                  },
                  child: Text(
                    'BACK TO LOGIN',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
