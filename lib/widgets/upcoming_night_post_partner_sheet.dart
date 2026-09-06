// ignore_for_file: use_build_context_synchronously
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../widgets/top_notification_banner.dart';
import '../widgets/dialogs/time_lock_blocked_dialog.dart';
import '../utils/lunara_date_formatter.dart';

class UpcomingNightPostPartnerSheet extends StatefulWidget {
  final Map<String, dynamic> party;
  final String venueId;
  final String venueName;
  final String date;
  final String time;
  final String? bannerImage;
  final String? eventTitle;

  const UpcomingNightPostPartnerSheet({
    super.key,
    required this.party,
    required this.venueId,
    required this.venueName,
    required this.date,
    required this.time,
    this.bannerImage,
    this.eventTitle,
  });

  static Future<void> show(
    BuildContext context, {
    required Map<String, dynamic> party,
    required String venueId,
    required String venueName,
    required String date,
    required String time,
    String? bannerImage,
    String? eventTitle,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: UpcomingNightPostPartnerSheet(
          party: party,
          venueId: venueId,
          venueName: venueName,
          date: date,
          time: time,
          bannerImage: bannerImage,
          eventTitle: eventTitle,
        ),
      ),
    );
  }

  @override
  State<UpcomingNightPostPartnerSheet> createState() => _UpcomingNightPostPartnerSheetState();
}

class _UpcomingNightPostPartnerSheetState extends State<UpcomingNightPostPartnerSheet> {
  late TextEditingController _messageController;
  bool _isPosting = false;
  String _selectedPrivacy = 'PUBLIC'; // 'PUBLIC' or 'PRIVATE'
  String _selectedFoodPref = 'ANY'; // 'ANY', 'VEG', 'NON_VEG'
  String _selectedDrinkPref = 'COCKTAILS'; // 'COCKTAILS', 'BEER', 'NON_ALCOHOLIC', 'ANY'

  @override
  void initState() {
    super.initState();
    final title = widget.eventTitle ?? widget.party['title'] ?? widget.party['name'] ?? widget.venueName;
    _messageController = TextEditingController(
      text: "Looking for a fun party partner for $title at ${widget.venueName}! ✨ Let's vibe!",
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  String _formatDisplayDate(String rawDate) {
    try {
      final parsed = DateTime.parse(rawDate);
      return DateFormat('EEEE, dd MMM yyyy').format(parsed);
    } catch (_) {
      return rawDate;
    }
  }

  String _formatToIsoDateTime(String dateStr, String timeStr) {
    try {
      DateTime parsedDate;
      if (dateStr.contains('T')) {
        parsedDate = DateTime.parse(dateStr);
      } else {
        final parts = dateStr.split('-');
        parsedDate = DateTime(
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
        );
      }

      int hour = 20;
      int minute = 0;

      final cleanTime = timeStr.trim().toUpperCase();
      if (cleanTime.contains('PM') || cleanTime.contains('AM')) {
        final isPm = cleanTime.contains('PM');
        final digits = cleanTime.replaceAll(RegExp(r'[^0-9:]'), '');
        final timeParts = digits.split(':');
        hour = int.tryParse(timeParts[0]) ?? (isPm ? 8 : 20);
        if (isPm && hour < 12) hour += 12;
        if (!isPm && hour == 12) hour = 0;
        if (timeParts.length > 1) {
          minute = int.tryParse(timeParts[1]) ?? 0;
        }
      } else if (cleanTime.contains(':')) {
        final timeParts = cleanTime.split(':');
        hour = int.tryParse(timeParts[0]) ?? 20;
        minute = int.tryParse(timeParts[1]) ?? 0;
      }

      final combined = DateTime(
        parsedDate.year,
        parsedDate.month,
        parsedDate.day,
        hour,
        minute,
      );
      return combined.toUtc().toIso8601String();
    } catch (_) {
      return DateTime.now().add(const Duration(hours: 3)).toUtc().toIso8601String();
    }
  }

  Future<void> _submitPost() async {
    final userId = ApiService.currentUserId;
    if (userId == null || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please log in to post to Live Feed')),
      );
      return;
    }

    if (_messageController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a message for your partner search')),
      );
      return;
    }

    setState(() => _isPosting = true);

    try {
      final isoPlanDateTime = _formatToIsoDateTime(widget.date, widget.time);
      final adId = widget.party['adId'] ?? widget.party['upcomingNightId'] ?? widget.party['id'];

      final response = await ApiService.post(
        '/api/mobile/party-plans',
        body: {
          'userId': userId,
          'venueId': widget.venueId,
          'message': _messageController.text.trim(),
          'planDateTime': isoPlanDateTime,
          'privacyType': _selectedPrivacy.toLowerCase(),
          'paymentStatus': 'pending',
          'paymentType': 'self_pay',
          'selectedUserIds': [],
          'mobileNumber': '',
          'optionalMobileNumber': '',
          'foodPreference': _selectedFoodPref,
          'drinkPreference': _selectedDrinkPref,
          'showVenueDetails': true,
          'showDateDetails': true,
          'showHostName': true,
          'showProfilePhoto': true,
          'isUpcomingNight': true,
          'upcomingNightId': adId?.toString(),
          'adId': adId?.toString(),
          'bannerToDate': widget.party['bannerToDate'] ?? widget.party['toDate'],
        },
        timeout: const Duration(seconds: 25),
      );

      setState(() => _isPosting = false);

      if (response.statusCode == 200 || response.statusCode == 201) {
        ApiService.planPostedNotifier.value++;
        ApiService.notifyFeedNeedsRefresh();

        Navigator.pop(context);

        TopNotificationBanner.show(
          title: 'Partner Search Posted! 🚀',
          body: 'Your Upcoming Night post is now live on the Live Feed! Anyone interested can request to join you.',
        );

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Posted to Live Feed! ✨'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final body = jsonDecode(response.body);
        final msg = body['message'] ?? 'Failed to create partner search post.';
        final isTimeLock = TimeLockBlockedDialog.isConflictError(msg) ||
            body['code'] == 'FOUR_HOUR_TIME_LOCK' ||
            body['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
            body['code'] == 'PLAN_TIME_LOCKED' ||
            body['reason'] == 'PLAN_TIME_LOCKED' ||
            body['code'] == 'USER_ALREADY_HAS_PLAN';

        if (isTimeLock) {
          TimeLockBlockedDialog.show(
            context,
            errorData: body is Map<String, dynamic> ? Map<String, dynamic>.from(body) : {'message': msg},
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.redAccent,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _isPosting = false);
      if (TimeLockBlockedDialog.isConflictError(e)) {
        TimeLockBlockedDialog.showWithMessage(context, e.toString());
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Network error: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = widget.eventTitle ?? widget.party['title'] ?? widget.party['name'] ?? widget.venueName;
    final flyer = widget.bannerImage ?? widget.party['image'] ?? widget.party['coverImageUrl'] ?? widget.party['imagePath'];

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF14141E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'POST TO FIND PARTNER',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.0,
                        ),
                      ),
                      Text(
                        'Post this upcoming night to Live Feed to find a partner',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close_rounded, color: isDark ? Colors.white54 : Colors.black54),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const Divider(height: 20),

          // Scrollable Form
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Event Card Preview
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E2C) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        if (flyer != null && flyer.toString().isNotEmpty)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.network(
                              flyer.toString().startsWith('http')
                                  ? flyer.toString()
                                  : '${ApiService.baseUrl}${flyer.toString().startsWith('/') ? '' : '/'}${flyer.toString()}',
                              width: 64,
                              height: 64,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => Container(
                                width: 64,
                                height: 64,
                                color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
                                child: const Icon(Icons.nightlife_rounded, color: LunaraTheme.electricViolet),
                              ),
                            ),
                          )
                        else
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: LunaraTheme.electricViolet.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.nightlife_rounded, color: LunaraTheme.electricViolet),
                          ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14.5,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.venueName,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  const Icon(Icons.calendar_today_rounded, size: 12, color: LunaraTheme.electricViolet),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDisplayDate(widget.date),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: LunaraTheme.electricViolet,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.access_time_rounded, size: 12, color: LunaraTheme.hotPink),
                                  const SizedBox(width: 4),
                                  Text(
                                    LunaraDateFormatter.normalizeTimeTo12Hour(widget.time),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: LunaraTheme.hotPink,
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
                  const SizedBox(height: 18),

                  // Message / Note
                  const Text(
                    'CUSTOMIZE YOUR INVITATION MESSAGE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _messageController,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 13.5),
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100],
                      hintText: 'Add details about your vibe or what you are looking for...',
                      hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.grey[400], fontSize: 13),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey[300]!),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: isDark ? Colors.white12 : Colors.grey[300]!),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: const BorderSide(color: LunaraTheme.electricViolet, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Food Preference
                  const Text(
                    'FOOD PREFERENCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildPillOption('ANY', 'Any Food', _selectedFoodPref == 'ANY', () {
                        setState(() => _selectedFoodPref = 'ANY');
                      }, isDark),
                      const SizedBox(width: 8),
                      _buildPillOption('VEG', 'Veg Only 🥦', _selectedFoodPref == 'VEG', () {
                        setState(() => _selectedFoodPref = 'VEG');
                      }, isDark),
                      const SizedBox(width: 8),
                      _buildPillOption('NON_VEG', 'Non-Veg 🍗', _selectedFoodPref == 'NON_VEG', () {
                        setState(() => _selectedFoodPref = 'NON_VEG');
                      }, isDark),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Drink Preference
                  const Text(
                    'DRINK PREFERENCE',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildPillOption('COCKTAILS', 'Cocktails 🍸', _selectedDrinkPref == 'COCKTAILS', () {
                        setState(() => _selectedDrinkPref = 'COCKTAILS');
                      }, isDark),
                      _buildPillOption('BEER', 'Beer 🍺', _selectedDrinkPref == 'BEER', () {
                        setState(() => _selectedDrinkPref = 'BEER');
                      }, isDark),
                      _buildPillOption('NON_ALCOHOLIC', 'Non-Alcoholic 🧃', _selectedDrinkPref == 'NON_ALCOHOLIC', () {
                        setState(() => _selectedDrinkPref = 'NON_ALCOHOLIC');
                      }, isDark),
                      _buildPillOption('ANY', 'Any', _selectedDrinkPref == 'ANY', () {
                        setState(() => _selectedDrinkPref = 'ANY');
                      }, isDark),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // Privacy Option
                  const Text(
                    'VISIBILITY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.0,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPrivacyCard(
                          title: 'Public Feed (Recommended)',
                          subtitle: 'Visible to everyone in Live Feed',
                          isSelected: _selectedPrivacy == 'PUBLIC',
                          onTap: () => setState(() => _selectedPrivacy = 'PUBLIC'),
                          isDark: isDark,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildPrivacyCard(
                          title: 'Direct Invite Only',
                          subtitle: 'Only visible to users you invite',
                          isSelected: _selectedPrivacy == 'PRIVATE',
                          onTap: () => setState(() => _selectedPrivacy = 'PRIVATE'),
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Post Button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: _isPosting ? null : _submitPost,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Ink(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                          ),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Container(
                          alignment: Alignment.center,
                          child: _isPosting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.campaign_rounded, color: Colors.white, size: 20),
                                    SizedBox(width: 8),
                                    Text(
                                      'POST TO LIVE FEED',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 13.5,
                                        letterSpacing: 1.0,
                                      ),
                                    ),
                                    SizedBox(width: 6),
                                    Text('✨', style: TextStyle(fontSize: 14)),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPillOption(String value, String label, bool isSelected, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? LunaraTheme.electricViolet
              : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey[100]),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? LunaraTheme.electricViolet : (isDark ? Colors.white12 : Colors.grey[300]!),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildPrivacyCard({
    required String title,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? LunaraTheme.electricViolet.withValues(alpha: 0.1)
              : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey[50]),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? LunaraTheme.electricViolet : (isDark ? Colors.white12 : Colors.grey[300]!),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                  size: 16,
                  color: isSelected ? LunaraTheme.electricViolet : Colors.grey,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? LunaraTheme.electricViolet : (isDark ? Colors.white : Colors.black),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: isDark ? Colors.white54 : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
