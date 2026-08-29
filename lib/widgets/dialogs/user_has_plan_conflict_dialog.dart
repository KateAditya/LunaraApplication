import 'package:flutter/material.dart';
import '../../core/theme.dart';

class UserHasPlanConflictDialog extends StatelessWidget {
  final String message;
  final String? userName;
  final List<Map<String, dynamic>> conflictingUsers;
  final List<String> validUserIds;
  final VoidCallback? onRemoveConflictingAndProceed;
  final VoidCallback? onChangeTime;
  final VoidCallback? onSelectAnotherProfile;

  const UserHasPlanConflictDialog({
    super.key,
    required this.message,
    this.userName,
    this.conflictingUsers = const [],
    this.validUserIds = const [],
    this.onRemoveConflictingAndProceed,
    this.onChangeTime,
    this.onSelectAnotherProfile,
  });

  static Future<void> show(
    BuildContext context, {
    required String message,
    String? userName,
    List<Map<String, dynamic>> conflictingUsers = const [],
    List<String> validUserIds = const [],
    VoidCallback? onRemoveConflictingAndProceed,
    VoidCallback? onChangeTime,
    VoidCallback? onSelectAnotherProfile,
  }) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => UserHasPlanConflictDialog(
        message: message,
        userName: userName,
        conflictingUsers: conflictingUsers,
        validUserIds: validUserIds,
        onRemoveConflictingAndProceed: onRemoveConflictingAndProceed,
        onChangeTime: onChangeTime,
        onSelectAnotherProfile: onSelectAnotherProfile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMultiple = conflictingUsers.length > 1;
    final displayName = userName?.trim().isNotEmpty == true
        ? userName!.trim()
        : (isMultiple ? '${conflictingUsers.length} Guests' : 'Selected user');

    final canRemoveAndProceed = onRemoveConflictingAndProceed != null && validUserIds.isNotEmpty;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24.0)),
      elevation: 12,
      backgroundColor: const Color(0xFF1E1E2E), // Premium dark theme card
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Header Icon Badge
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.event_busy_rounded,
                color: Colors.amber,
                size: 38,
              ),
            ),
            const SizedBox(height: 14),

            // Header Title
            Text(
              isMultiple ? 'Schedule Conflicts' : 'Schedule Conflict',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                fontFamily: 'AllroundGothic',
              ),
            ),
            const SizedBox(height: 12),

            // Conflicting Users List / Badge
            if (isMultiple) ...[
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A3C),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1),
                ),
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: conflictingUsers.map((u) {
                      final name = (u['name'] ?? 'Guest').toString();
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.redAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.cancel_outlined, size: 13, color: Colors.redAccent),
                            const SizedBox(width: 5),
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A3C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.person_rounded, size: 16, color: Colors.amber),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        displayName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),

            // Message text
            Text(
              message.isNotEmpty
                  ? message
                  : (isMultiple
                      ? '${conflictingUsers.length} selected guests have another plan at this time.'
                      : '$displayName has another plan at the scheduled time. Change time or use another profile.'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFFB0B0C3),
                height: 1.45,
              ),
            ),
            const SizedBox(height: 20),

            // Primary Option: Remove conflicting & Proceed
            if (canRemoveAndProceed) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    onRemoveConflictingAndProceed!();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: LunaraTheme.electricViolet,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.check_circle_outline, size: 18, color: Colors.white),
                  label: Text(
                    'REMOVE & CONTINUE (${validUserIds.length} Guests)',
                    style: const TextStyle(
                      fontFamily: 'AllroundGothic',
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],

            // Secondary Options: Change Profiles or Change Time
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (onSelectAnotherProfile != null) {
                        onSelectAnotherProfile!();
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: const Text(
                      'CHANGE PROFILES',
                      style: TextStyle(
                        fontFamily: 'AllroundGothic',
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.white70,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      if (onChangeTime != null) {
                        onChangeTime!();
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      backgroundColor: canRemoveAndProceed ? Colors.transparent : LunaraTheme.electricViolet,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      side: canRemoveAndProceed
                          ? BorderSide(color: Colors.white.withValues(alpha: 0.2))
                          : BorderSide.none,
                    ),
                    child: Text(
                      'CHANGE TIME',
                      style: TextStyle(
                        fontFamily: 'AllroundGothic',
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: canRemoveAndProceed ? Colors.white70 : Colors.white,
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
  }
}
