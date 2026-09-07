import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../discovery/digital_ticket_screen.dart';
import '../profile/lunara_wallet_screen.dart';
import '../social/large_party_ticket_screen.dart';
import '../social/party_plan_ticket_screen.dart';
import '../social/strangers_meet_ticket_screen.dart';
import '../../models/strangers_meet_request.dart';
import '../../utils/lunara_date_formatter.dart';

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
  List<Map<String, dynamic>> _allBookings = [];
  List<Map<String, dynamic>> _activeBookings = [];
  List<Map<String, dynamic>> _pastBookings = [];
  List<Map<String, dynamic>> _cancelledBookings = [];
  final Map<String, int> _activeCategoryCounts = {};
  final Map<String, int> _pastCategoryCounts = {};
  final Map<String, int> _cancelledCategoryCounts = {};
  bool _isLoading = true;
  TicketFilterCategory _selectedCategory = TicketFilterCategory.all;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
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

  Timer? _ticketDebounceTimer;

  void _initListeners() {
    ApiService.planPostedNotifier.addListener(_onAutoRefresh);
    ApiService.addSocketListener('party_plan_ticket_generated', _onSocketUpdate);
    ApiService.addSocketListener('ticket_updated', _onSocketUpdate);
    ApiService.addSocketListener('ticket_status_update', _onSocketUpdate);
    ApiService.addSocketListener('party_plan_match_success', _onSocketUpdate);
    ApiService.addSocketListener('group_party_payment_success', _onSocketUpdate);
    ApiService.addSocketListener('strangers_meet_settled', _onSocketUpdate);
    ApiService.addSocketListener('notification_created', _onSocketUpdate);
  }

  void _disposeListeners() {
    _ticketDebounceTimer?.cancel();
    ApiService.planPostedNotifier.removeListener(_onAutoRefresh);
    ApiService.removeSocketListener('party_plan_ticket_generated', _onSocketUpdate);
    ApiService.removeSocketListener('ticket_updated', _onSocketUpdate);
    ApiService.removeSocketListener('ticket_status_update', _onSocketUpdate);
    ApiService.removeSocketListener('party_plan_match_success', _onSocketUpdate);
    ApiService.removeSocketListener('group_party_payment_success', _onSocketUpdate);
    ApiService.removeSocketListener('strangers_meet_settled', _onSocketUpdate);
    ApiService.removeSocketListener('notification_created', _onSocketUpdate);
  }

  void _onAutoRefresh() {
    if (!mounted) return;
    _ticketDebounceTimer?.cancel();
    _ticketDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadBookings(forceRefresh: true);
    });
  }

  void _onSocketUpdate(dynamic data) {
    if (!mounted) return;
    _ticketDebounceTimer?.cancel();
    _ticketDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _loadBookings(forceRefresh: true);
    });
  }

  Future<void> _loadBookings({bool forceRefresh = false}) async {
    if (_allBookings.isEmpty) {
      setState(() {
        _isLoading = true;
      });
    }
    final tickets = await ApiService.fetchAllUserTickets(forceRefresh: forceRefresh);
    if (mounted) {
      final active = <Map<String, dynamic>>[];
      final past = <Map<String, dynamic>>[];
      final cancelled = <Map<String, dynamic>>[];
      final activeCounts = <String, int>{};
      final pastCounts = <String, int>{};
      final cancelledCounts = <String, int>{};

      for (final t in tickets) {
        final cat = _getTicketCategory(t);
        if (_isCancelledBooking(t)) {
          cancelled.add(t);
          cancelledCounts[cat] = (cancelledCounts[cat] ?? 0) + 1;
        } else if (_isActiveBooking(t)) {
          active.add(t);
          activeCounts[cat] = (activeCounts[cat] ?? 0) + 1;
        } else {
          past.add(t);
          pastCounts[cat] = (pastCounts[cat] ?? 0) + 1;
        }
      }

      setState(() {
        _allBookings = tickets;
        _activeBookings = active;
        _pastBookings = past;
        _cancelledBookings = cancelled;
        _activeCategoryCounts.clear();
        _activeCategoryCounts.addAll(activeCounts);
        _pastCategoryCounts.clear();
        _pastCategoryCounts.addAll(pastCounts);
        _cancelledCategoryCounts.clear();
        _cancelledCategoryCounts.addAll(cancelledCounts);
        _isLoading = false;
      });
    }
  }

  String _getTicketCategory(Map<String, dynamic> booking) {
    // 1. Check strong Party Plan indicators first (ensuring Host and Joiner party plans are NEVER misclassified as venue_booking)
    final isPartyPlan = booking['isPartyPlan'] == true ||
        booking['category']?.toString().toLowerCase() == 'party_plan' ||
        booking['bookingType']?.toString().toLowerCase() == 'party_plan' ||
        booking['type']?.toString().toLowerCase() == 'party_plan' ||
        (booking['goingMode'] ?? booking['booking']?['goingMode'])?.toString().toLowerCase() == 'plan' ||
        (booking['ticketCode'] ?? booking['ticketId'])?.toString().toUpperCase().startsWith('PP-') == true ||
        booking['plan'] != null ||
        booking['partyPlanId'] != null ||
        booking['planId'] != null ||
        booking['tablePackage']?.toString().toLowerCase().contains('party plan') == true ||
        booking['partySubject']?.toString().toLowerCase().contains('party plan') == true ||
        (booking['specialRequests'] != null && booking['specialRequests'].toString().contains('planId'));
    if (isPartyPlan) return 'party_plan';

    // 2. Check strong Strangers Meet indicators
    final isStrangersMeet = booking['isStrangersMeet'] == true ||
        booking['category']?.toString().toLowerCase() == 'strangers_meet' ||
        booking['bookingType']?.toString().toLowerCase() == 'strangers_meet' ||
        booking['type']?.toString().toLowerCase() == 'strangers_meet' ||
        (booking['ticketCode'] ?? booking['ticketId'])?.toString().toUpperCase().startsWith('SM-') == true ||
        booking['strangersMeet'] != null ||
        booking['strangersMeetRequestId'] != null;
    if (isStrangersMeet) return 'strangers_meet';

    // 3. Check explicit server-provided category if non-generic
    if (booking['category'] != null && booking['category'].toString().isNotEmpty) {
      final cat = booking['category'].toString().toLowerCase().trim();
      if (cat == 'group_party' ||
          cat == 'large_party' ||
          cat == 'solo' ||
          cat == 'event_booking') {
        return cat;
      }
    }

    // Comprehensive fallback classification
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
    final innerPlan = booking['plan'] is Map ? booking['plan'] : (booking['rawRequest'] is Map ? booking['rawRequest'] : null);
    final dateStr = booking['planDateTime']?.toString() ??
        innerPlan?['planDateTime']?.toString() ??
        booking['eventStartAt']?.toString() ??
        booking['eventDateTime']?.toString() ??
        innerPlan?['eventDateTime']?.toString() ??
        booking['bookingDate']?.toString() ??
        booking['partyDate']?.toString() ??
        booking['date']?.toString();
    final startTimeStr = booking['startTime']?.toString() ??
        booking['partyTime']?.toString() ??
        booking['time']?.toString() ??
        innerPlan?['startTime']?.toString() ??
        innerPlan?['time']?.toString();
    final cleanTime = (startTimeStr != null && startTimeStr.trim().isNotEmpty)
        ? LunaraDateFormatter.normalizeTimeTo12Hour(startTimeStr)
        : null;

    return LunaraDateFormatter.parseToLocal(
      dateStr,
      explicitTime: cleanTime,
    );
  }

  DateTime? _extractExpirationDateTime(Map<String, dynamic> booking, DateTime? eventStart) {
    if (eventStart == null) return null;

    // Strangers Meet and standard tickets expire strictly 2 hours after scheduled event start time
    final defaultExp = eventStart.add(const Duration(hours: 2));

    final isStrangersMeet = booking['isStrangersMeet'] == true ||
        booking['bookingType'] == 'strangers_meet' ||
        booking['type'] == 'strangers_meet' ||
        (booking['tablePackage']?.toString().toUpperCase().contains('STRANGER') == true);

    final isLargeParty = booking['isLargeParty'] == true ||
        booking['isLargePartyRequest'] == true ||
        booking['bookingType'] == 'large_party' ||
        booking['category'] == 'large_party' ||
        booking['goingMode'] == 'party_request' ||
        (booking['numberOfGuests'] != null && int.tryParse(booking['numberOfGuests'].toString()) != null && int.parse(booking['numberOfGuests'].toString()) > 20);

    final isGroupParty = booking['isGroupParty'] == true ||
        booking['bookingType'] == 'group_party' ||
        booking['category'] == 'group_party';

    if (isStrangersMeet || isLargeParty || isGroupParty) {
      return defaultExp;
    }

    if (booking['ticketExpiresAt'] != null) {
      final dt = DateTime.tryParse(booking['ticketExpiresAt'].toString())?.toLocal();
      if (dt != null && dt.isAfter(eventStart)) {
        if (dt.hour == 0 && dt.minute == 0 && (eventStart.hour != 0 || eventStart.minute != 0)) {
          return defaultExp;
        }
        return dt;
      }
    }
    if (booking['expiresAt'] != null) {
      final dt = DateTime.tryParse(booking['expiresAt'].toString())?.toLocal();
      if (dt != null && dt.isAfter(eventStart)) {
        if (dt.hour == 0 && dt.minute == 0 && (eventStart.hour != 0 || eventStart.minute != 0)) {
          return defaultExp;
        }
        return dt;
      }
    }
    if (booking['eventEndAt'] != null) {
      final dt = DateTime.tryParse(booking['eventEndAt'].toString())?.toLocal();
      if (dt != null && dt.isAfter(eventStart)) return dt;
    }

    return defaultExp;
  }

  bool _isCancelledBooking(Map<String, dynamic> booking) {
    final status = (booking['status'] ?? booking['bookingStatus'] ?? booking['ticketStatus'] ?? '').toString().toLowerCase().trim();
    final paymentStatus = (booking['paymentStatus'] ?? '').toString().toLowerCase().trim();
    final isCancelledFlag = booking['isCancelled'] == true;
    final cancelStatus = (booking['cancellationStatus'] ?? booking['cancellation_status'] ?? '').toString().toLowerCase().trim();

    return isCancelledFlag ||
        status == 'cancelled' ||
        status == 'rejected' ||
        status == 'void' ||
        status == 'no_show' ||
        cancelStatus == 'approved' ||
        cancelStatus == 'refunded' ||
        cancelStatus == 'cancelled' ||
        paymentStatus == 'refunded';
  }

  bool _isActiveBooking(Map<String, dynamic> booking) {
    if (_isCancelledBooking(booking)) return false;
    try {
      final status = booking['status']?.toString().toLowerCase().trim() ?? '';
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

  List<Map<String, dynamic>> _filterListByCategory(
    List<Map<String, dynamic>> list,
    TicketFilterCategory category,
  ) {
    if (category == TicketFilterCategory.all) return list;
    return list.where((b) => _getTicketCategory(b) == category.key).toList();
  }

  int _getCategoryCount(
    TicketFilterCategory category, {
    required int tabIndex,
  }) {
    if (category == TicketFilterCategory.all) {
      if (tabIndex == 0) return _activeBookings.length;
      if (tabIndex == 1) return _pastBookings.length;
      return _cancelledBookings.length;
    }
    final counts = tabIndex == 0
        ? _activeCategoryCounts
        : (tabIndex == 1 ? _pastCategoryCounts : _cancelledCategoryCounts);
    return counts[category.key] ?? 0;
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

    if (venue['coverImageUrl'] != null && venue['coverImageUrl'].toString().trim().isNotEmpty && !venue['coverImageUrl'].toString().toLowerCase().contains('menu')) {
      return normalize(venue['coverImageUrl'].toString());
    }

    if (venue['profilePhotoUrl'] != null && venue['profilePhotoUrl'].toString().trim().isNotEmpty && !venue['profilePhotoUrl'].toString().toLowerCase().contains('menu')) {
      return normalize(venue['profilePhotoUrl'].toString());
    }

    if (venue['coverImage'] != null && venue['coverImage'] is Map) {
      final path =
          venue['coverImage']['url'] ?? venue['coverImage']['filePath'];
      if (path != null && path.toString().isNotEmpty) {
        return normalize(path.toString());
      }
    }

    if (venue['imageUrl'] != null && venue['imageUrl'].toString().isNotEmpty && !venue['imageUrl'].toString().toLowerCase().contains('menu')) {
      return normalize(venue['imageUrl'].toString());
    }
    if (venue['image'] != null && venue['image'].toString().isNotEmpty && !venue['image'].toString().toLowerCase().contains('menu')) {
      return normalize(venue['image'].toString());
    }

    final images = venue['images'];
    if (images is List && images.isNotEmpty) {
      final nonMenuImages = images.where((img) {
        if (img is Map) {
          final type = (img['imageType'] ?? img['type'] ?? img['category'] ?? '').toString().toLowerCase();
          return !type.contains('menu') && !type.contains('package');
        }
        return true;
      }).toList();

      if (nonMenuImages.isNotEmpty) {
        final first = nonMenuImages.first;
        if (first is Map) {
          final path = first['url'] ?? first['filePath'];
          if (path != null && path.toString().isNotEmpty) {
            return normalize(path.toString());
          }
        }
      }
    }

    final gallery = venue['gallery'];
    if (gallery is List && gallery.isNotEmpty) {
      final nonMenuGallery = gallery.where((img) {
        if (img is Map) {
          final type = (img['imageType'] ?? img['type'] ?? img['category'] ?? '').toString().toLowerCase();
          return !type.contains('menu') && !type.contains('package');
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
    final cleanTime = startTimeStr.trim().isNotEmpty
        ? LunaraDateFormatter.normalizeTimeTo12Hour(startTimeStr)
        : '';
    final dt = LunaraDateFormatter.parseToLocal(
      bookingDateStr,
      // Only pass explicitTime when we KNOW the event start-time.
      // If cleanTime is empty, do NOT let parseToLocal use the ISO timestamp's
      // time component — for party plans that timestamp is a creation/booking
      // time, not the actual party start time, and would show a wrong value.
      explicitTime: cleanTime.isNotEmpty ? cleanTime : null,
    );
    if (dt == null) {
      return cleanTime.isNotEmpty ? '$bookingDateStr • $cleanTime' : bookingDateStr;
    }
    final formattedDate = LunaraDateFormatter.formatEventDate(dt, pattern: 'MMM d, yyyy').toUpperCase();
    // Only append a time when we have an explicit startTime string.
    // Falling back to the ISO time component risks showing a creation/system
    // timestamp (e.g. 4:46 PM) instead of the real event time (10:16 PM).
    if (cleanTime.isNotEmpty) {
      return '$formattedDate • $cleanTime';
    }
    return formattedDate;
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

  String _getBookingStatus(Map<String, dynamic> booking, int tabIndex) {
    if (tabIndex == 2 || _isCancelledBooking(booking)) return 'CANCELLED';
    final status = (booking['status'] ?? booking['bookingStatus'] ?? booking['ticketStatus'] ?? '').toString().toLowerCase().trim();
    if (status == 'cancelled' || status == 'void' || status == 'rejected') return 'CANCELLED';
    if (status == 'no_show') return 'NO SHOW';

    if (tabIndex == 0) {
      if (status == 'pending') return 'PENDING';
      return 'CONFIRMED';
    } else {
      if (status == 'completed' || status == 'used') return 'USED';
      return 'EXPIRED';
    }
  }

  Widget _buildTicketExpirationCard(
    Map<String, dynamic> booking, {
    required int tabIndex,
  }) {
    final bool isCancelled = tabIndex == 2 || _isCancelledBooking(booking);
    if (isCancelled) {
      final String totalPriceStr = booking['totalAmount']?.toString() ??
          booking['paymentAmount']?.toString() ??
          booking['chargesPerHead']?.toString() ??
          booking['charges']?.toString() ??
          '';
      final double amountPaid = double.tryParse(totalPriceStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
      final double refundAmount = (booking['refundAmount'] is num)
          ? (booking['refundAmount'] as num).toDouble()
          : (double.tryParse(booking['refundAmount']?.toString() ?? '') ?? 0.0);
      final int refundPct = (booking['refundPercentage'] is num)
          ? (booking['refundPercentage'] as num).toInt()
          : (int.tryParse(booking['refundPercentage']?.toString() ?? '') ?? (amountPaid > 0 && refundAmount > 0 ? ((refundAmount / amountPaid) * 100).round() : 100));
      final double effectiveRefund = refundAmount > 0 ? refundAmount : (amountPaid > 0 ? (amountPaid * refundPct / 100.0) : 0.0);
      final String refundStr = effectiveRefund > 0 ? '₹${effectiveRefund.toStringAsFixed(0)} ($refundPct%)' : '';
      final String subtext = effectiveRefund > 0
          ? '$refundStr refunded to your Lunara Wallet'
          : 'This booking / ticket has been cancelled.';

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEF4444).withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFFEF4444).withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.cancel_outlined,
                size: 16,
                color: Color(0xFFEF4444),
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
                      const Flexible(
                        child: Text(
                          'BOOKING CANCELLED',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.8,
                            color: Color(0xFFEF4444),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          amountPaid > 0 ? 'REFUNDED' : 'CANCELLED',
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                            color: Color(0xFFEF4444),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtext,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                      letterSpacing: 0.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    final bool isActive = tabIndex == 0;
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildStatsBanner(_activeBookings.length, _pastBookings.length, _cancelledBookings.length),
            _buildTabBar(_activeBookings.length, _pastBookings.length, _cancelledBookings.length),
            _buildCategoryFilterBar(tabIndex: _tabController.index),
            Expanded(
              child: (_isLoading && _allBookings.isEmpty)
                  ? _buildSkeletonList()
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildTicketListView(_activeBookings, tabIndex: 0),
                        _buildTicketListView(_pastBookings, tabIndex: 1),
                        _buildTicketListView(_cancelledBookings, tabIndex: 2),
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
            onPressed: () => _loadBookings(forceRefresh: true),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsBanner(int activeCount, int pastCount, int cancelledCount) {
    final totalCount = _allBookings.length;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: _lunaraPurple.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_rounded,
              size: 15,
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
                    fontSize: 8.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.8,
                    color: Colors.black54,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$totalCount ${totalCount == 1 ? 'TICKET' : 'TICKETS'}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: Color(0xFF0F172A),
                    letterSpacing: 0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _statPill('ACTIVE', activeCount, const Color(0xFF10B981)),
                  const SizedBox(width: 3.5),
                  _statPill('PAST', pastCount, Colors.grey[700]!),
                  const SizedBox(width: 3.5),
                  _statPill('CANCELLED', cancelledCount, const Color(0xFFEF4444)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statPill(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4.5,
            height: 4.5,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 3.5),
          Text(
            '$count $label',
            style: TextStyle(
              fontSize: 8.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.2,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(int activeCount, int pastCount, int cancelledCount) {
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
        padding: const EdgeInsets.all(3),
        labelPadding: EdgeInsets.zero,
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
        labelColor: Colors.white,
        unselectedLabelColor: Colors.black54,
        labelStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
        ),
        dividerHeight: 0,
        tabs: [
          Tab(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('ACTIVE'),
                    const SizedBox(width: 4),
                    _tabBadge(activeCount, isSelected: _tabController.index == 0, color: _lunaraPurple),
                  ],
                ),
              ),
            ),
          ),
          Tab(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('PAST'),
                    const SizedBox(width: 4),
                    _tabBadge(pastCount, isSelected: _tabController.index == 1, color: Colors.grey[700]!),
                  ],
                ),
              ),
            ),
          ),
          Tab(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('CANCELLED'),
                    const SizedBox(width: 4),
                    _tabBadge(cancelledCount, isSelected: _tabController.index == 2, color: const Color(0xFFEF4444)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabBadge(int count, {required bool isSelected, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: isSelected
            ? Colors.white.withValues(alpha: 0.25)
            : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w900,
          color: isSelected ? Colors.white : color,
        ),
      ),
    );
  }

  Widget _buildCategoryFilterBar({required int tabIndex}) {
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
          final count = _getCategoryCount(cat, tabIndex: tabIndex);
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

  Widget _buildSkeletonList() {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      itemCount: 3,
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.grey[200]!),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 145,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(23)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      height: 16,
                      width: 140,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      height: 12,
                      width: 220,
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          height: 28,
                          width: 80,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        Container(
                          height: 28,
                          width: 100,
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTicketListView(List<Map<String, dynamic>> rawList, {required int tabIndex}) {
    final filteredTickets = _filterListByCategory(rawList, _selectedCategory);

    if (filteredTickets.isEmpty) {
      final String emptyText;
      if (tabIndex == 0) {
        emptyText = _selectedCategory == TicketFilterCategory.all
            ? 'NO ACTIVE TICKETS FOUND'
            : 'NO ACTIVE ${_selectedCategory.label} TICKETS FOUND';
      } else if (tabIndex == 1) {
        emptyText = _selectedCategory == TicketFilterCategory.all
            ? 'NO PAST TICKETS FOUND'
            : 'NO PAST ${_selectedCategory.label} TICKETS FOUND';
      } else {
        emptyText = _selectedCategory == TicketFilterCategory.all
            ? 'NO CANCELLED TICKETS FOUND'
            : 'NO CANCELLED ${_selectedCategory.label} TICKETS FOUND';
      }

      return _buildEmptyState(
        emptyText,
        tabIndex: tabIndex,
      );
    }

    return RefreshIndicator(
      color: _lunaraPurple,
      onRefresh: () => _loadBookings(forceRefresh: true),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: filteredTickets.length,
        addAutomaticKeepAlives: true,
        addRepaintBoundaries: true,
        itemBuilder: (context, index) {
          final booking = filteredTickets[index];
          return _buildTicketCard(booking, tabIndex: tabIndex);
        },
      ),
    );
  }

  Widget _buildEmptyState(String message, {int tabIndex = 0}) {
    final String subText = tabIndex == 2
        ? 'You have no cancelled tickets. All your confirmed bookings are active or completed.'
        : 'Book tables, host party plans, join group parties, or meet new people.';

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
                  tabIndex == 2
                      ? Icons.cancel_outlined
                      : (_selectedCategory == TicketFilterCategory.all
                          ? Icons.confirmation_number_outlined
                          : _selectedCategory.icon),
                  size: 48,
                  color: tabIndex == 2
                      ? const Color(0xFFEF4444).withValues(alpha: 0.6)
                      : (_selectedCategory == TicketFilterCategory.all
                          ? Colors.grey[400]
                          : _getCategoryColor(_selectedCategory.key)),
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
                subText,
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
    required int tabIndex,
  }) {
    final bool isActive = tabIndex == 0;
    final bool isCancelled = tabIndex == 2 || _isCancelledBooking(booking);
    final status = _getBookingStatus(booking, tabIndex);
    final bool isExpired = status == 'EXPIRED' || tabIndex == 1;
    final statusColor = switch (status) {
      'CONFIRMED' => _lunaraPurple,
      'PENDING' => Colors.amber.shade700,
      'USED' => Colors.black,
      'EXPIRED' => Colors.red.shade400,
      'CANCELLED' => const Color(0xFFEF4444),
      'NO SHOW' => Colors.grey.shade600,
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
    final innerPlan = booking['plan'] is Map ? booking['plan'] : (booking['rawRequest'] is Map ? booking['rawRequest'] : null);
    final bookingDate = booking['planDateTime']?.toString() ??
        innerPlan?['planDateTime']?.toString() ??
        booking['eventStartAt']?.toString() ??
        booking['eventDateTime']?.toString() ??
        booking['partyDate']?.toString() ??
        booking['bookingDate']?.toString() ??
        '';
    final startTime = booking['startTime']?.toString() ??
        booking['partyTime']?.toString() ??
        booking['time']?.toString() ??
        booking['eventTime']?.toString() ??
        innerPlan?['startTime']?.toString() ??
        innerPlan?['partyTime']?.toString() ??
        innerPlan?['eventTime']?.toString() ??
        innerPlan?['time']?.toString() ??
        '';
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

    final ticketCode = booking['ticketCode'] ?? booking['ticketId'] ?? (booking['id']?.toString().substring(0, 8).toUpperCase() ?? '');

    final bool isEventTicket = category == 'event_booking' ||
        booking['isUpcomingNight'] == true ||
        booking['isEventBooking'] == true;

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

    final cardHeaderImage = (isEventTicket && resolvedBannerUrl != null && resolvedBannerUrl.isNotEmpty)
        ? (resolvedBannerUrl.startsWith('http')
            ? resolvedBannerUrl
            : '${ApiService.baseUrl}/${resolvedBannerUrl.startsWith('/') ? resolvedBannerUrl.substring(1) : resolvedBannerUrl}')
        : imageUrl;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: GestureDetector(
        onTap: () {
          if (isCancelled && amountPaid > 0) {
            Navigator.push(context, MaterialPageRoute(builder: (_) => const LunaraWalletScreen()));
            return;
          }

          // Party plan tickets have dedicated matched UI
          if (category == 'party_plan') {
            final rawPlan = booking['plan'] is Map
                ? Map<String, dynamic>.from(booking['plan'])
                : <String, dynamic>{};
            final rawReq = booking['rawRequest'] is Map
                ? Map<String, dynamic>.from(booking['rawRequest'])
                : (booking['request'] is Map
                    ? Map<String, dynamic>.from(booking['request'])
                    : <String, dynamic>{});

            // Enrich plan
            if (rawPlan['venue'] == null && venue != null) rawPlan['venue'] = venue;
            if (rawPlan['planDateTime'] == null && (booking['planDateTime'] != null || booking['eventStartAt'] != null || booking['bookingDate'] != null)) {
              rawPlan['planDateTime'] = booking['planDateTime'] ?? booking['eventStartAt'] ?? booking['bookingDate'];
            }
            if (rawPlan['eventStartAt'] == null && booking['eventStartAt'] != null) {
              rawPlan['eventStartAt'] = booking['eventStartAt'];
            }
            if (rawPlan['depositAmount'] == null && booking['totalAmount'] != null) {
              rawPlan['depositAmount'] = booking['totalAmount'];
            }
            if (rawPlan['id'] == null && (booking['bookingId'] != null || booking['id'] != null)) {
              rawPlan['id'] = booking['bookingId'] ?? booking['id'];
            }
            if (rawPlan['ticketCode'] == null && ticketCode.isNotEmpty) {
              rawPlan['ticketCode'] = ticketCode;
            }
            if (rawPlan['user'] == null && booking['user'] != null) {
              rawPlan['user'] = booking['user'];
            }
            if (rawPlan['host'] == null && (booking['host'] != null || booking['creator'] != null)) {
              rawPlan['host'] = booking['host'] ?? booking['creator'];
            }
            if (rawPlan['creator'] == null && (booking['creator'] != null || booking['host'] != null)) {
              rawPlan['creator'] = booking['creator'] ?? booking['host'];
            }
            if (rawPlan['partner'] == null && (booking['partner'] != null || booking['joiner'] != null)) {
              rawPlan['partner'] = booking['partner'] ?? booking['joiner'];
            }
            if (rawPlan['matchedJoiner'] == null && (booking['matchedJoiner'] != null || booking['joiner'] != null || booking['partner'] != null)) {
              rawPlan['matchedJoiner'] = booking['matchedJoiner'] ?? booking['joiner'] ?? booking['partner'];
            }
            if (rawPlan['joiner'] == null && (booking['joiner'] != null || booking['partner'] != null)) {
              rawPlan['joiner'] = booking['joiner'] ?? booking['partner'];
            }

            // Enrich request
            if (rawReq['venue'] == null && venue != null) rawReq['venue'] = venue;
            if (rawReq['planDateTime'] == null && (booking['planDateTime'] != null || booking['eventStartAt'] != null || booking['bookingDate'] != null)) {
              rawReq['planDateTime'] = booking['planDateTime'] ?? booking['eventStartAt'] ?? booking['bookingDate'];
            }
            if (rawReq['eventStartAt'] == null && booking['eventStartAt'] != null) {
              rawReq['eventStartAt'] = booking['eventStartAt'];
            }
            if (rawReq['paymentAmount'] == null && booking['totalAmount'] != null) {
              rawReq['paymentAmount'] = booking['totalAmount'];
            }
            if (rawReq['depositAmount'] == null && booking['totalAmount'] != null) {
              rawReq['depositAmount'] = booking['totalAmount'];
            }
            if (rawReq['id'] == null && (booking['id'] != null || booking['bookingId'] != null)) {
              rawReq['id'] = booking['id'] ?? booking['bookingId'];
            }
            if (rawReq['planId'] == null && (booking['bookingId'] != null || booking['id'] != null)) {
              rawReq['planId'] = booking['bookingId'] ?? booking['id'];
            }
            if (rawReq['ticketCode'] == null && ticketCode.isNotEmpty) {
              rawReq['ticketCode'] = ticketCode;
            }
            if (rawReq['host'] == null && (booking['host'] != null || booking['creator'] != null)) {
              rawReq['host'] = booking['host'] ?? booking['creator'];
            }
            if (rawReq['creator'] == null && (booking['creator'] != null || booking['host'] != null)) {
              rawReq['creator'] = booking['creator'] ?? booking['host'];
            }
            if (rawReq['requester'] == null && (booking['partner'] != null || booking['joiner'] != null || booking['requester'] != null)) {
              rawReq['requester'] = booking['partner'] ?? booking['joiner'] ?? booking['requester'];
            }
            if (rawReq['joiner'] == null && (booking['joiner'] != null || booking['partner'] != null)) {
              rawReq['joiner'] = booking['joiner'] ?? booking['partner'];
            }
            if (rawReq['partner'] == null && (booking['partner'] != null || booking['joiner'] != null)) {
              rawReq['partner'] = booking['partner'] ?? booking['joiner'];
            }
            if (rawReq['plan'] == null && rawPlan.isNotEmpty) {
              rawReq['plan'] = rawPlan;
            }

            final isHost = booking['isHost'] == true ||
                (booking['creator'] != null && booking['creator']['id']?.toString() == ApiService.currentUserId) ||
                (booking['host'] != null && booking['host']['id']?.toString() == ApiService.currentUserId);

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PartyPlanTicketScreen(
                  request: rawReq.isNotEmpty ? rawReq : (rawPlan.isNotEmpty ? rawPlan : Map<String, dynamic>.from(booking)),
                  plan: rawPlan.isNotEmpty ? rawPlan : Map<String, dynamic>.from(booking),
                  isHost: isHost,
                  isExpired: isExpired,
                  isCancelled: isCancelled,
                ),
              ),
            );
            return;
          }

          // Group party / Large party tickets via LargePartyTicketScreen
          if (category == 'large_party' || category == 'group_party') {
            final bookingMap = Map<String, dynamic>.from(booking);
            if (bookingMap['venue'] == null && venue != null) {
              bookingMap['venue'] = venue;
            }
            if (bookingMap['partyDate'] == null) {
              bookingMap['partyDate'] = booking['partyDate'] ?? booking['bookingDate'] ?? booking['eventStartAt'] ?? booking['eventDateTime'];
            }
            if ((bookingMap['startTime'] == null || bookingMap['startTime'].toString().trim().isEmpty) && startTime.isNotEmpty) {
              bookingMap['startTime'] = startTime;
            }
            if (bookingMap['totalParticipants'] == null && booking['numberOfGuests'] != null) {
              bookingMap['totalParticipants'] = booking['numberOfGuests'];
            }
            if (bookingMap['numberOfFriends'] == null && booking['numberOfGuests'] != null) {
              bookingMap['numberOfFriends'] = booking['numberOfGuests'];
            }
            if (bookingMap['paymentStatus'] == null || bookingMap['paymentStatus'].toString().isEmpty) {
              bookingMap['paymentStatus'] = 'paid';
            }
            if (bookingMap['status'] == null || bookingMap['status'].toString().isEmpty) {
              bookingMap['status'] = isCancelled ? 'cancelled' : (isExpired ? 'expired' : 'confirmed');
            }
            if (bookingMap['ticketCode'] == null && ticketCode.isNotEmpty) {
              bookingMap['ticketCode'] = ticketCode;
            }
            if (booking['bookingId'] != null && bookingMap['bookingId'] == null) {
              bookingMap['bookingId'] = booking['bookingId'];
            }

            final cachedUser = ApiService.cachedCurrentUser;
            if (cachedUser != null) {
              final userMap = bookingMap['user'] is Map ? Map<String, dynamic>.from(bookingMap['user']) : <String, dynamic>{};
              final hostMap = bookingMap['host'] is Map ? Map<String, dynamic>.from(bookingMap['host']) : <String, dynamic>{};
              if ((userMap['profilePhotoUrl'] ?? userMap['profilePhoto']) == null && cachedUser.profilePhoto != null) {
                userMap['profilePhotoUrl'] = cachedUser.profilePhoto;
                userMap['profilePhoto'] = cachedUser.profilePhoto;
                bookingMap['user'] = userMap;
              }
              if ((hostMap['profilePhotoUrl'] ?? hostMap['profilePhoto']) == null && cachedUser.profilePhoto != null) {
                hostMap['profilePhotoUrl'] = cachedUser.profilePhoto;
                hostMap['profilePhoto'] = cachedUser.profilePhoto;
                bookingMap['host'] = hostMap;
              }
            }

            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LargePartyTicketScreen(
                  booking: bookingMap,
                  venue: venue ?? {'name': venueName, 'id': booking['venueId']},
                  isExpired: isExpired,
                  isCancelled: isCancelled,
                ),
              ),
            );
            return;
          }

          // Strangers Meet Ticket Screen
          if (category == 'strangers_meet') {
            try {
              final rawMap = booking['rawRequest'] is Map
                  ? Map<String, dynamic>.from(booking['rawRequest'])
                  : (booking['request'] is Map
                      ? Map<String, dynamic>.from(booking['request'])
                      : Map<String, dynamic>.from(booking));

              if (venue != null && rawMap['venue'] == null) {
                rawMap['venue'] = venue;
              }
              if (rawMap['ticketCode'] == null && ticketCode.isNotEmpty) {
                rawMap['ticketCode'] = ticketCode;
              }
              if (rawMap['ticketId'] == null && ticketCode.isNotEmpty) {
                rawMap['ticketId'] = ticketCode;
              }
              if (booking['startTime'] != null && rawMap['startTime'] == null) {
                rawMap['startTime'] = booking['startTime'];
              }
              if (booking['bookingDate'] != null && rawMap['eventDateTime'] == null) {
                rawMap['eventDateTime'] = booking['bookingDate'];
              }
              if (booking['eventStartAt'] != null && rawMap['eventDateTime'] == null) {
                rawMap['eventDateTime'] = booking['eventStartAt'];
              }
              if (booking['bookingId'] != null) {
                rawMap['bookingId'] = booking['bookingId'];
                rawMap['id'] = booking['bookingId'];
              }
              rawMap['paymentStatus'] = 'paid';
              rawMap['status'] = isCancelled ? 'cancelled' : (isExpired ? 'expired' : 'confirmed');

              final req = StrangersMeetRequest.fromJson(rawMap);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StrangersMeetTicketScreen(
                    request: req,
                    isExpired: isExpired,
                    isCancelled: isCancelled,
                  ),
                ),
              );
              return;
            } catch (e) {
              debugPrint('Failed to launch StrangersMeetTicketScreen: $e');
            }
          }

          // Standard Digital Ticket Screen (Solo / Event / Venue)
          final rawBookingDate = booking['bookingDate']?.toString() ?? booking['eventStartAt']?.toString() ?? bookingDate;
          final rawStartTime = booking['startTime']?.toString() ?? startTime;
          final bookingMap = Map<String, dynamic>.from(booking);
          if (bookingMap['venue'] == null && venue != null) {
            bookingMap['venue'] = venue;
          }
          if (bookingMap['startTime'] == null && rawStartTime.isNotEmpty) {
            bookingMap['startTime'] = rawStartTime;
          }
          if (bookingMap['bookingDate'] == null && rawBookingDate.isNotEmpty) {
            bookingMap['bookingDate'] = rawBookingDate;
          }
          if (bookingMap['ticketCode'] == null && ticketCode.isNotEmpty) {
            bookingMap['ticketCode'] = ticketCode;
          }
          if (bookingMap['totalAmount'] == null && amountPaid > 0) {
            bookingMap['totalAmount'] = amountPaid;
          }

          final cachedUser = ApiService.cachedCurrentUser;
          if (cachedUser != null) {
            final userMap = bookingMap['user'] is Map ? Map<String, dynamic>.from(bookingMap['user']) : <String, dynamic>{};
            final photo = userMap['profilePhotoUrl'] ?? userMap['profilePhoto'] ?? userMap['profileImageUrl'];
            if ((photo == null || photo.toString().trim().isEmpty) && cachedUser.profilePhoto != null) {
              userMap['profilePhotoUrl'] = cachedUser.profilePhoto;
              userMap['profilePhoto'] = cachedUser.profilePhoto;
              userMap['profileImageUrl'] = cachedUser.profilePhoto;
              bookingMap['user'] = userMap;
            }
          }

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DigitalTicketScreen(
                venue: venue ?? {'name': venueName, 'imageUrl': imageUrl},
                date: rawBookingDate,
                time: rawStartTime,
                table: table,
                guests: guests.toString(),
                package: table,
                totalPrice: amountPaid > 0 ? '₹${amountPaid.toStringAsFixed(0)}' : 'FREE',
                ticketId: ticketCode,
                ticketUrl: booking['ticketUrl'] ?? booking['ticket_url'],
                status: isCancelled ? 'CANCELLED' : (isExpired ? 'EXPIRED' : status),
                booking: bookingMap,
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
              color: isCancelled
                  ? const Color(0xFFEF4444).withValues(alpha: 0.25)
                  : categoryColor.withValues(alpha: 0.16),
              width: 1.2,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 145,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(23),
                      ),
                      child: Image.network(
                        cardHeaderImage,
                        fit: BoxFit.cover,
                        cacheWidth: 800,
                        cacheHeight: 350,
                        filterQuality: FilterQuality.low,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[900],
                            child: Center(
                              child: Icon(categoryIcon, size: 36, color: categoryColor.withValues(alpha: 0.4)),
                            ),
                          );
                        },
                      ),
                    ),
                    Container(
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
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Container(
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
                                        Flexible(
                                          child: Text(
                                            categoryName,
                                            style: TextStyle(
                                              color: categoryColor,
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w900,
                                              letterSpacing: 0.8,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isCancelled ? const Color(0xFFEF4444) : Colors.white,
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
                                      color: isCancelled ? Colors.white : statusColor,
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
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
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                if (ticketCode.isNotEmpty) ...[
                                  const SizedBox(width: 8),
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
                              ],
                            ),
                          ),
                          if (isCancelled || status == 'CANCELLED')
                            Positioned(
                              top: 0,
                              right: 0,
                              child: _buildCancelledWatermark(),
                            )
                          else if (status == 'EXPIRED' || tabIndex == 1)
                            Positioned(
                              top: 0,
                              right: 0,
                              child: _buildExpiredWatermark(),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildTicketExpirationCard(booking, tabIndex: tabIndex),
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
                        if (isCancelled)
                          GestureDetector(
                            onTap: () {
                              if (amountPaid > 0) {
                                Navigator.push(context, MaterialPageRoute(builder: (_) => const LunaraWalletScreen()));
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8.5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEF4444).withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFEF4444).withValues(alpha: 0.35),
                                  width: 1,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (amountPaid > 0) ...[
                                    const Icon(Icons.account_balance_wallet_rounded, size: 13, color: Color(0xFFEF4444)),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    amountPaid > 0 ? 'VIEW WALLET' : 'CANCELLED',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 1,
                                      color: Color(0xFFEF4444),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
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
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.grey[400], size: 14),
            const SizedBox(width: 3.5),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 11,
                fontWeight: FontWeight.w900,
              ),
              maxLines: 1,
            ),
          ],
        ),
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

  Widget _buildCancelledWatermark() {
    return IgnorePointer(
      child: Transform.rotate(
        angle: -0.22,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFEF4444).withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFEF4444),
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFEF4444).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Text(
            'CANCELLED',
            style: TextStyle(
              color: Color(0xFFEF4444),
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
