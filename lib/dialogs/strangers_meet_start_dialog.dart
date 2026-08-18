import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';

class StrangersMeetStartDialog extends StatefulWidget {
  final String meetId;
  final String subject;
  final String venueName;
  final DateTime eventDateTime;
  final VoidCallback? onStarted;

  const StrangersMeetStartDialog({
    super.key,
    required this.meetId,
    required this.subject,
    required this.venueName,
    required this.eventDateTime,
    this.onStarted,
  });

  static Future<bool?> show(
    BuildContext context, {
    required String meetId,
    required String subject,
    required String venueName,
    required DateTime eventDateTime,
    VoidCallback? onStarted,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StrangersMeetStartDialog(
        meetId: meetId,
        subject: subject,
        venueName: venueName,
        eventDateTime: eventDateTime,
        onStarted: onStarted,
      ),
    );
  }

  @override
  State<StrangersMeetStartDialog> createState() => _StrangersMeetStartDialogState();
}

class _StrangersMeetStartDialogState extends State<StrangersMeetStartDialog> {
  bool _showDurationPicker = false;
  double _selectedDuration = 2.0; // Default 2 hours
  DateTime? _customEndDateTime;
  bool _isSubmitting = false;
  String? _errorMessage;

  final List<double> _presetDurations = [1.0, 2.0, 3.0, 4.0];

  Future<void> _pickCustomEndTime() async {
    final now = DateTime.now();
    final initialDate = widget.eventDateTime.isAfter(now) ? widget.eventDateTime : now;
    final initialTime = TimeOfDay.fromDateTime(initialDate.add(const Duration(hours: 2)));

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
      final pickedDateTime = DateTime(
        initialDate.year,
        initialDate.month,
        initialDate.day,
        pickedTime.hour,
        pickedTime.minute,
      );
      if (pickedDateTime.isAfter(now)) {
        setState(() {
          _customEndDateTime = pickedDateTime;
          _selectedDuration = -1.0; // custom indicator
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Custom end time must be in the future'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleConfirmStart() async {
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      if (_selectedDuration == -1.0 && _customEndDateTime != null) {
        await ApiService.confirmStrangersMeetStarted(
          widget.meetId,
          customEndDateTime: _customEndDateTime!.toIso8601String(),
        );
      } else {
        await ApiService.confirmStrangersMeetStarted(
          widget.meetId,
          durationHours: _selectedDuration,
        );
      }

      if (mounted) {
        Navigator.pop(context, true);
        widget.onStarted?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.greenAccent),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Strangers Meet has started! Countdown is live.',
                    style: GoogleFonts.poppins(color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: const Color(0xFF1E1E2E),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  Future<void> _handleNotStarted() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1B2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Mark as Not Started?',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 16),
        ),
        content: Text(
          'Are you sure this Strangers Meet did not take place? This will close the meetup.',
          style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Yes, Not Started', style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      await ApiService.reportStrangersMeetNotStarted(widget.meetId);
      if (mounted) {
        Navigator.pop(context, true);
        widget.onStarted?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Meetup marked as not started.', style: GoogleFonts.poppins(color: Colors.white)),
            backgroundColor: const Color(0xFF1E1E2E),
            behavior: SnackBarBehavior.floating,
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
    final dateFormat = DateFormat('EEE, dd MMM • hh:mm a');
    final formattedDate = dateFormat.format(widget.eventDateTime);

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
        border: Border(
          top: BorderSide(color: Color(0xFF2A283E), width: 1.5),
        ),
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
                  color: const Color(0xFF8B5CF6).withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.play_circle_filled_rounded,
                  color: Color(0xFF8B5CF6),
                  size: 28,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Has your Strangers Meet started?',
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
                        color: const Color(0xFF8B5CF6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Meetup Meta Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1B2E),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF2E2A44)),
            ),
            child: Row(
              children: [
                const Icon(Icons.location_on_outlined, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.venueName,
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.access_time_rounded, color: Colors.white70, size: 16),
                const SizedBox(width: 6),
                Text(
                  formattedDate,
                  style: GoogleFonts.poppins(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_errorMessage != null) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.redAccent.withOpacity(0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withOpacity(0.3)),
              ),
              child: Text(
                _errorMessage!,
                style: GoogleFonts.poppins(color: Colors.redAccent, fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
          ],

          if (!_showDurationPicker) ...[
            // Initial Prompt Buttons
            Text(
              'Please confirm if participants have gathered and the meetup has officially begun.',
              style: GoogleFonts.poppins(color: Colors.white60, fontSize: 13),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _isSubmitting
                  ? null
                  : () {
                      setState(() {
                        _showDurationPicker = true;
                      });
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: Text(
                'YES, STRANGERS MEET STARTED',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _isSubmitting ? null : _handleNotStarted,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.redAccent,
                side: BorderSide(color: Colors.redAccent.withOpacity(0.5)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: Text(
                'NOT STARTED',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Dismiss / Decide Later',
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
              ),
            ),
          ] else ...[
            // Duration Selection Step
            Text(
              'Select expected meeting duration:',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),

            // Preset Pills
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ..._presetDurations.map((hrs) {
                  final isSelected = _selectedDuration == hrs;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedDuration = hrs;
                        _customEndDateTime = null;
                      });
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF1E1B2E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF2E2A44),
                        ),
                      ),
                      child: Text(
                        '${hrs.toInt()} ${hrs == 1 ? 'HOUR' : 'HOURS'}',
                        style: GoogleFonts.poppins(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                }),
                // Custom Button
                InkWell(
                  onTap: _pickCustomEndTime,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: _selectedDuration == -1.0 ? const Color(0xFF8B5CF6) : const Color(0xFF1E1B2E),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedDuration == -1.0 ? const Color(0xFF8B5CF6) : const Color(0xFF2E2A44),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.edit_calendar_rounded, size: 14, color: Colors.white70),
                        const SizedBox(width: 6),
                        Text(
                          _customEndDateTime != null
                              ? 'CUSTOM (${DateFormat('hh:mm a').format(_customEndDateTime!)})'
                              : 'CUSTOM TIME',
                          style: GoogleFonts.poppins(
                            color: _selectedDuration == -1.0 ? Colors.white : Colors.white70,
                            fontWeight: _selectedDuration == -1.0 ? FontWeight.w700 : FontWeight.w500,
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

            // Confirm Button
            ElevatedButton(
              onPressed: _isSubmitting ? null : _handleConfirmStart,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'CONFIRM & START COUNTDOWN',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _showDurationPicker = false;
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
