import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../widgets/lunara_profile_image.dart';

class UpcomingNightInviteDialog extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic>? hostProfile;
  final String venueName;
  final String date;
  final String time;
  final VoidCallback? onAccepted;
  final VoidCallback? onDeclined;

  const UpcomingNightInviteDialog({
    super.key,
    required this.requestId,
    this.hostProfile,
    required this.venueName,
    required this.date,
    required this.time,
    this.onAccepted,
    this.onDeclined,
  });

  @override
  State<UpcomingNightInviteDialog> createState() => _UpcomingNightInviteDialogState();
}

class _UpcomingNightInviteDialogState extends State<UpcomingNightInviteDialog> {
  bool _isLoading = false;
  Map<String, dynamic>? _fullHostData;

  @override
  void initState() {
    super.initState();
    _fullHostData = widget.hostProfile;
    if (_fullHostData == null || _fullHostData!['firstName'] == null) {
      _loadHostProfile();
    }
  }

  Future<void> _loadHostProfile() async {
    final hostId = widget.hostProfile?['id'] ?? widget.hostProfile?['userId'];
    if (hostId != null) {
      final data = await ApiService.fetchPartnerProfilePreview(hostId.toString());
      if (mounted && data != null) {
        setState(() {
          _fullHostData = data;
        });
      }
    }
  }

  Future<void> _respond(String action) async {
    setState(() => _isLoading = true);
    final success = await ApiService.respondToNightPartnerRequest(
      requestId: widget.requestId,
      action: action,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    Navigator.pop(context);

    if (success) {
      if (action == 'accept') {
        if (widget.onAccepted != null) widget.onAccepted!();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.white),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '🎉 Invite Accepted! Host notified to confirm booking.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        if (widget.onDeclined != null) widget.onDeclined!();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invite declined'),
            backgroundColor: Colors.grey,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to process response. Please try again.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final hostName = _fullHostData?['firstName'] ?? 'Host';
    final age = _fullHostData?['age'];
    final photoUrl = _fullHostData?['primaryPhoto'] ?? _fullHostData?['profilePhotoUrl'];
    final bio = _fullHostData?['bio'] ?? 'Wants to go to Upcoming Night with you!';
    final matchScore = _fullHostData?['compatibilityScore'] ?? 88;
    final isVerified = _fullHostData?['isVerified'] == true;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_awesome, color: LunaraTheme.electricViolet, size: 16),
                  SizedBox(width: 6),
                  Text(
                    'UPCOMING NIGHT INVITE',
                    style: TextStyle(
                      fontFamily: 'AllroundGothic',
                      color: LunaraTheme.electricViolet,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Host Avatar with Verification Badge
            Stack(
              children: [
                LunaraProfileImage(
                  userData: {'profilePhotoUrl': photoUrl},
                  radius: 40,
                ),
                if (isVerified)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified,
                        color: LunaraTheme.cyberCyan,
                        size: 20,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // Host Name & Age
            Text(
              age != null ? '$hostName, $age' : hostName,
              style: const TextStyle(
                fontFamily: 'AllroundGothic',
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),

            // Compatibility Match Tag
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFDCFCE7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$matchScore% Match',
                style: const TextStyle(
                  color: Color(0xFF15803D),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Bio preview
            Text(
              bio,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
                height: 1.3,
              ),
            ),
            const SizedBox(height: 20),

            // Event Details Box
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey[200]!),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.nightlife_rounded, color: LunaraTheme.electricViolet, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.venueName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded, color: LunaraTheme.electricViolet, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        '${widget.date} • ${widget.time}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Action Buttons: Accept & Decline
            _isLoading
                ? const CircularProgressIndicator(color: LunaraTheme.electricViolet)
                : Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _respond('decline'),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.grey[300]!),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'DECLINE',
                            style: TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _respond('accept'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: LunaraTheme.electricViolet,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'ACCEPT INVITE',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              letterSpacing: 0.5,
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
