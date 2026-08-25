import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_service.dart';
import '../utils/lunara_date_formatter.dart';

class StrangersMeetEndDialog extends StatefulWidget {
  final String meetId;
  final String subject;
  final String venueName;
  final DateTime? expectedEndAt;
  final VoidCallback? onEnded;
  final VoidCallback? onExtended;

  const StrangersMeetEndDialog({
    super.key,
    required this.meetId,
    required this.subject,
    required this.venueName,
    this.expectedEndAt,
    this.onEnded,
    this.onExtended,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String meetId,
    required String subject,
    required String venueName,
    DateTime? expectedEndAt,
    VoidCallback? onEnded,
    VoidCallback? onExtended,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StrangersMeetEndDialog(
        meetId: meetId,
        subject: subject,
        venueName: venueName,
        expectedEndAt: expectedEndAt,
        onEnded: onEnded,
        onExtended: onExtended,
      ),
    );
  }

  @override
  State<StrangersMeetEndDialog> createState() => _StrangersMeetEndDialogState();
}

class _StrangersMeetEndDialogState extends State<StrangersMeetEndDialog> {
  bool _showExtensionPicker = false;
  double _selectedExtensionHours = 1.0; // Default +1 hour
  DateTime? _customEndDateTime;
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<double> _extensionOptions = [0.5, 1.0, 2.0];

  Future<void> _pickCustomExtensionTime() async {
    final now = DateTime.now();
    final baseTime =
        (widget.expectedEndAt != null && widget.expectedEndAt!.isAfter(now))
        ? widget.expectedEndAt!
        : now;
    final initialTime = TimeOfDay.fromDateTime(
      baseTime.add(const Duration(hours: 1)),
    );

    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Color(0xFF8B5CF6),
              surface: Color(0xFF1E1E2E),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedTime != null) {
      DateTime pickedDateTime = DateTime(
        baseTime.year,
        baseTime.month,
        baseTime.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      if (pickedDateTime.isBefore(baseTime)) {
        pickedDateTime = pickedDateTime.add(const Duration(days: 1));
      }
      if (pickedDateTime.isAfter(now)) {
        setState(() {
          _customEndDateTime = pickedDateTime;
          _selectedExtensionHours = -1.0;
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Extension time must be in the future'),
              backgroundColor: Colors.redAccent,
            ),
          );
        }
      }
    }
  }

  Future<void> _handleConfirmEnded() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ApiService.confirmStrangersMeetEnded(widget.meetId);
      if (mounted) {
        Navigator.pop(context, true);
        widget.onEnded?.call();
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1B2E),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.verified_rounded,
                  color: Color(0xFF10B981),
                  size: 28,
                ),
                const SizedBox(width: 8),
                Text(
                  'Meetup Ended!',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            content: Text(
              'Thank you for hosting! Your meetup is now marked as ended. Lunara admin will verify and initiate your settlement within 24 hours.',
              style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(
                  'OK',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF8B5CF6),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  Future<void> _handleConfirmExtension() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      if (_selectedExtensionHours == -1.0 && _customEndDateTime != null) {
        await ApiService.extendStrangersMeetDuration(
          widget.meetId,
          customEndDateTime: _customEndDateTime!.toUtc().toIso8601String(),
        );
      } else {
        await ApiService.extendStrangersMeetDuration(
          widget.meetId,
          additionalHours: _selectedExtensionHours,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        widget.onExtended?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.more_time_rounded, color: Colors.greenAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Meetup duration extended successfully!',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E1E2E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSubmitting = false;
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF13111C),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFF2A283E), width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Header Icon & Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.timer_off_outlined,
                  color: Color(0xFFF59E0B),
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Has your Strangers Meet ended?',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    Text(
                      widget.subject,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: const Color(0xFFF59E0B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Venue Meta
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1B2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E2A44)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.location_on_outlined,
                  color: Colors.white70,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.venueName,
                    style: GoogleFonts.poppins(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.redAccent.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                _errorMessage!,
                style: GoogleFonts.poppins(
                  color: Colors.redAccent,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (!_showExtensionPicker) ...[
            Text(
              'Confirming completion will submit your meetup for admin verification and 24-hour host payout settlement.',
              style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _handleConfirmEnded,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'YES, STRANGERS MEET ENDED',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                setState(() {
                  _showExtensionPicker = true;
                });
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFF8B5CF6)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'NOT YET — EXTEND TIME',
                style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: const Color(0xFF8B5CF6),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Dismiss for now',
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
              ),
            ),
          ] else ...[
            // Extension Picker
            Text(
              'Add extra time to your meetup duration:',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),

            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._extensionOptions.map((hrs) {
                  final isSelected = _selectedExtensionHours == hrs;
                  final label = hrs == 0.5
                      ? '+30 MINS'
                      : '+${hrs.toInt()} ${hrs == 1 ? 'HOUR' : 'HOURS'}';
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedExtensionHours = hrs;
                        _customEndDateTime = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF8B5CF6)
                            : const Color(0xFF1E1B2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF8B5CF6)
                              : const Color(0xFF2E2A44),
                        ),
                      ),
                      child: Text(
                        label,
                        style: GoogleFonts.poppins(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: isSelected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }),
                InkWell(
                  onTap: _pickCustomExtensionTime,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _selectedExtensionHours == -1.0
                          ? const Color(0xFF8B5CF6)
                          : const Color(0xFF1E1B2E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedExtensionHours == -1.0
                            ? const Color(0xFF8B5CF6)
                            : const Color(0xFF2E2A44),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.edit_calendar_rounded,
                          size: 14,
                          color: Colors.white70,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _customEndDateTime != null
                              ? 'CUSTOM (${LunaraDateFormatter.formatEventTime(_customEndDateTime!)})'
                              : 'CUSTOM TIME',
                          style: GoogleFonts.poppins(
                            color: _selectedExtensionHours == -1.0
                                ? Colors.white
                                : Colors.white70,
                            fontWeight: _selectedExtensionHours == -1.0
                                ? FontWeight.w700
                                : FontWeight.w500,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              onPressed: _isSubmitting ? null : _handleConfirmExtension,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'CONFIRM EXTENSION',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _showExtensionPicker = false;
                });
              },
              child: Text(
                'Back',
                style: GoogleFonts.poppins(color: Colors.white60, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
