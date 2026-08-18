import 'package:flutter/material.dart';
import '../../../core/theme.dart';
import '../../../services/api_service.dart';
import '../../profile/lunara_wallet_screen.dart';

class PartyPlanArrivalDialog {
  /// Shows the prominent Partner Arrival Confirmation Modal Bottom Sheet
  static Future<void> showArrivalPrompt(
    BuildContext context, {
    required Map<String, dynamic> plan,
    required bool isHost,
    VoidCallback? onUpdate,
  }) async {
    final venue = (plan['venue'] is Map) ? plan['venue'] as Map<String, dynamic> : <String, dynamic>{};
    final venueName = venue['name']?.toString() ?? plan['venueName']?.toString() ?? 'the venue';
    final planId = plan['planId']?.toString() ?? plan['id']?.toString() ?? '';

    // Resolve Partner profile
    final acceptedReq = (plan['acceptedRequest'] is Map)
        ? plan['acceptedRequest'] as Map<String, dynamic>
        : (plan['request'] is Map ? plan['request'] as Map<String, dynamic> : <String, dynamic>{});
    final partnerData = isHost
        ? ((acceptedReq['requester'] is Map)
            ? acceptedReq['requester'] as Map<String, dynamic>
            : (plan['joiner'] is Map
                ? plan['joiner'] as Map<String, dynamic>
                : (plan['partner'] is Map ? plan['partner'] as Map<String, dynamic> : <String, dynamic>{})))
        : ((plan['creator'] is Map)
            ? plan['creator'] as Map<String, dynamic>
            : (plan['user'] is Map
                ? plan['user'] as Map<String, dynamic>
                : (plan['host'] is Map ? plan['host'] as Map<String, dynamic> : <String, dynamic>{})));

    final partnerName = '${partnerData['firstName'] ?? (isHost ? 'Party Partner' : 'Host')} ${partnerData['lastName'] ?? ''}'.trim();
    final rawPhoto = partnerData['profileImageUrl'] ?? partnerData['profilePhotoUrl'] ?? partnerData['primaryPhoto'];
    final partnerPhotoUrl = ApiService.formatImageUrl(rawPhoto);

    // Resolve scheduled date/time string
    String scheduledTimeStr = plan['startTime']?.toString() ?? plan['planTime']?.toString() ?? 'Starting soon';
    final rawDateTime = plan['planDateTime'] ?? plan['eventDateTime'] ?? plan['partyDate'];
    if (rawDateTime != null) {
      try {
        final dt = DateTime.parse(rawDateTime.toString()).toLocal();
        const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        final w = weekdayNames[dt.weekday - 1];
        final m = monthNames[dt.month - 1];
        final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
        final ampm = dt.hour >= 12 ? 'PM' : 'AM';
        final minute = dt.minute.toString().padLeft(2, '0');
        scheduledTimeStr = '$w, ${dt.day} $m • $hour:$minute $ampm';
      } catch (_) {}
    }

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
                    const SizedBox(height: 18),

                    // Header title
                    const Text(
                      'Partner Arrival Confirmation',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Your Party Plan is starting soon.\nHas your partner reached the venue?',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[700],
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Partner Profile & Venue Summary Card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFFE2E8F0),
                            backgroundImage: partnerPhotoUrl != null ? NetworkImage(partnerPhotoUrl) : null,
                            child: partnerPhotoUrl == null
                                ? const Icon(Icons.person, color: Color(0xFF94A3B8), size: 24)
                                : null,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  partnerName,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF0F172A),
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Row(
                                  children: [
                                    const Icon(Icons.location_on_rounded, size: 13, color: LunaraTheme.electricViolet),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        venueName,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFF475569),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Icon(Icons.schedule_rounded, size: 13, color: Color(0xFF64748B)),
                                    const SizedBox(width: 4),
                                    Text(
                                      scheduledTimeStr,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF64748B),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Refund Helper Note
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.info_outline_rounded, size: 16, color: LunaraTheme.electricViolet),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'When both participants confirm arrival, your ₹99 Commitment Deposit is immediately refunded to your wallet.',
                              style: TextStyle(fontSize: 11.5, color: Colors.grey[700], height: 1.3),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),

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
                                      backgroundColor: Color(0xFF10B981),
                                    ),
                                  );
                                }
                                onUpdate?.call();
                              },
                              icon: const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                              label: const Text(
                                "YES, REACHED",
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
                          const SizedBox(height: 10),

                          // Secondary NO Button
                          SizedBox(
                            width: double.infinity,
                            height: 48,
                            child: OutlinedButton.icon(
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
                                      content: Text('Recorded: NOT REACHED. You can update your response before the window closes.'),
                                      backgroundColor: Colors.orange,
                                    ),
                                  );
                                }
                                onUpdate?.call();
                              },
                              icon: const Icon(Icons.cancel_outlined, size: 18, color: Color(0xFF64748B)),
                              label: const Text(
                                'NO, NOT REACHED',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF475569),
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: Color(0xFFCBD5E1), width: 1.2),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'You can update your response until the confirmation window closes.',
                            style: TextStyle(fontSize: 11, color: Colors.grey[500]),
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
