import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../services/api_service.dart';
import '../../profile/lunara_wallet_screen.dart';

class PartyPlanArrivalDialog {
  /// Shows the prominent 10-minute / 5-minute Arrival Confirmation Modal Bottom Sheet
  static Future<void> showArrivalPrompt(
    BuildContext context, {
    required Map<String, dynamic> plan,
    required bool isHost,
    VoidCallback? onUpdate,
  }) async {
    final venue = (plan['venue'] is Map) ? plan['venue'] as Map<String, dynamic> : <String, dynamic>{};
    final venueName = venue['name']?.toString() ?? plan['venueName']?.toString() ?? 'the venue';
    final planId = plan['planId']?.toString() ?? plan['id']?.toString() ?? '';

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        bool isSubmitting = false;

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Container(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 20,
                    offset: Offset(0, -4),
                  ),
                ],
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Top drag handle
                    Container(
                      width: 44,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Location Pin Header Icon
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: LunaraTheme.electricViolet.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.pin_drop_rounded,
                        color: LunaraTheme.electricViolet,
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      '📍 ARE YOU AT THE VENUE?',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 10),

                    Text(
                      'Your Party Plan at\n"$venueName"\nstarts soon.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey[200]!),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 18, color: LunaraTheme.electricViolet),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Your answer confirms the Party Plan and processes your eligible ₹99 Commitment Deposit refund.',
                              style: TextStyle(fontSize: 12, color: Colors.grey[700], height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    if (isSubmitting)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
                      )
                    else
                      Column(
                        children: [
                          // Primary YES Button
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                setSheetState(() => isSubmitting = true);
                                final uid = ApiService.currentUserId ?? '';
                                final res = await ApiService.confirmArrival(
                                  planId: planId,
                                  userId: uid,
                                  hasArrived: true,
                                );
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }

                                if (res['bothArrived'] == true && context.mounted) {
                                  showBothArrivedSuccessDialog(
                                    context,
                                    venueName: venueName,
                                    plan: plan,
                                  );
                                } else if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('✓ Arrival Confirmed! Waiting for your partner to confirm.'),
                                      backgroundColor: LunaraTheme.electricViolet,
                                    ),
                                  );
                                }
                                onUpdate?.call();
                              },
                              icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                              label: const Text(
                                "✓ YES, I'M HERE",
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                  color: Colors.white,
                                ),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // Secondary NOT YET Button
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton(
                              onPressed: () async {
                                setSheetState(() => isSubmitting = true);
                                final uid = ApiService.currentUserId ?? '';
                                await ApiService.confirmArrival(
                                  planId: planId,
                                  userId: uid,
                                  hasArrived: false,
                                );
                                if (sheetContext.mounted) {
                                  Navigator.pop(sheetContext);
                                }
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Recorded: NOT YET. Confirm when you reach to unlock your refund.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                                onUpdate?.call();
                              },
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: Colors.grey[300]!, width: 1.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: Text(
                                'NOT YET',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// Shows the Celebration Dialog when BOTH participants have arrived and ₹99 refund is issued
  static void showBothArrivedSuccessDialog(
    BuildContext context, {
    required String venueName,
    required Map<String, dynamic> plan,
  }) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  color: Color(0xFFECFDF5),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.celebration_rounded,
                  color: Color(0xFF10B981),
                  size: 40,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                '🎉 BOTH OF YOU HAVE ARRIVED!',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Colors.black87,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your Party Plan at "$venueName" has been successfully confirmed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 16),

              // Arrival checklist
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[200]!),
                ),
                child: Column(
                  children: const [
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                        SizedBox(width: 8),
                        Text('Host reached venue', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 18),
                        SizedBox(width: 8),
                        Text('Partner reached venue', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Wallet refund highlight box
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.3)),
                ),
                child: Column(
                  children: [
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.account_balance_wallet_rounded, color: LunaraTheme.electricViolet, size: 20),
                        SizedBox(width: 6),
                        Text(
                          '💰 Commitment Deposit Refund',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: LunaraTheme.electricViolet,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '₹99 has been returned to your LUNARA Wallet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Available for future party plans, VIP upgrades, and other LUNARA purchases.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogCtx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(dialogCtx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LunaraWalletScreen()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LunaraTheme.electricViolet,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('View Wallet', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
