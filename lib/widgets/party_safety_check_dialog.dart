import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import 'top_error_banner.dart';

class PartySafetyCheckDialog extends StatefulWidget {
  final Map<String, dynamic> checkData;
  final VoidCallback? onSubmitted;

  const PartySafetyCheckDialog({
    super.key,
    required this.checkData,
    this.onSubmitted,
  });

  static Future<void> showIfNeeded(BuildContext context, {VoidCallback? onSubmitted}) async {
    final pending = await ApiService.fetchPendingSafetyCheck();
    if (pending != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PartySafetyCheckDialog(
          checkData: pending,
          onSubmitted: onSubmitted,
        ),
      );
    }
  }

  @override
  State<PartySafetyCheckDialog> createState() => _PartySafetyCheckDialogState();
}

class _PartySafetyCheckDialogState extends State<PartySafetyCheckDialog> {
  String _selectedStatus = 'SAFE'; // 'SAFE', 'NEED_HELP', 'EXTENDED'
  final Set<String> _selectedReasons = <String>{};
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;

  final List<String> _unsafeReasons = [
    'Felt uncomfortable',
    'Rude or aggressive',
    'Did not match profile',
    'Inappropriate behavior',
    'Partner did not leave',
    'Medical emergency',
    'Need immediate help',
  ];

  final List<String> _safeReasons = [
    'Polite & Friendly',
    'Respectful & Safe',
    'Great communication',
    'Arrived home safely',
    'Felt very comfortable',
  ];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final checkId = (widget.checkData['id'] ?? widget.checkData['_id'] ?? widget.checkData['checkId'] ?? '').toString();
    if (checkId.isEmpty) return;

    setState(() => _isSubmitting = true);

    final isEmergency = _selectedStatus == 'NEED_HELP';
    final reasonsText = _selectedReasons.isNotEmpty ? _selectedReasons.join(', ') : '';
    final userNote = _notesController.text.trim();
    final combinedNotes = [
      if (reasonsText.isNotEmpty) 'Reasons: $reasonsText',
      if (userNote.isNotEmpty) 'Note: $userNote',
    ].join(' | ');

    final res = await ApiService.submitSafetyCheckStatus(
      checkId: checkId,
      safetyStatus: _selectedStatus,
      notes: combinedNotes.isNotEmpty ? combinedNotes : (isEmergency ? 'Emergency alert reported by user' : 'Confirmed safe'),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      widget.onSubmitted?.call();
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isEmergency ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isEmergency
                      ? '🔴 Emergency alert sent to Lunara Admin Safety Team!'
                      : '🟢 Safety check confirmed! Stay safe!',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ),
            ],
          ),
          backgroundColor: isEmergency ? Colors.red.shade900 : const Color(0xFF10B981),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } else {
      TopErrorBanner.show(context, res['message'] ?? 'Failed to update safety check');
    }
  }

  @override
  Widget build(BuildContext context) {
    final venueName = widget.checkData['venueName'] ?? 'the venue';
    final partner = widget.checkData['partner'] as Map<String, dynamic>?;
    final partnerName = partner?['name'] ?? 'your party match';
    final partnerAvatar = partner?['avatarUrl'];

    final isEmergency = _selectedStatus == 'NEED_HELP';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(22.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Shield icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isEmergency ? Colors.red.withValues(alpha: 0.1) : const Color(0xFF10B981).withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isEmergency ? Icons.warning_rounded : Icons.shield_outlined,
                  size: 38,
                  color: isEmergency ? Colors.red.shade700 : const Color(0xFF10B981),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'POST-PARTY SAFETY CHECK',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: Colors.black,
                ),
              ),
              const SizedBox(height: 6),
              Builder(
                builder: (_) {
                  final rawDate = widget.checkData['partyDate'] ?? widget.checkData['eventDateTime'] ?? widget.checkData['createdAt'];
                  String elapsedText = (widget.checkData['hoursText'] ?? '').toString();
                  if (rawDate != null) {
                    try {
                      final dt = DateTime.parse(rawDate.toString()).toLocal();
                      final diff = DateTime.now().difference(dt);
                      if (elapsedText.isEmpty) {
                        final hours = diff.inHours;
                        if (hours >= 1) {
                          elapsedText = '$hours ${hours == 1 ? "hour" : "hours"} ago';
                        } else if (diff.inMinutes > 0) {
                          elapsedText = '${diff.inMinutes} mins ago';
                        }
                      }
                    } catch (_) {}
                  }
                  if (elapsedText.isEmpty) {
                    final pTime = widget.checkData['partyTime']?.toString();
                    elapsedText = pTime != null && pTime.isNotEmpty ? 'at $pTime' : 'recently';
                  }

                  return Text(
                    'Your party at $venueName started $elapsedText.\nPlease confirm you are safe & sound.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.grey[700],
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              if (partner != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: LunaraTheme.electricViolet.withValues(alpha: 0.15),
                        backgroundImage: partnerAvatar != null
                            ? NetworkImage(partnerAvatar)
                            : null,
                        child: partnerAvatar == null
                            ? const Icon(Icons.person, size: 20, color: LunaraTheme.electricViolet)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Planned with $partnerName',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.black87),
                            ),
                            if (partner['phone'] != null)
                              Text(
                                partner['phone'],
                                style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Are you safe and sound?',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black),
                ),
              ),
              const SizedBox(height: 10),
              _buildOptionTile(
                status: 'SAFE',
                label: '🟢 Yes, I\'m Safe & Reached Home',
                sublabel: 'Party is complete, I am back safely.',
                color: const Color(0xFF10B981),
              ),
              const SizedBox(height: 8),
              _buildOptionTile(
                status: 'NEED_HELP',
                label: '🔴 No, Need Help / Report Issue',
                sublabel: 'Alert Lunara safety team & admins immediately.',
                color: Colors.red.shade700,
              ),
              const SizedBox(height: 8),
              _buildOptionTile(
                status: 'EXTENDED',
                label: '🟡 Still Partying / Extended',
                sublabel: 'We are enjoying and extending the night.',
                color: Colors.orange.shade700,
              ),
              const SizedBox(height: 16),

              // Reason chips
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  isEmergency ? 'Select Reasons (Sent to Safety Team):' : 'Share Experience (Optional):',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Colors.grey[800]),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: (isEmergency ? _unsafeReasons : _safeReasons).map((reason) {
                  final isSelected = _selectedReasons.contains(reason);
                  return FilterChip(
                    label: Text(
                      reason,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? Colors.white : Colors.black87,
                      ),
                    ),
                    selected: isSelected,
                    selectedColor: isEmergency ? Colors.red.shade700 : const Color(0xFF10B981),
                    backgroundColor: Colors.grey[100],
                    checkmarkColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: isSelected
                            ? (isEmergency ? Colors.red.shade700 : const Color(0xFF10B981))
                            : Colors.grey[300]!,
                      ),
                    ),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedReasons.add(reason);
                        } else {
                          _selectedReasons.remove(reason);
                        }
                      });
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 12),
              TextField(
                controller: _notesController,
                maxLines: 2,
                style: const TextStyle(fontSize: 13, color: Colors.black87),
                decoration: InputDecoration(
                  hintText: isEmergency
                      ? 'Describe what happened (Confidential report to Admin)...'
                      : 'Optional feedback or notes...',
                  hintStyle: TextStyle(fontSize: 12, color: Colors.grey[400]),
                  filled: true,
                  fillColor: Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[200]!),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey[200]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isEmergency ? Colors.red.shade700 : const Color(0xFF10B981),
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isEmergency ? Colors.red.shade700 : const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          isEmergency ? 'SEND EMERGENCY ALERT' : 'CONFIRM & SUBMIT',
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                            fontSize: 13,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptionTile({
    required String status,
    required String label,
    required String sublabel,
    required Color color,
  }) {
    final isSelected = _selectedStatus == status;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedStatus = status;
          _selectedReasons.clear();
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.1) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? color : Colors.grey[400],
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isSelected ? color : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    sublabel,
                    style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
