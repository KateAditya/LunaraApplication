import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../screens/profile/profile_screen.dart';
import '../widgets/lunara_profile_image.dart';
import 'upcoming_night_post_partner_sheet.dart';
import 'upcoming_night_payment_mode_dialog.dart';
import 'dialogs/time_lock_blocked_dialog.dart';
import '../utils/lunara_date_formatter.dart';

class NightPartnerSelectorSheet extends StatefulWidget {
  final String venueId;
  final String venueName;
  final String date;
  final String? time;
  final String? bannerImage;
  final String? eventTitle;
  final Map<String, dynamic>? party;

  const NightPartnerSelectorSheet({
    super.key,
    required this.venueId,
    required this.venueName,
    required this.date,
    this.time,
    this.bannerImage,
    this.eventTitle,
    this.party,
  });

  static Future<void> show(
    BuildContext context, {
    required String venueId,
    required String venueName,
    required String date,
    String? time,
    String? bannerImage,
    String? eventTitle,
    Map<String, dynamic>? party,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => NightPartnerSelectorSheet(
        venueId: venueId,
        venueName: venueName,
        date: date,
        time: time,
        bannerImage: bannerImage,
        eventTitle: eventTitle,
        party: party,
      ),
    );
  }

  @override
  State<NightPartnerSelectorSheet> createState() => _NightPartnerSelectorSheetState();
}

class _NightPartnerSelectorSheetState extends State<NightPartnerSelectorSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Map<String, dynamic>> _invitees = [];
  bool _isLoading = true;
  final bool _showPostPartnerBanner = false;
  final Set<String> _sentInviteUserIds = {};
  final Set<String> _loadingUserIds = {};

  @override
  void initState() {
    super.initState();
    _loadInvitees();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInvitees([String? query]) async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> results = await ApiService.fetchAvailableInvitees(
      venueId: widget.venueId,
      date: widget.date,
      search: query,
    );

    // If results are empty (e.g. initial seed or no venue-matched records yet),
    // gracefully fall back to active profiles so user never sees an empty screen
    if (results.isEmpty) {
      try {
        final customers = await ApiService.fetchCustomers();
        final currentUserId = ApiService.currentUserId;
        if (customers.isNotEmpty) {
          results = customers
              .where((u) => u['id']?.toString() != currentUserId)
              .where((u) {
                if (query == null || query.trim().isEmpty) return true;
                final q = query.trim().toLowerCase();
                final name = '${u['firstName'] ?? ''} ${u['lastName'] ?? ''}'.toLowerCase();
                return name.contains(q);
              })
              .map((u) => {
                    'userId': u['id']?.toString(),
                    'firstName': u['firstName'] ?? 'User',
                    'age': u['age'],
                    'city': u['city'] ?? 'Pune',
                    'gender': u['gender'],
                    'bio': u['bio'] ?? '',
                    'primaryPhoto': u['profilePhotoUrl'] ?? u['profilePhoto'] ?? u['photoUrl'],
                    'isVerified': u['isVerified'] == true,
                    'compatibilityScore': 90,
                    'isInterested': false,
                  })
              .toList();
        }
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() {
      _invitees = results;
      _isLoading = false;
      for (final item in _invitees) {
        if (item['hasPendingInvite'] == true) {
          _sentInviteUserIds.add(item['userId']?.toString() ?? '');
        }
      }
    });
  }

  double _resolveTicketPrice() {
    final party = widget.party;
    if (party != null) {
      final rawPrice = party['ticketPrice'] ?? party['price'] ?? party['coupleEntryFee'] ?? party['coverCharges'] ?? party['entryFee'];
      if (rawPrice != null) {
        final parsed = double.tryParse(rawPrice.toString().replaceAll(RegExp(r'[^0-9.]'), ''));
        if (parsed != null && parsed > 0) return parsed;
      }
    }
    return 1000.0;
  }

  Future<void> _promptAndSendInvite(Map<String, dynamic> partner) async {
    final selectedMode = await UpcomingNightPaymentModeDialog.show(
      context,
      partner: partner,
      venueName: widget.venueName,
      date: widget.date,
      time: widget.time,
      eventTitle: widget.eventTitle,
      ticketPrice: _resolveTicketPrice(),
    );

    if (selectedMode != null) {
      _sendInvite(partner, selectedMode);
    }
  }

  Future<void> _sendInvite(Map<String, dynamic> partner, [String paymentMode = 'SELF_PAY']) async {
    final partnerId = partner['userId']?.toString();
    if (partnerId == null || partnerId.isEmpty) return;

    if (_sentInviteUserIds.contains(partnerId)) return;

    setState(() {
      _loadingUserIds.add(partnerId);
    });

    final res = await ApiService.sendNightPartnerRequest(
      partnerId: partnerId,
      venueId: widget.venueId,
      date: widget.date,
      time: LunaraDateFormatter.normalizeTimeTo12Hour(widget.time),
      paymentMode: paymentMode,
    );

    if (!mounted) return;

    setState(() {
      _loadingUserIds.remove(partnerId);
      if (res != null && res['success'] == true) {
        _sentInviteUserIds.add(partnerId);
      }
    });

    if (res != null && res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Invite sent to ${partner['firstName'] ?? 'partner'}! 🎉',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      final msg = res?['message']?.toString() ?? 'Could not send invite. Please try again.';
      final isTimeLock = TimeLockBlockedDialog.isConflictError(msg) ||
          res?['code'] == 'FOUR_HOUR_TIME_LOCK' ||
          res?['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
          res?['code'] == 'USER_ALREADY_HAS_PLAN' ||
          res?['code'] == 'PLAN_TIME_LOCKED';

      if (isTimeLock) {
        TimeLockBlockedDialog.show(
          context,
          errorData: res is Map<String, dynamic> ? res : {'message': msg},
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _openUserProfile(Map<String, dynamic> partner) {
    final uid = partner['userId']?.toString() ?? '';
    if (uid.isEmpty) return;

    final userObj = User.fromJson({
      'id': uid,
      'firstName': partner['firstName'] ?? 'User',
      'photos': partner['primaryPhoto'] != null
          ? [{'url': partner['primaryPhoto']}]
          : [],
      'profile': {
        'city': partner['city'],
        'gender': partner['gender'],
        'bio': partner['bio'],
        'occupation': partner['occupation'],
        'interests': partner['interests'] ?? [],
      },
      'bio': partner['bio'] ?? '',
    });

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProfileScreen(user: userObj)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final interestedList = _invitees.where((i) => i['isInterested'] == true).toList();
    final otherList = _invitees.where((i) => i['isInterested'] != true).toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.88,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161622) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        children: [
          // Drag Handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'INVITE A PARTNER',
                        style: TextStyle(
                          fontFamily: 'AllroundGothic',
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.venueName} • ${widget.date}',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Post to Find Partner Banner (Disabled for now as requested; logic preserved)
          if (_showPostPartnerBanner) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: InkWell(
                onTap: () {
                  Navigator.pop(context);
                  UpcomingNightPostPartnerSheet.show(
                    context,
                    party: widget.party ?? {
                      'venueId': widget.venueId,
                      'venue': widget.venueName,
                      'venueName': widget.venueName,
                      'date': widget.date,
                      'rawDate': widget.date,
                      'time': LunaraDateFormatter.normalizeTimeTo12Hour(widget.time),
                      'title': widget.eventTitle ?? widget.venueName,
                      'image': widget.bannerImage,
                    },
                    venueId: widget.venueId,
                    venueName: widget.venueName,
                    date: widget.date,
                    time: LunaraDateFormatter.normalizeTimeTo12Hour(widget.time),
                    bannerImage: widget.bannerImage,
                    eventTitle: widget.eventTitle ?? widget.venueName,
                  );
                },
                borderRadius: BorderRadius.circular(18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        LunaraTheme.electricViolet.withValues(alpha: 0.12),
                        LunaraTheme.hotPink.withValues(alpha: 0.08),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF7C3AED), Color(0xFFEC4899)],
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.campaign_rounded,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Text(
                                  'Share as Post to Find Partner',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13,
                                    color: LunaraTheme.electricViolet,
                                  ),
                                ),
                                SizedBox(width: 4),
                                Text('✨', style: TextStyle(fontSize: 11)),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Post to Live Feed so anyone interested can request to join you!',
                              style: TextStyle(
                                fontSize: 11,
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 13,
                        color: LunaraTheme.electricViolet,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.grey[100],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.grey[300]!,
                ),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: (val) => _loadInvitees(val),
                decoration: InputDecoration(
                  hintText: 'Search people to invite...',
                  hintStyle: TextStyle(
                    fontSize: 13.5,
                    color: isDark ? Colors.white38 : Colors.grey[500],
                  ),
                  icon: const Icon(Icons.search, color: LunaraTheme.electricViolet, size: 20),
                  border: InputBorder.none,
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchController.clear();
                            _loadInvitees();
                          },
                        )
                      : null,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // List of available partners
          Expanded(
            child: _isLoading
                ? _buildInviteesSkeleton(isDark)
                : _invitees.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline_rounded, size: 48, color: Colors.grey[400]),
                            const SizedBox(height: 12),
                            Text(
                              'No available users found',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Try searching for another name or check back soon.',
                              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                        children: [
                          if (interestedList.isNotEmpty) ...[
                            _buildSectionHeader(
                              'INTERESTED IN THIS NIGHT (${interestedList.length})',
                              isHighlight: true,
                            ),
                            const SizedBox(height: 6),
                            ...interestedList.map((partner) => _buildPartnerRow(partner, isDark)),
                            const SizedBox(height: 16),
                          ],
                          if (otherList.isNotEmpty) ...[
                            _buildSectionHeader(
                              interestedList.isNotEmpty
                                  ? 'OTHER AVAILABLE PEOPLE (${otherList.length})'
                                  : 'AVAILABLE TO INVITE (${otherList.length})',
                              isHighlight: false,
                            ),
                            const SizedBox(height: 6),
                            ...otherList.map((partner) => _buildPartnerRow(partner, isDark)),
                            const SizedBox(height: 16),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, {required bool isHighlight}) {
    return Row(
      children: [
        if (isHighlight) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5722), Color(0xFFFF9800)],
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text(
              'HOT',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Text(
          title,
          style: TextStyle(
            color: isHighlight ? const Color(0xFFFF5722) : const Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  Widget _buildPartnerRow(Map<String, dynamic> partner, bool isDark) {
    final partnerId = partner['userId']?.toString() ?? '';
    final isSent = _sentInviteUserIds.contains(partnerId);
    final isInviting = _loadingUserIds.contains(partnerId);
    final name = partner['firstName'] ?? 'User';
    final age = partner['age'];
    final city = partner['city'] ?? '';
    final photo = partner['primaryPhoto'];
    final score = partner['compatibilityScore'] ?? 88;
    final isVerified = partner['isVerified'] == true;
    final isInterested = partner['isInterested'] == true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isInterested
              ? (isDark ? const Color(0xFF1E1E30) : const Color(0xFFFFF7ED))
              : (isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFFAFAFC)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isInterested
                ? const Color(0xFFFFB74D).withValues(alpha: 0.4)
                : (isDark ? Colors.white10 : const Color(0xFFF1F5F9)),
            width: isInterested ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _openUserProfile(partner),
              child: Stack(
                children: [
                  LunaraProfileImage(
                    userData: {'profilePhotoUrl': photo},
                    radius: 24,
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
                          size: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: GestureDetector(
                onTap: () => _openUserProfile(partner),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            age != null ? '$name, $age' : name,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isInterested) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFFFF5722), Color(0xFFFF9800)],
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'INTERESTED 🔥',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.4,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (city.isNotEmpty) ...[
                          Text(
                            city,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: isDark ? Colors.white54 : Colors.grey[600],
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text('•', style: TextStyle(color: Colors.grey, fontSize: 10)),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          '$score% Vibe',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF15803D),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              height: 36,
              child: ElevatedButton(
                onPressed: (isSent || isInviting)
                    ? null
                    : () => _promptAndSendInvite(partner),
                style: ElevatedButton.styleFrom(
                  backgroundColor: isSent
                      ? Colors.green.withValues(alpha: 0.15)
                      : LunaraTheme.electricViolet,
                  foregroundColor: isSent ? Colors.green : Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: isSent
                        ? const BorderSide(color: Colors.green, width: 1.2)
                        : BorderSide.none,
                  ),
                ),
                child: isInviting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        isSent ? 'INVITED ✓' : 'INVITE',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 11.5,
                          letterSpacing: 0.8,
                          color: isSent ? Colors.green : Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInviteesSkeleton(bool isDark) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.03) : const Color(0xFFFAFAFC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : const Color(0xFFF1F5F9),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey[300],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 120,
                        height: 14,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey[300],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 80,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 70,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white10 : Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
