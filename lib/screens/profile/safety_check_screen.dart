import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../models/user.dart';
import '../../widgets/lunara_profile_image.dart';

class SafetyCheckScreen extends StatefulWidget {
  final User? user;
  const SafetyCheckScreen({super.key, this.user});

  @override
  State<SafetyCheckScreen> createState() => _SafetyCheckScreenState();
}

class _SafetyCheckScreenState extends State<SafetyCheckScreen> {
  bool? _feltSafe;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'SAFETY CHECK',
          style: TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w900,
            fontSize: 18,
            letterSpacing: 2,
            fontFamily: 'AllroundGothic',
          ),
        ),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Privacy Banner
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.1)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lock_outline_rounded, color: LunaraTheme.electricViolet, size: 20),
                  SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Your feedback is 100% private and never shared with your partner.',
                      style: TextStyle(
                        color: Colors.black87,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Experience Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: LunaraTheme.premiumCardShadow,
                border: Border.all(color: Colors.grey[100]!),
              ),
              child: Row(
                children: [
                  LunaraProfileImage(
                    user: widget.user,
                    radius: 28,
                    showGradientBorder: true,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Rate your experience with',
                          style: TextStyle(
                            color: Colors.black54,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.user?.fullName ?? 'Sarah J.',
                          style: const TextStyle(
                            color: Colors.black,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'ELARA VELVET',
                        style: TextStyle(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'FEB 22',
                        style: TextStyle(
                          color: LunaraTheme.electricViolet,
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 48),
            // Question
            const Text(
              'DID YOU FEEL SAFE TONIGHT?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            // Action Buttons
            Row(
              children: [
                Expanded(
                  child: _buildSafetyButton(
                    'YES',
                    Icons.check_circle_outline_rounded,
                    _feltSafe == true,
                    () => setState(() => _feltSafe = true),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSafetyButton(
                    'NO',
                    Icons.warning_amber_rounded,
                    _feltSafe == false,
                    () => setState(() => _feltSafe = false),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSafetyButton(String label, IconData icon, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 32),
        decoration: BoxDecoration(
          color: isSelected ? LunaraTheme.electricViolet.withValues(alpha: 0.05) : Colors.grey[50],
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected ? LunaraTheme.electricViolet : Colors.grey[200]!,
            width: 2,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ] : [],
        ),
        child: Column(
          children: [
            Icon(
              icon,
              color: isSelected ? LunaraTheme.electricViolet : Colors.grey[300],
              size: 40,
            ),
            const SizedBox(height: 16),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? LunaraTheme.electricViolet : Colors.black,
                fontSize: 14,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
