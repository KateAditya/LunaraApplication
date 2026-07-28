import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import 'top_error_banner.dart';

class PartySafetyCheckDialog extends StatefulWidget {
  final Map<String, dynamic> checkData;

  const PartySafetyCheckDialog({super.key, required this.checkData});

  static Future<void> showIfNeeded(BuildContext context) async {
    final pending = await ApiService.fetchPendingSafetyCheck();
    if (pending != null && context.mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PartySafetyCheckDialog(checkData: pending),
      );
    }
  }

  @override
  State<PartySafetyCheckDialog> createState() => _PartySafetyCheckDialogState();
}

class _PartySafetyCheckDialogState extends State<PartySafetyCheckDialog> {
  String _selectedStatus = 'SAFE';
  final TextEditingController _notesController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final checkId = widget.checkData['id']?.toString() ?? '';
    if (checkId.isEmpty) return;

    setState(() => _isSubmitting = true);

    final res = await ApiService.submitSafetyCheckStatus(
      checkId: checkId,
      safetyStatus: _selectedStatus,
      notes: _notesController.text.trim(),
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_selectedStatus == 'NEED_HELP'
              ? '🔴 Emergency alert sent to Lunara Admin Safety Team!'
              : '🟢 Safety check status updated successfully! Stay safe!'),
          backgroundColor: _selectedStatus == 'NEED_HELP' ? Colors.red.shade900 : Colors.green.shade800,
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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: LunaraTheme.primaryRich.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 40,
                  color: LunaraTheme.primaryRich,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'POST-PARTY SAFETY CHECK',
                style: LunaraTheme.headingStyle.copyWith(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your party at $venueName started 3 hours ago.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              if (partner != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundImage: partnerAvatar != null
                            ? NetworkImage(partnerAvatar)
                            : null,
                        child: partnerAvatar == null
                            ? const Icon(Icons.person, size: 20)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Planned with $partnerName',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              partner['phone'] ?? '',
                              style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Select your current status:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              _buildOptionTile(
                status: 'SAFE',
                label: '🟢 I\'m Safe & Reached Home',
                sublabel: 'Party is complete, I am back safe.',
                color: Colors.green,
              ),
              const SizedBox(height: 8),
              _buildOptionTile(
                status: 'EXTENDED',
                label: '🟡 Still Partying / Extended',
                sublabel: 'We are enjoying and extending the night.',
                color: Colors.orange,
              ),
              const SizedBox(height: 8),
              _buildOptionTile(
                status: 'NEED_HELP',
                label: '🔴 Need Help / Emergency',
                sublabel: 'Alert Lunara safety team & admins immediately.',
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _notesController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: 'Optional note or location update...',
                  hintStyle: const TextStyle(fontSize: 12),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.04),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _selectedStatus == 'NEED_HELP' ? Colors.red.shade700 : LunaraTheme.primaryRich,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : Text(
                          _selectedStatus == 'NEED_HELP' ? 'SEND EMERGENCY ALERT' : 'SUBMIT SAFETY CHECK',
                          style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Colors.white),
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
      onTap: () => setState(() => _selectedStatus = status),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.12) : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? color : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4),
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
                      color: isSelected ? color : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
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
