import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../discovery/digital_ticket_screen.dart';
import '../social/large_party_ticket_screen.dart';
import '../social/party_plan_ticket_screen.dart';
import '../social/strangers_meet_ticket_screen.dart';
import '../../models/strangers_meet_request.dart';

enum TicketFilterCategory {
  all('all', 'ALL', Icons.all_inclusive_rounded),
  partyPlan('party_plan', 'PARTY PLAN', Icons.celebration_rounded),
  groupParties('group_party', 'GROUP PARTIES', Icons.groups_rounded),
  largeParty('large_party', 'LARGE PARTY', Icons.star_rounded),
  strangersMeet('strangers_meet', 'STRANGER MEET', Icons.handshake_rounded),
  soloBooking('solo', 'SOLO BOOKING', Icons.person_rounded),
  eventBooking('event_booking', 'EVENT BOOKING', Icons.nightlife_rounded),
  venueBooking('venue_booking', 'VENUE BOOKING', Icons.local_bar_rounded);

  final String key;
  final String label;
  final IconData icon;
  const TicketFilterCategory(this.key, this.label, this.icon);
}

class TicketPocketScreen extends StatefulWidget {
  const TicketPocketScreen({super.key});

  @override
  State<TicketPocketScreen> createState() => _TicketPocketScreenState();
}

class _TicketPocketScreenState extends State<TicketPocketScreen>
    with SingleTickerProviderStateMixin {
  static const LinearGradient _lunaraPurpleGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF7C3AED), // Vibrant Royal Violet
      Color(0xFF9333EA), // Rich Electric Purple
    ],
  );

  static const Color _lunaraPurple = Color(0xFF7C3AED);

  late TabController _tabController;
  List<dynamic> _allBookings = [];
  bool _isLoading = true;
  TicketFilterCategory _selectedCategory = TicketFilterCategory.all;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (mounted) setState(() {});
    });
    _loadBookings();
    _initListeners();
  }

  @override
  void dispose() {
    _disposeListeners();
    _tabController.dispose();
    super.dispose();
  }

  void _initListeners() {
    ApiService.planPostedNotifier.addListener(_onAutoRefresh);
    ApiService.addSocketListener('party_plan_match_success', _onSocketUpdate);
    ApiService.addSocketListener('group_party_payment_success', _onSocketUpdate);
    ApiService.addSocketListener('strangers_meet_settled', _onSocketUpdate);
    ApiService.addSocketListener('notification_created', _onSocketUpdate);
  }

  void _disposeListeners() {
    ApiService.planPostedNotifier.removeListener(_onAutoRefresh);
    ApiService.removeSocketListener('party_plan_match_success', _onSocketUpdate);
    ApiService.removeSocketListener('group_party_payment_success', _onSocketUpdate);
    ApiService.removeSocketListener('strangers_meet_settled', _onSocketUpdate);
    ApiService.removeSocketListener('notification_created', _onSocketUpdate);
  }

  void _onAutoRefresh() {
    if (!mounted) return;
    _loadBookings();
  }

  void _onSocketUpdate(dynamic data) {
    if (!mounted) return;
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() {
      _isLoading = true;
    });
    final tickets = await ApiService.fetchAllUserTickets();
    if (mounted) {
      setState(() {
        _allBookings = tickets;
        _isLoading = false;
      });
    }
  }

  String _getTicketCategory(Map<String, dynamic> booking) {
    if (booking['category'] != null && booking['category'].toString().isNotEmpty) {
      final cat = booking['category'].toString().toLowerCase().trim();
      if (cat == 'party_plan' ||
          cat == 'group_party' ||
          cat == 'large_party' ||
          cat == 'strangers_meet' ||
          cat == 'solo' ||
          cat == 'event_booking' ||
          cat == 'venue_booking') {
        return cat;
      }
    }

    // Comprehensive fallback classification
    final isPartyPlan = booking['isPartyPlan'] == true ||
        booking['bookingType'] == 'party_plan' ||
        booking['type'] == 'party_plan';
    if (isPartyPlan) return 'party_plan';

    final isStrangersMeet = booking['isStrangersMeet'] == true ||
        booking['bookingType'] == 'strangers_meet' ||
        booking['type'] == 'strangers_meet';
    if (isStrangersMeet) return 'strangers_meet';

    final isLargeParty = booking['isLargeParty'] == true ||
        booking['isLargePartyRequest'] == true ||
        booking['tablePackage']?.toString().toLowerCase().contains('large_party') == true ||
        ((booking['numberOfGuests'] ?? 1) is int && (booking['numberOfGuests'] as int) > 20 && booking['goingMode'] == 'party_request');
    if (isLargeParty) return 'large_party';

    final isGroupParty = booking['isGroupParty'] == true ||
        booking['isSmallGroupParty'] == true ||
        booking['bookingType'] == 'group_party' ||
        booking['type'] == 'group_party' ||
        booking['goingMode'] == 'party_request';
    if (isGroupParty) return 'group_party';

    final isUpcomingNight = booking['isUpcomingNight'] == true ||
        booking['isEventBooking'] == true ||
        booking['bookingType'] == 'upcoming_night' ||
        booking['bookingType'] == 'event_booking';
    if (isUpcomingNight) return 'event_booking';

    final isSolo = booking['isSolo'] == true ||
        booking['bookingType'] == 'solo' ||
        booking['goingMode'] == 'solo';
    if (isSolo) return 'solo';

    return 'venue_booking';
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'party_plan':
        return _lunaraPurple;
      case 'group_party':
        return const Color(0xFF06B6D4);
      case 'large_party':
        return const Color(0xFFF59E0B);
      case 'strangers_meet':
        return const Color(0xFF10B981);
      case 'solo':
        return const Color(0xFF8B5CF6);
      case 'event_booking':
        return const Color(0xFFEC4899);
      case 'venue_booking':
      default:
        return const Color(0xFF3B82F6);
    }
  }

  String _getCategoryDisplayName(String category) {
    switch (category) {
      case 'party_plan':
        return 'PARTY PLAN';
      case 'group_party':
        return 'GROUP PARTY';
      case 'large_party':
        return 'LARGE PARTY';
      case 'strangers_meet':
        return 'STRANGER MEET';
      case 'solo':
        return 'SOLO BOOKING';
      case 'event_booking':
        return 'EVENT BOOKING';
      case 'venue_booking':
      default:
        return 'VENUE BOOKING';
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'party_plan':
        return Icons.celebration_rounded;
      case 'group_party':
        return Icons.groups_rounded;
      case 'large_party':
        return Icons.star_rounded;
      case 'strangers_meet':
        return Icons.handshake_rounded;
      case 'solo':
        return Icons.person_rounded;
      case 'event_booking':
        return Icons.nightlife_rounded;
      case 'venue_booking':
      default:
        return Icons.local_bar_rounded;
    }
  }

  DateTime? _extractEventStartDateTime(Map<String, dynamic> booking) {
    if (booking['eventStartAt'] != null) {
      final dt = DateTime.tryParse(booking['eventStartAt'].toString())?.toLocal();
      if (dt != null) return dt;
    }
    if (booking['eventDateTime'] != null) {
      final dt = DateTime.tryParse(booking['eventDateTime'].toString())?.toLocal();
      if (dt != null) return dt;
    }
    if (booking['planDateTime'] != null) {
      final dt = DateTime.tryParse(booking['planDateTime'].toString())?.toLocal();
      if (dt != null) return dt;
    }
    final dateStr = booking['bookingDate']?.toString() ??
        booking['partyDate']?.toString() ??
        booking['date']?.toString();
    final startTimeStr = booking['startTime']?.toString() ??
        booking['partyTime']?.toString() ??
        '20:00';

    if (dateStr != null && dateStr.isNotEmpty) {
      try {
        final bDate = DateTime.parse(dateStr).toLocal();
        final isPm = startTimeStr.toUpperCase().contains('PM');
        final isAm = startTimeStr.toUpperCase().contains('AM');
        final cleanTime = startTimeStr.toUpperCase().replaceAll('AM', '').replaceAll('PM', '').trim();
        final parts = cleanTime.split(':');
        int h = parts.isNotEmpty ? (int.tryParse(parts[0].trim()) ?? 20) : 20;
        final m = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0;
        if (isPm && h < 12) h += 12;
        if (isAm && h == 12) h = 0;
        return DateTime(bDate.year, bDate.month, bDate.day, h, m);
      } catch (_) {}
    }
    return null;
  }

  DateTime? _extractExpirationDateTime(Map<String, dynamic> booking, DateTime? eventStart) {
    final now = DateTime.now();
    final defaultExp = eventStart?.add(const Duration(hours: 30));

    if (booking['expiresAt'] != null) {
      final dt = DateTime.tryParse(booking['expiresAt'].toString())?.toLocal();
      if (dt != null && dt.isAfter(now)) return dt;
    }
    if (booking['ticketExpiresAt'] != null) {
      final dt = DateTime.tryParse(booking['ticketExpiresAt'].toString())?.toLocal();
      if (dt != null && dt.isAfter(now)) return dt;
    }
    if (booking['eventEndAt'] != null) {
      final dt = DateTime.tryParse(booking['eventEndAt'].toString())?.toLocal();
      if (dt != null && dt.isAfter(now)) return dt;
    }

    return defaultExp;
  }

  bool _isActiveBooking(Map<String, dynamic> booking) {
    try {
      final status = booking['status']?.toString().toLowerCase() ?? '';
      if (status == 'cancelled' ||
          status == 'no_show' ||
          status == 'rejected' ||
          status == 'void') {
        return false;
      }
      if (status == 'completed' || status == 'used' || status == 'expired') {
        return false;
      }

      final eventStart = _extractEventStartDateTime(booking);
      final expirationTime = _extractExpirationDateTime(booking, eventStart);
      final now = DateTime.now();

      if (expirationTime != null) {
        return now.isBefore(expirationTime);
      }

      final dateStr = booking['bookingDate']?.toString() ??
          booking['partyDate']?.toString() ??
          booking['eventStartAt']?.toString() ??
          booking['date']?.toString();
      if (dateStr == null || dateStr.isEmpty) return true;

      final bookingDate = DateTime.parse(dateStr).toLocal();
      final todayStart = DateTime(now.year, now.month, now.day);
      final bookingDateStart = DateTime(
        bookingDate.year,
        bookingDate.month,
        bookingDate.day,
      );

      return bookingDateStart.isAtSameMomentAs(todayStart) ||
          bookingDateStart.isAfter(todayStart);
    } catch (_) {
      return true;
    }
  }

  List<Map<String, dynamic>> _getActiveBookings() {
    return _allBookings.where((b) {
      if (b is Map) {
        try {
          return _isActiveBooking(Map<String, dynamic>.from(b));
        } catch (_) {
          return false;
        }
      }
      return false;
    }).map((b) => Map<String, dynamic>.from(b as Map)).toList();
  }

  List<Map<String, dynamic>> _getPastBookings() {
    return _allBookings.where((b) {
      if (b is Map) {
        try {
          return !_isActiveBooking(Map<String, dynamic>.from(b));
        } catch (_) {
          return false;
        }
      }
      return false;
    }).map((b) => Map<String, dynamic>.from(b as Map)).toList();
  }

  List<Map<String, dynamic>> _filterListByCategory(
    List<Map<String, dynamic>> list,
    TicketFilterCategory category,
  ) {
    if (category == TicketFilterCategory.all) return list;
    return list.where((b) => _getTicketCategory(b) == category.key).toList();
  }

  int _getCategoryCount(
    List<Map<String, dynamic>> list,
    TicketFilterCategory category,
  ) {
    if (category == TicketFilterCategory.all) return list.length;
    return list.where((b) => _getTicketCategory(b) == category.key).length;
  }

  String _getVenueImageUrl(Map<String, dynamic>? venue) {
    if (venue == null) return 'https://picsum.photos/seed/venue/600/400';

    String normalize(String path) {
      final clean = path.replaceAll('\\', '/');
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return clean;
      }
      return '${ApiService.baseUrl}/${clean.startsWith('/') ? clean.substring(1) : clean}';
    }

    if (venue['coverImageUrl'] != null && venue['coverImageUrl'].toString().trim().isNotEmpty) {
      return normalize(venue['coverImageUrl'].toString());
    }

    if (venue['profilePhotoUrl'] != null && venue['profilePhotoUrl'].toString().trim().isNotEmpty) {
      return normalize(venue['profilePhotoUrl'].toString());
    }

    if (venue['coverImage'] != null && venue['coverImage'] is Map) {
      final path =
          venue['coverImage']['url'] ?? venue['coverImage']['filePath'];
      if (path != null && path.toString().isNotEmpty) {
        return normalize(path.toString());
      }
    }

    if (venue['imageUrl'] != null && venue['imageUrl'].toString().isNotEmpty) {
      return normalize(venue['imageUrl'].toString());
    }
    if (venue['image'] != null && venue['image'].toString().isNotEmpty) {
      return normalize(venue['image'].toString());
    }

    final images = venue['images'];
    if (images is List && images.isNotEmpty) {
      final nonMenuImages = images.where((img) {
        if (img is Map) {
          final type = (img['type'] ?? img['category'] ?? '').toString().toLowerCase();
          return !type.contains('menu');
        }
        return true;
      }).toList();

      final listToUse = nonMenuImages.isNotEmpty ? nonMenuImages : images;
      final img = listToUse[0];
      if (img is Map) {
        final path = img['filePath'] ?? img['url'];
        if (path != null && path.toString().isNotEmpty) {
          return normalize(path.toString());
        }
      } else if (img is String && img.isNotEmpty) {
        return normalize(img);
      }
    }

    final gallery = venue['gallery'];
    if (gallery is List && gallery.isNotEmpty) {
      final nonMenuGallery = gallery.where((img) {
        if (img is Map) {
          final type = (img['type'] ?? img['category'] ?? '').toString().toLowerCase();
          return !type.contains('menu');
        }
        return true;
      }).toList();

      final listToUse = nonMenuGallery.isNotEmpty ? nonMenuGallery : gallery;
      final img = listToUse[0];
      if (img is Map) {
        final path = img['url'] ?? img['filePath'];
        if (path != null && path.toString().isNotEmpty) {
          return normalize(path.toString());
        }
      }
    }

    final idHash = (venue['name']?.toString() ?? 'venue').hashCode.abs() % 20;
    return 'https://picsum.photos/seed/$idHash/600/400';
  }

  String _formatBookingDateTime(String bookingDateStr, String startTimeStr) {
    if (bookingDateStr.trim().isEmpty) {
      return '• $startTimeStr';
    }
    try {
      final date = DateTime.parse(bookingDateStr).toLocal();
      final formattedDate = DateFormat('MMM d, yyyy').format(date).toUpperCase();
      return '$formattedDate • $startTimeStr';
    } catch (_) {
      return '$bookingDateStr • $startTimeStr';
    }
  }

  String _formatTablePackage(String? tablePackage) {
    if (tablePackage == null || tablePackage.toLowerCase() == 'none' || tablePackage.trim().isEmpty) {
      return 'GENERAL';
    }
    final clean = tablePackage.trim();
    if (clean.toLowerCase().contains('confirmation')) {
      return 'STANDARD';
    }
    return clean.toUpperCase();
  }

  String _getBookingStatus(Map<String, dynamic> booking, bool isActive) {
    final status = booking['status']?.toString().toLowerCase();
    if (status == 'cancelled') return 'CANCELLED';
    if (status == 'no_show') return 'NO SHOW';

    if (isActive) {
      if (status == 'pending') return 'PENDING';
      return 'CONFIRMED';
    } else {
      if (status == 'completed' || status == 'used') return 'USED';
      return 'EXPIRED';
    }
  }

  Widget _buildTicketExpirationCard(
    Map<String, dynamic> booking, {
    required bool isActive,
  }) {
    final eventStart = _extractEventStartDateTime(booking);
    final expirationTime = _extractExpirationDateTime(booking, eventStart);
    final now = DateTime.now();

    final bool isExpired = expirationTime != null ? now.isAfter(expirationTime) : !isActive;
    final bool isLiveNow = eventStart != null &&
        expirationTime != null &&
        now.isAfter(eventStart) &&
        now.isBefore(expirationTime);

    final String expiryDateFormatted = expirationTime != null
        ? DateFormat('EEE, MMM d, yyyy • h:mm a').format(expirationTime)
        : (eventStart != null
            ? DateFormat('EEE, MMM d, yyyy • h:mm a').format(eventStart.add(const Duration(hours: 4)))
            : 'END OF EVENT');

    String badgeLabel = 'VALID';
    Color themeColor = _lunaraPurple;
    IconData leadingIcon = Icons.verified_outlined;

    if (isExpired) {
      badgeLabel = 'EXPIRED';
      themeColor = const Color(0xFFEF4444);
      leadingIcon = Icons.event_busy_rounded;
    } else if (isLiveNow) {
      final remaining = expirationTime.difference(now);
      final hrs = remaining.inHours;
      final mins = remaining.inMinutes % 60;
      badgeLabel = hrs > 0 ? 'LIVE NOW • ${hrs}h ${mins}m LEFT' : 'LIVE NOW • ${mins}m LEFT';
      themeColor = const Color(0xFF10B981);
      leadingIcon = Icons.bolt_rounded;
    } else if (eventStart != null) {
      final untilStart = eventStart.difference(now);
      if (untilStart.inDays > 0) {
        badgeLabel = 'STARTS IN ${untilStart.inDays} ${untilStart.inDays == 1 ? 'DAY' : 'DAYS'}';
      } else if (untilStart.inHours > 0) {
        badgeLabel = 'STARTS IN ${untilStart.inHours}h ${untilStart.inMinutes % 60}m';
      } else if (untilStart.inMinutes > 0) {
        badgeLabel = 'STARTS IN ${untilStart.inMinutes}m';
      } else {
        badgeLabel = 'UPCOMING';
      }
      themeColor = _lunaraPurple;
      leadingIcon = Icons.access_time_rounded;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: themeColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: themeColor.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: themeColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              leadingIcon,
              size: 16,
              color: themeColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        isExpired ? 'TICKET EXPIRED' : 'EXPIRES ON',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.8,
                          color: themeColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                          color: themeColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  expiryDateFormatted,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isExpired ? Colors.grey[700] : const Color(0xFF0F172A),
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeList = _getActiveBookings();
    final pastList = _getPastBookings();
    final currentPool = _tabController.index == 0 ? activeList : pastList;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildStatsBanner(activeList.length, pastList.length),
            _buildTabBar(activeList.length, pastList.length),
            _buildCategoryFilterBar(currentPool),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: _lunaraPurple,
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTicketListView(activeList, isActive: true),
                        _buildTicketListView(pastList, isActive: false),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.black, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: _lunaraPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.confirmation_number_rounded,
                  color: _lunaraPurple,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'TICKET POCKET',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.5,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.black, size: 22),
            onPressed: _loadBookings,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBanner(int activeCount, int pastCount) {
    final totalCount = _allBookings.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _lunaraPurple.withValues(alpha: 0.08),
            const Color(0xFF9333EA).withValues(alpha: 0.03),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _lunaraPurple.withValues(alpha: 0.16),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _lunaraPurple.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 16,
              color: _lunaraPurple,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'TOTAL BOOKINGS',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.0,
                    color: Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  '$totalCount ${totalCount == 1 ? 'TICKET' : 'TICKETS'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.3,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _statPill('ACTIVE', activeCount, const Color(0xFF10B981)),
              const SizedBox(width: 5),
              _statPill('PAST', pastCount, Colors.grey[700]!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(int activeCount, int pastCount) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[200]!),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: _lunaraPurpleGradient,
          borderRadius: BorderRadius.circular(13),
          boxShadow: [
            BoxShadow(
              color: _lunaraPurple.withValues(alpha: 0.35),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(3),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.black54,
        labelStyle: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.5,
        ),
        dividerHeight: 0,
        tabs: [
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('ACTIVE'),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _tabController.index == 0
                        ? Colors.white.withValues(alpha: 0.25)
                        : _lunaraPurple.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$activeCount',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: _tabController.index == 0 ? Colors.white : _lunaraPurple,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Tab(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('PAST'),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: _tabController.index == 1
                        ? Colors.white.withValues(alpha: 0.25)
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$pastCount',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: _tabController.index == 1 ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryFilterBar(List<Map<String, dynamic>> currentPool) {
    return Container(
      height: 42,
      margin: const EdgeInsets.only(top: 4, bottom: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: TicketFilterCategory.values.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final cat = TicketFilterCategory.values[index];
          final isSelected = _selectedCategory == cat;
          final count = _getCategoryCount(currentPool, cat);
          final catColor = cat == TicketFilterCategory.all
              ? _lunaraPurple
              : _getCategoryColor(cat.key);

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedCategory = cat;
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
              decoration: BoxDecoration(
                gradient: isSelected ? _lunaraPurpleGradient : null,
                color: isSelected ? null : Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? _lunaraPurple
                      : (count > 0 ? catColor.withValues(alpha: 0.3) : Colors.grey[200]!),
                  width: isSelected ? 1.5 : 1,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: _lunaraPurple.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.02),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    cat.icon,
                    size: 13,
                    color: isSelected ? Colors.white : (count > 0 ? catColor : Colors.grey[500]),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    cat.label,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                      letterSpacing: 0.6,
                      color: isSelected ? Colors.white : (count > 0 ? Colors.black87 : Colors.grey[500]),
                    ),
                  ),
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withValues(alpha: 0.28)
                          : (count > 0 ? catColor.withValues(alpha: 0.12) : Colors.grey[200]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        color: isSelected ? Colors.white : (count > 0 ? catColor : Colors.grey[600]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTicketListView(List<Map<String, dynamic>> rawList, {required bool isActive}) {
    final filteredTickets = _filterListByCategory(rawList, _selectedCategory);

    if (filteredTickets.isEmpty) {
      return _buildEmptyState(
        _selectedCategory == TicketFilterCategory.all
            ? (isActive ? 'NO ACTIVE TICKETS FOUND' : 'NO PAST TICKETS FOUND')
            : 'NO ${isActive ? 'ACTIVE' : 'PAST'} ${_selectedCategory.label} TICKETS FOUND',
      );
    }

    return RefreshIndicator(
      color: _lunaraPurple,
      onRefresh: _loadBookings,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: filteredTickets.length,
        itemBuilder: (context, index) {
          final booking = filteredTickets[index];
          return _buildTicketCard(booking, isActive: isActive);
        },
      ),
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(22),
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.grey[200]!),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Icon(
                  _selectedCategory == TicketFilterCategory.all
                      ? Icons.confirmation_number_outlined
                      : _selectedCategory.icon,
                  size: 48,
                  color: _selectedCategory == TicketFilterCategory.all
                      ? Colors.grey[400]
                      : _getCategoryColor(_selectedCategory.key),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Book tables, host party plans, join group parties, or meet new people.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[400],
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_selectedCategory != TicketFilterCategory.all) ...[
                const SizedBox(height: 16),
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedCategory = TicketFilterCategory.all;
                    });
                  },
                  icon: const Icon(Icons.clear_all_rounded, size: 16, color: _lunaraPurple),
                  label: const Text(
                    'SHOW ALL TICKETS',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: _lunaraPurple,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTicketCard(
    Map<String, dynamic> booking, {
    required bool isActive,
  }) {
    final status = _getBookingStatus(booking, isActive);
    final statusColor = switch (status) {
      'CONFIRMED' => _lunaraPurple,
      'PENDING' => Colors.amber.shade700,
      'USED' => Colors.black,
      'EXPIRED' => Colors.red.shade400,
      _ => Colors.black,
    };

    final category = _getTicketCategory(booking);
    final categoryColor = _getCategoryColor(category);
    final categoryName = _getCategoryDisplayName(category);
    final categoryIcon = _getCategoryIcon(category);

    final venue = booking['venue'] as Map<String, dynamic>?;
    final venueName =
        venue?['name']?.toString() ??
        booking['venueName']?.toString() ??
        'LUNARA VENUE';
    final imageUrl = _getVenueImageUrl(venue);
    final bookingDate = booking['bookingDate']?.toString() ?? '';
    final startTime = booking['startTime']?.toString() ?? '';
    final dateStr = _formatBookingDateTime(bookingDate, startTime);

    final eventTitle = booking['subject']?.toString().trim().isNotEmpty == true
        ? booking['subject'].toString()
        : (booking['eventTitle']?.toString().trim().isNotEmpty == true
            ? booking['eventTitle'].toString()
            : (booking['partySubject']?.toString().trim().isNotEmpty == true
                ? booking['partySubject'].toString()
                : null));
    final displayTitle = (category == 'strangers_meet' || category == 'party_plan' || category == 'event_booking') && eventTitle != null
        ? eventTitle
        : venueName;
    final displaySubtitle = (displayTitle != venueName)
        ? '$venueName • $dateStr'
        : dateStr;

    final table = category == 'strangers_meet'
        ? 'STRANGER MEET'
        : _formatTablePackage(booking['tablePackage']?.toString());
    final guests = booking['numberOfGuests'] ?? (category == 'strangers_meet' ? 2 : 1);

    final String totalPriceStr = booking['totalAmount']?.toString() ??
        booking['paymentAmount']?.toString() ??
        booking['chargesPerHead']?.toString() ??
        booking['charges']?.toString() ??
        '';
    final double amountPaid = double.tryParse(totalPriceStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final String displayAmount = amountPaid > 0 ? '₹${amountPaid.toStringAsFixed(0)}' : 'FREE';

    final ticketCode = booking['ticketCode']?.toString() ??
        booking['ticketId']?.toString() ??
        (booking['id'] != null ? booking['id'].toString().substring(0, 8).toUpperCase() : '');

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GestureDetector(
        onTap: () {
          // Party plan tickets have dedicated matched UI
          if (category == 'party_plan') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanTicketScreen(
                  request: Map<String, dynamic>.from(booking['rawRequest'] ?? booking['plan'] ?? booking),
                  plan: Map<String, dynamic>.from(booking['plan'] ?? booking),
                  isHost: booking['isHost'] == true,
                ),
              ),
            );
            return;
          }

          // Group party / Large party tickets via LargePartyTicketScreen
          if (category == 'large_party' || category == 'group_party') {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LargePartyTicketScreen(
                  booking: booking,
                  venue: venue ?? {'name': venueName, 'id': booking['venueId']},
                ),
              ),
            );
            return;
          }

          // Strangers meet tickets
          if (category == 'strangers_meet') {
            try {
              final rawMap = booking['rawRequest'] is Map
                  ? Map<String, dynamic>.from(booking['rawRequest'])
                  : Map<String, dynamic>.from(booking);
              if (booking['venue'] is Map && rawMap['venue'] == null) {
                rawMap['venue'] = booking['venue'];
              }
              if (booking['user'] is Map && rawMap['user'] == null) {
                rawMap['user'] = booking['user'];
              }
              if (booking['host'] is Map && rawMap['host'] == null) {
                rawMap['host'] = booking['host'];
              }
              if (booking['ticketCode'] != null && rawMap['ticketId'] == null) {
                rawMap['ticketId'] = booking['ticketCode'];
              }
              if (rawMap['ticketCode'] == null && booking['ticketCode'] != null) {
                rawMap['ticketCode'] = booking['ticketCode'];
              }
              final totalAmt = booking['totalAmount'] ?? booking['paymentAmount'] ?? booking['chargesPerHead'];
              if (totalAmt != null && (rawMap['paymentAmount'] == null || rawMap['paymentAmount'] == 0)) {
                rawMap['paymentAmount'] = totalAmt;
              }
              if (booking['subject'] != null && rawMap['subject'] == null) {
                rawMap['subject'] = booking['subject'];
              }
              if (booking['tagline'] != null && rawMap['tagline'] == null) {
                rawMap['tagline'] = booking['tagline'];
              }
              if (booking['startTime'] != null && rawMap['startTime'] == null) {
                rawMap['startTime'] = booking['startTime'];
              }
              final req = StrangersMeetRequest.fromJson(rawMap);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StrangersMeetTicketScreen(request: req),
                ),
              );
              return;
            } catch (e) {
              debugPrint('Failed to launch StrangersMeetTicketScreen: $e');
            }
          }

          // Standard Digital Ticket Screen (Solo / Event / Venue)
          final bool isEventTicket = category == 'event_booking' ||
              booking['isUpcomingNight'] == true ||
              booking['isEventBooking'] == true;

          // Resolve banner image - prefer partyEvent bannerImageUrl, then booking fields
          String? resolvedBannerUrl;
          final partyEvent = booking['partyEvent'];
          if (partyEvent is Map) {
            resolvedBannerUrl =
                partyEvent['bannerImageUrl']?.toString().trim().isNotEmpty == true
                    ? partyEvent['bannerImageUrl'].toString()
                    : partyEvent['imagePath']?.toString().trim().isNotEmpty == true
                        ? partyEvent['imagePath'].toString()
                        : null;
          }
          resolvedBannerUrl ??=
              booking['bannerImageUrl']?.toString().trim().isNotEmpty == true
                  ? booking['bannerImageUrl'].toString()
                  : booking['eventPoster']?.toString().trim().isNotEmpty == true
                      ? booking['eventPoster'].toString()
                      : null;

          // Resolve event title
          String? resolvedEventTitle;
          if (partyEvent is Map) {
            resolvedEventTitle = partyEvent['title']?.toString().trim().isNotEmpty == true
                ? partyEvent['title'].toString()
                : null;
          }
          resolvedEventTitle ??=
              booking['eventTitle']?.toString().trim().isNotEmpty == true
                  ? booking['eventTitle'].toString()
                  : booking['partySubject']?.toString().trim().isNotEmpty == true
                      ? booking['partySubject'].toString()
                      : null;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DigitalTicketScreen(
                venue: venue ?? {'name': venueName, 'imageUrl': imageUrl},
                date: dateStr,
                table: table,
                guests: guests.toString(),
                package: table,
                totalPrice:
                    booking['totalAmount']?.toString() ??
                    booking['paymentAmount']?.toString(),
                ticketId: ticketCode,
                ticketUrl: booking['ticketUrl'] ?? booking['ticket_url'],
                status: status,
                booking: booking,
                bannerImageUrl: resolvedBannerUrl,
                eventTitle: resolvedEventTitle,
                user: booking['user'] ?? booking['host'] ?? ApiService.cachedCurrentUser,
                isUpcomingNight: isEventTicket,
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
            border: Border.all(
              color: categoryColor.withValues(alpha: 0.16),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header Banner on Image ───────────────────────────
              Container(
                height: 145,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(23),
                  ),
                  image: DecorationImage(
                    image: NetworkImage(imageUrl),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(23),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.45),
                        Colors.black.withValues(alpha: 0.85),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Stack(
                    children: [
                      // Top Row: Category Tag + Status Badge
                      Align(
                        alignment: Alignment.topLeft,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.65),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: categoryColor.withValues(alpha: 0.5),
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(categoryIcon, size: 12, color: categoryColor),
                                  const SizedBox(width: 5),
                                  Text(
                                    categoryName,
                                    style: TextStyle(
                                      color: categoryColor,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4.5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: statusColor.withValues(alpha: 0.25),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Text(
                                status,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Bottom Details on Image
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    displayTitle,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 18,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    displaySubtitle,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.9),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.4,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (ticketCode.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  ticketCode,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (status == 'EXPIRED' || !isActive)
                        Positioned(
                          top: 0,
                          right: 0,
                          child: _buildExpiredWatermark(),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Card Body ─────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildTicketExpirationCard(booking, isActive: isActive),
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              _infoChip(Icons.table_bar_outlined, table, flex: 2),
                              const SizedBox(width: 4),
                              _infoChip(Icons.group_outlined, '$guests', flex: 1),
                              const SizedBox(width: 4),
                              _infoChip(Icons.payments_outlined, displayAmount, flex: 1),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8.5,
                          ),
                          decoration: BoxDecoration(
                            gradient: isActive
                                ? _lunaraPurpleGradient
                                : null,
                            color: isActive ? null : Colors.grey[200],
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: isActive
                                ? [
                                    BoxShadow(
                                      color: _lunaraPurple.withValues(alpha: 0.35),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            'VIEW TICKET',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: isActive ? Colors.white : Colors.black54,
                            ),
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
      ),
    );
  }

  Widget _infoChip(IconData icon, String label, {int flex = 1}) {
    return Flexible(
      flex: flex,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.grey[400], size: 15),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpiredWatermark() {
    return IgnorePointer(
      child: Transform.rotate(
        angle: -0.22,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.red.shade600,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            'EXPIRED',
            style: TextStyle(
              color: Colors.red.shade600,
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 3.5,
            ),
          ),
        ),
      ),
    );
  }
}
