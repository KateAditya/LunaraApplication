import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/booking_cancellation_dialog.dart';
import '../../widgets/lunara_cached_image.dart';

enum HistoryFilterType {
  all,
  today,
  yesterday,
  thisWeek,
  thisMonth,
  custom,
  month,
}

class BookingHistoryScreen extends StatefulWidget {
  const BookingHistoryScreen({super.key});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  HistoryFilterType _selectedFilter = HistoryFilterType.all;
  String? _selectedMonth;
  DateTimeRange? _customDateRange;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<dynamic> _allBookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookings();
    _initListeners();
  }

  @override
  void dispose() {
    _disposeListeners();
    _searchController.dispose();
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
    final bookings = await ApiService.fetchBookings(forceRefresh: true);
    if (mounted) {
      setState(() {
        _allBookings = bookings ?? [];
        _isLoading = false;
      });
    }
  }

  DateTime? _getBookedDateTime(Map<String, dynamic> booking) {
    final dateStr = booking['bookedAt']?.toString() ??
        booking['createdAt']?.toString() ??
        booking['partyDate']?.toString() ??
        booking['eventDateTime']?.toString() ??
        booking['bookingDate']?.toString();
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr).toLocal();
    } catch (_) {
      return null;
    }
  }

  DateTime? _getEventDateTime(Map<String, dynamic> booking) {
    final dateStr = booking['eventDateTime']?.toString() ??
        booking['bookingDate']?.toString() ??
        booking['partyDate']?.toString() ??
        booking['createdAt']?.toString();
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr).toLocal();
    } catch (_) {
      return null;
    }
  }

  List<String> _getAvailableBookedMonths() {
    final months = <String>{};
    for (final b in _allBookings) {
      if (b is! Map<String, dynamic>) continue;
      final dt = _getBookedDateTime(b);
      if (dt != null) {
        final mStr = DateFormat('MMM yyyy').format(dt).toUpperCase();
        months.add(mStr);
      }
    }

    final sorted = months.toList();
    sorted.sort((a, b) {
      try {
        final dateA = DateFormat('MMM yyyy').parse(a);
        final dateB = DateFormat('MMM yyyy').parse(b);
        return dateB.compareTo(dateA);
      } catch (_) {
        return 0;
      }
    });
    return sorted;
  }

  List<dynamic> get _filteredBookings {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart.add(const Duration(days: 1));
    final yesterdayStart = todayStart.subtract(const Duration(days: 1));
    final yesterdayEnd = todayStart;

    // Week start (Monday)
    final weekStart = todayStart.subtract(Duration(days: todayStart.weekday - 1));
    final weekEnd = weekStart.add(const Duration(days: 7));

    // Month start
    final monthStart = DateTime(now.year, now.month, 1);
    final nextMonthStart = DateTime(now.year, now.month + 1, 1);

    return _allBookings.where((b) {
      if (b is! Map<String, dynamic>) return false;
      final bookedDt = _getBookedDateTime(b);
      if (bookedDt == null) return false;

      // 1. Date Filter (based on BOOKED DATE)
      bool matchesDate = false;
      switch (_selectedFilter) {
        case HistoryFilterType.all:
          matchesDate = true;
          break;
        case HistoryFilterType.today:
          matchesDate = bookedDt.isAfter(todayStart.subtract(const Duration(milliseconds: 1))) &&
              bookedDt.isBefore(todayEnd);
          break;
        case HistoryFilterType.yesterday:
          matchesDate = bookedDt.isAfter(yesterdayStart.subtract(const Duration(milliseconds: 1))) &&
              bookedDt.isBefore(yesterdayEnd);
          break;
        case HistoryFilterType.thisWeek:
          matchesDate = bookedDt.isAfter(weekStart.subtract(const Duration(milliseconds: 1))) &&
              bookedDt.isBefore(weekEnd);
          break;
        case HistoryFilterType.thisMonth:
          matchesDate = bookedDt.isAfter(monthStart.subtract(const Duration(milliseconds: 1))) &&
              bookedDt.isBefore(nextMonthStart);
          break;
        case HistoryFilterType.custom:
          if (_customDateRange != null) {
            final rangeStart = DateTime(
              _customDateRange!.start.year,
              _customDateRange!.start.month,
              _customDateRange!.start.day,
            );
            final rangeEnd = DateTime(
              _customDateRange!.end.year,
              _customDateRange!.end.month,
              _customDateRange!.end.day,
            ).add(const Duration(days: 1));
            matchesDate = bookedDt.isAfter(rangeStart.subtract(const Duration(milliseconds: 1))) &&
                bookedDt.isBefore(rangeEnd);
          } else {
            matchesDate = true;
          }
          break;
        case HistoryFilterType.month:
          if (_selectedMonth != null) {
            final mStr = DateFormat('MMM yyyy').format(bookedDt).toUpperCase();
            matchesDate = mStr == _selectedMonth;
          } else {
            matchesDate = true;
          }
          break;
      }

      if (!matchesDate) return false;

      // 2. Search Query Filter
      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.trim().toLowerCase();
        final venue = b['venue'] as Map<String, dynamic>?;
        final venueName = (venue?['name']?.toString() ?? '').toLowerCase();
        final area = (venue?['area']?.toString() ?? '').toLowerCase();
        final city = (venue?['city']?.toString() ?? '').toLowerCase();
        final tablePackage = (b['tablePackage']?.toString() ?? '').toLowerCase();
        final bookingNumber = (b['bookingNumber']?.toString() ?? b['id']?.toString() ?? '').toLowerCase();
        final ticketCode = (b['ticketCode']?.toString() ?? '').toLowerCase();
        final amount = (b['totalAmount']?.toString() ?? '').toLowerCase();
        final status = (b['status']?.toString() ?? '').toLowerCase();

        final matchesSearch = venueName.contains(query) ||
            area.contains(query) ||
            city.contains(query) ||
            tablePackage.contains(query) ||
            bookingNumber.contains(query) ||
            ticketCode.contains(query) ||
            amount.contains(query) ||
            status.contains(query);

        if (!matchesSearch) return false;
      }

      return true;
    }).toList();
  }

  int get _nightsOut {
    return _filteredBookings.where((b) {
      final status = b['status']?.toString().toLowerCase();
      return status != 'cancelled';
    }).length;
  }

  String get _totalSpent {
    double total = 0;
    for (final b in _filteredBookings) {
      final status = b['status']?.toString().toLowerCase();
      if (status != 'cancelled') {
        final amt = double.tryParse(b['totalAmount']?.toString() ?? '0') ?? 0.0;
        total += amt;
      }
    }

    if (total >= 1000) {
      return '₹${(total / 1000).toStringAsFixed(1)}K';
    }
    return '₹${total.toInt()}';
  }

  String get _avgRating {
    final validBookings = _filteredBookings.where((b) {
      final status = b['status']?.toString().toLowerCase();
      return status != 'cancelled';
    }).toList();

    if (validBookings.isEmpty) return '0.0★';
    double totalStars = 0;
    for (final b in validBookings) {
      final id = b['id']?.toString() ?? '';
      final rating = (id.hashCode.abs() % 3) + 3; // 3, 4, or 5 stars
      totalStars += rating;
    }
    return '${(totalStars / validBookings.length).toStringAsFixed(1)}★';
  }

  String _getVenueImageUrl(Map<String, dynamic>? venue) {
    if (venue != null && venue['images'] != null && (venue['images'] as List).isNotEmpty) {
      final img = venue['images'][0];
      if (img is Map && img['filePath'] != null) {
        final path = img['filePath'].toString().replaceAll('\\', '/');
        return path.startsWith('http')
            ? path
            : '${ApiService.baseUrl}/${path.startsWith('/') ? path.substring(1) : path}';
      }
    }
    final idHash = (venue?['name']?.toString() ?? 'venue').hashCode.abs() % 20;
    return 'https://picsum.photos/seed/$idHash/600/400';
  }

  String _formatBookedTimestamp(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final itemDate = DateTime(dt.year, dt.month, dt.day);
    final timeStr = DateFormat('h:mm a').format(dt);

    if (itemDate == today) {
      return 'Booked Today • $timeStr';
    } else if (itemDate == today.subtract(const Duration(days: 1))) {
      return 'Booked Yesterday • $timeStr';
    } else {
      return 'Booked ${DateFormat('MMM dd, yyyy').format(dt)} • $timeStr';
    }
  }

  String _formatEventDate(DateTime dt) {
    return DateFormat('EEE, MMM d, yyyy').format(dt);
  }

  String _formatBookingTime(String startTimeStr) {
    try {
      final parts = startTimeStr.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      final dt = DateTime(2026, 1, 1, hour, minute);
      return DateFormat('h:mm a').format(dt);
    } catch (_) {
      return startTimeStr;
    }
  }

  String _formatTablePackage(String? tablePackage) {
    if (tablePackage == null || tablePackage.toLowerCase() == 'none') {
      return 'GENERAL';
    }
    return tablePackage.toUpperCase();
  }

  Future<void> _selectCustomDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2),
      initialDateRange: _customDateRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 7)),
            end: now,
          ),
      builder: (context, child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light(
              primary: LunaraTheme.electricViolet,
              onPrimary: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _customDateRange = picked;
        _selectedFilter = HistoryFilterType.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildSearchBar(),
            _buildFilterPills(),
            if (!_isLoading) _buildSummaryRow(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: LunaraTheme.electricViolet,
                      ),
                    )
                  : _buildTimeline(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'YOUR NIGHTS',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black),
            onPressed: _loadBookings,
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: Colors.grey[50],
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey[200]!),
        ),
        child: TextField(
          controller: _searchController,
          onChanged: (val) {
            setState(() {
              _searchQuery = val;
            });
          },
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.black,
          ),
          decoration: InputDecoration(
            hintText: 'Search by venue, package, ticket or city...',
            hintStyle: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey[400],
            ),
            prefixIcon: Icon(Icons.search_rounded, size: 20, color: Colors.grey[500]),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _searchQuery = '';
                      });
                    },
                  )
                : null,
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ),
    );
  }

  Widget _buildFilterPills() {
    final availableMonths = _getAvailableBookedMonths();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: SizedBox(
        height: 40,
        child: ListView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          children: [
            _buildPill(
              label: 'ALL',
              isSelected: _selectedFilter == HistoryFilterType.all,
              onTap: () {
                setState(() {
                  _selectedFilter = HistoryFilterType.all;
                  _selectedMonth = null;
                });
              },
            ),
            _buildPill(
              label: 'TODAY',
              isSelected: _selectedFilter == HistoryFilterType.today,
              onTap: () {
                setState(() {
                  _selectedFilter = HistoryFilterType.today;
                  _selectedMonth = null;
                });
              },
            ),
            _buildPill(
              label: 'YESTERDAY',
              isSelected: _selectedFilter == HistoryFilterType.yesterday,
              onTap: () {
                setState(() {
                  _selectedFilter = HistoryFilterType.yesterday;
                  _selectedMonth = null;
                });
              },
            ),
            _buildPill(
              label: 'THIS WEEK',
              isSelected: _selectedFilter == HistoryFilterType.thisWeek,
              onTap: () {
                setState(() {
                  _selectedFilter = HistoryFilterType.thisWeek;
                  _selectedMonth = null;
                });
              },
            ),
            _buildPill(
              label: 'THIS MONTH',
              isSelected: _selectedFilter == HistoryFilterType.thisMonth,
              onTap: () {
                setState(() {
                  _selectedFilter = HistoryFilterType.thisMonth;
                  _selectedMonth = null;
                });
              },
            ),
            _buildPill(
              label: _customDateRange == null
                  ? '📅 CUSTOM'
                  : '📅 ${DateFormat('MMM d').format(_customDateRange!.start)} - ${DateFormat('MMM d').format(_customDateRange!.end)}',
              isSelected: _selectedFilter == HistoryFilterType.custom,
              onTap: _selectCustomDateRange,
            ),
            ...availableMonths.map((m) {
              final isSelected = _selectedFilter == HistoryFilterType.month && _selectedMonth == m;
              return _buildPill(
                label: m,
                isSelected: isSelected,
                onTap: () {
                  setState(() {
                    _selectedFilter = HistoryFilterType.month;
                    _selectedMonth = m;
                  });
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPill({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.grey[50],
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.black : Colors.grey[200]!,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontSize: 11,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      child: Row(
        children: [
          _summaryCard('NIGHTS OUT', _nightsOut.toString(), LunaraTheme.electricViolet),
          const SizedBox(width: 10),
          _summaryCard('TOTAL SPENT', _totalSpent, Colors.black),
          const SizedBox(width: 10),
          _summaryCard('AVG RATING', _avgRating, Colors.amber[700]!),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LunaraTheme.cardGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: LunaraTheme.premiumCardShadow,
          border: Border.all(color: color.withValues(alpha: 0.06)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 9,
                fontWeight: FontWeight.w900,
                letterSpacing: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    final bookings = _filteredBookings;
    if (bookings.isEmpty) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: LunaraTheme.electricViolet.withValues(alpha: 0.06),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.history_toggle_off_rounded,
                  size: 48,
                  color: LunaraTheme.electricViolet.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'NO BOOKINGS FOUND',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _searchQuery.isNotEmpty
                    ? 'No bookings matched "$_searchQuery" in this date range.'
                    : 'No bookings booked in this time period.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey[500],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 20),
              if (_selectedFilter != HistoryFilterType.all || _searchQuery.isNotEmpty)
                TextButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedFilter = HistoryFilterType.all;
                      _selectedMonth = null;
                      _customDateRange = null;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 16, color: LunaraTheme.electricViolet),
                  label: const Text(
                    'RESET FILTERS',
                    style: TextStyle(
                      color: LunaraTheme.electricViolet,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      physics: const BouncingScrollPhysics(),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        final booking = bookings[index] as Map<String, dynamic>;
        final isLast = index == bookings.length - 1;
        final venue = booking['venue'] as Map<String, dynamic>?;
        final venueName = venue?['name']?.toString() ?? 'VENUE';
        final imageUrl = _getVenueImageUrl(venue);

        final bookedDt = _getBookedDateTime(booking);
        final eventDt = _getEventDateTime(booking);

        final bookedStr = bookedDt != null ? _formatBookedTimestamp(bookedDt) : 'Booked recently';
        final startTime = booking['startTime']?.toString() ?? '';
        final eventDateStr = eventDt != null ? _formatEventDate(eventDt) : 'Event Date';
        final timeStr = _formatBookingTime(startTime);

        final isSolo = booking['isSolo'] == true || booking['goingMode'] == 'solo' || booking['category'] == 'solo' || booking['bookingType'] == 'solo';
        final isStrangersMeet = !isSolo && (booking['isStrangersMeet'] == true || booking['bookingType'] == 'strangers_meet' || booking['type'] == 'strangers_meet');
        final isPartyPlan = !isSolo && (booking['isPartyPlan'] == true ||
            booking['category'] == 'party_plan' ||
            booking['bookingType'] == 'party_plan' ||
            booking['type'] == 'party_plan' ||
            booking['goingMode'] == 'plan' ||
            (booking['ticketCode'] ?? booking['ticketId'])?.toString().toUpperCase().startsWith('PP-') == true ||
            booking['plan'] != null ||
            booking['partyPlanId'] != null ||
            booking['planId'] != null);
        final isGroupParty = !isSolo && (booking['isGroupParty'] == true || booking['bookingType'] == 'group_party');
        final bool isEventTicketH = !isSolo && (booking['isUpcomingNight'] == true ||
            booking['isEventBooking'] == true ||
            booking['bookingType'] == 'upcoming_night' ||
            booking['bookingType'] == 'event_booking');

        final eventTitle = booking['subject']?.toString().trim().isNotEmpty == true
            ? booking['subject'].toString()
            : (booking['eventTitle']?.toString().trim().isNotEmpty == true
                ? booking['eventTitle'].toString()
                : (booking['partySubject']?.toString().trim().isNotEmpty == true
                    ? booking['partySubject'].toString()
                    : null));
        final displayTitle = (isStrangersMeet || isPartyPlan || isEventTicketH) && eventTitle != null
            ? eventTitle
            : venueName;
        final displaySubtitle = (displayTitle != venueName)
            ? '$venueName • $eventDateStr • $timeStr'
            : 'Event: $eventDateStr • $timeStr';

        final table = isStrangersMeet
            ? 'STRANGER MEET'
            : (isPartyPlan ? 'PARTY PLAN' : _formatTablePackage(booking['tablePackage']?.toString()));

        final amtRaw = booking['totalAmount'] ?? booking['paymentAmount'] ?? booking['chargesPerHead'] ?? booking['charges'];
        final amtVal = double.tryParse(amtRaw?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0.0;
        final amountStr = amtVal <= 0
            ? 'FREE'
            : '₹${NumberFormat('#,##,###').format(amtVal.toInt())}';

        final id = booking['id']?.toString() ?? '';
        final rating = (id.hashCode.abs() % 3) + 3; // 3, 4, or 5 stars
        final rawStatus = booking['status']?.toString().toUpperCase() ?? 'CONFIRMED';
        final isCancelled = rawStatus.contains('CANCEL');
        final bool isExpired = !isCancelled && (rawStatus == 'EXPIRED' || (eventDt != null && eventDt.isBefore(DateTime.now())));
        final displayStatus = isCancelled ? 'CANCELLED' : (isExpired ? 'EXPIRED' : rawStatus);

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 36,
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: isCancelled || isExpired ? Colors.grey : LunaraTheme.electricViolet,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (isCancelled || isExpired ? Colors.grey : LunaraTheme.electricViolet)
                                .withValues(alpha: 0.35),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.grey[200],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 20),
                  child: GestureDetector(
                    onTap: () => _showBookingDetailsModal(booking),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LunaraTheme.cardGradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: LunaraTheme.premiumCardShadow,
                        border: Border.all(
                          color: LunaraTheme.electricViolet.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top info: Booked Timestamp & Status chip
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  bookedStr,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey[600],
                                    letterSpacing: 0.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if ((isSolo || (isGroupParty && booking['isLargePartyRequest'] != true)) && !isCancelled && !isExpired && rawStatus != 'COMPLETED') ...[
                                    GestureDetector(
                                      onTap: () {
                                        final bId = booking['id']?.toString() ?? booking['bookingId']?.toString();
                                        if (bId != null) {
                                          BookingCancellationDialog.show(
                                            context,
                                            bookingId: bId,
                                            isGroupParty: isGroupParty,
                                            initialVenueName: venueName,
                                            initialDate: eventDateStr,
                                            initialTime: timeStr,
                                            initialAmountPaid: amtVal,
                                            onCancelled: _loadBookings,
                                          );
                                        }
                                      },
                                      child: Container(
                                        margin: const EdgeInsets.only(right: 6),
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: Colors.red.withValues(alpha: 0.08),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.25)),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.cancel_outlined, size: 10, color: Colors.redAccent),
                                            SizedBox(width: 3),
                                            Text(
                                              'CANCEL',
                                              style: TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 8.5,
                                                fontWeight: FontWeight.w900,
                                                letterSpacing: 0.5,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isCancelled
                                          ? const Color(0xFFEF4444).withValues(alpha: 0.1)
                                          : (isExpired
                                              ? Colors.red.withValues(alpha: 0.1)
                                              : LunaraTheme.electricViolet.withValues(alpha: 0.1)),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: isCancelled
                                            ? const Color(0xFFEF4444).withValues(alpha: 0.3)
                                            : (isExpired
                                                ? Colors.red.withValues(alpha: 0.3)
                                                : LunaraTheme.electricViolet.withValues(alpha: 0.3)),
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Text(
                                      displayStatus,
                                      style: TextStyle(
                                        color: isCancelled
                                            ? const Color(0xFFEF4444)
                                            : (isExpired ? Colors.red.shade600 : LunaraTheme.electricViolet),
                                        fontSize: 9,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Divider(height: 1, color: Colors.grey[100]),
                          const SizedBox(height: 10),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  image: DecorationImage(
                                    image: NetworkImage(imageUrl),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      displayTitle,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      displaySubtitle,
                                      style: const TextStyle(
                                        color: Colors.black87,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 5),
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            table,
                                            style: const TextStyle(
                                              color: Colors.black54,
                                              fontSize: 10,
                                              fontWeight: FontWeight.w900,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          amountStr,
                                          style: const TextStyle(
                                            color: LunaraTheme.electricViolet,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  5,
                                  (i) => Icon(
                                    i < rating
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    size: 11,
                                    color: i < rating
                                        ? LunaraTheme.electricViolet
                                        : Colors.grey[200],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showBookingDetailsModal(Map<String, dynamic> booking) {
    final venue = booking['venue'] as Map<String, dynamic>?;
    final venueName = venue?['name']?.toString() ?? booking['venueName']?.toString() ?? 'VENUE';
    final venueCity = venue?['city']?.toString() ?? '';
    final venueArea = venue?['area']?.toString() ?? '';
    final venueAddress = venue?['address']?.toString() ??
        venue?['addressLine1']?.toString() ??
        '${venueArea.isNotEmpty ? "$venueArea, " : ""}$venueCity';
    final imageUrl = _getVenueImageUrl(venue);

    final bookedDt = _getBookedDateTime(booking);
    final eventDt = _getEventDateTime(booking);

    final bookedStr = bookedDt != null ? _formatBookedTimestamp(bookedDt) : 'Booked recently';
    final startTime = booking['startTime']?.toString() ?? '';
    final eventDateStr = eventDt != null ? _formatEventDate(eventDt) : 'Event Date';
    final timeStr = _formatBookingTime(startTime);

    final isSolo = booking['isSolo'] == true || booking['goingMode'] == 'solo' || booking['category'] == 'solo' || booking['bookingType'] == 'solo';
    final isStrangersMeet = !isSolo && (booking['isStrangersMeet'] == true || booking['bookingType'] == 'strangers_meet' || booking['type'] == 'strangers_meet');
    final isPartyPlan = !isSolo && (booking['isPartyPlan'] == true ||
        booking['category'] == 'party_plan' ||
        booking['bookingType'] == 'party_plan' ||
        booking['type'] == 'party_plan' ||
        booking['goingMode'] == 'plan' ||
        (booking['ticketCode'] ?? booking['ticketId'])?.toString().toUpperCase().startsWith('PP-') == true ||
        booking['plan'] != null ||
        booking['partyPlanId'] != null ||
        booking['planId'] != null);
    final isGroupParty = !isSolo && (booking['isGroupParty'] == true || booking['bookingType'] == 'group_party');
    final bool isEventTicketH = !isSolo && (booking['isUpcomingNight'] == true ||
        booking['isEventBooking'] == true ||
        booking['bookingType'] == 'upcoming_night' ||
        booking['bookingType'] == 'event_booking');

    final eventTitle = booking['subject']?.toString().trim().isNotEmpty == true
        ? booking['subject'].toString()
        : (booking['eventTitle']?.toString().trim().isNotEmpty == true
            ? booking['eventTitle'].toString()
            : (booking['partySubject']?.toString().trim().isNotEmpty == true
                ? booking['partySubject'].toString()
                : null));
    final displayTitle = (isStrangersMeet || isPartyPlan || isEventTicketH) && eventTitle != null
        ? eventTitle
        : venueName;

    final bookingCategory = isStrangersMeet
        ? 'STRANGERS MEET'
        : (isPartyPlan
            ? 'PARTY PLAN'
            : (isGroupParty
                ? 'GROUP PARTY'
                : (isEventTicketH ? 'EVENT NIGHT' : 'VENUE BOOKING')));

    final table = isStrangersMeet
        ? 'STRANGER MEET'
        : (isPartyPlan ? 'PARTY PLAN' : _formatTablePackage(booking['tablePackage']?.toString()));

    final amtRaw = booking['totalAmount'] ?? booking['paymentAmount'] ?? booking['chargesPerHead'] ?? booking['charges'];
    final amtVal = double.tryParse(amtRaw?.toString().replaceAll(RegExp(r'[^0-9.]'), '') ?? '0') ?? 0.0;
    final amountStr = amtVal <= 0
        ? 'FREE'
        : '₹${NumberFormat('#,##,###').format(amtVal.toInt())}';

    final ticketCode = (booking['ticketCode'] ??
        booking['ticketId'] ??
        booking['bookingId'] ??
        (booking['id'] != null ? booking['id'].toString().substring(0, 8).toUpperCase() : 'TICKET')).toString().toUpperCase();

    final rawStatus = booking['status']?.toString().toUpperCase() ?? 'CONFIRMED';
    final isCancelled = rawStatus.contains('CANCEL');
    final bool isExpired = !isCancelled && (rawStatus == 'EXPIRED' || (eventDt != null && eventDt.isBefore(DateTime.now())));
    final displayStatus = isCancelled ? 'CANCELLED' : (isExpired ? 'EXPIRED' : rawStatus);

    final statusColor = isCancelled
        ? const Color(0xFFEF4444)
        : (isExpired ? Colors.red.shade600 : LunaraTheme.electricViolet);

    final guests = booking['numberOfGuests'] ?? (isStrangersMeet ? 2 : (isPartyPlan ? 2 : 1));

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle Bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header Row
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'BOOKING DETAILS',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: statusColor.withValues(alpha: 0.4), width: 1),
                  ),
                  child: Text(
                    displayStatus,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Venue / Event Card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: LunaraCachedImage(
                      imageUrl,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Container(
                        width: 56,
                        height: 56,
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.nightlife_rounded, color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayTitle,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (venueAddress.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            venueAddress,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 4),
                        Text(
                          bookingCategory,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: Color(0xFF7C3AED),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Details Grid
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  _buildDetailRow(
                    label: 'Booking ID',
                    value: ticketCode,
                    valueColor: const Color(0xFF7C3AED),
                    isMonospace: true,
                  ),
                  const Divider(height: 16, thickness: 0.5, color: Color(0xFFE2E8F0)),
                  _buildDetailRow(
                    label: 'Event Date & Time',
                    value: '$eventDateStr • $timeStr',
                  ),
                  const Divider(height: 16, thickness: 0.5, color: Color(0xFFE2E8F0)),
                  _buildDetailRow(
                    label: 'Booked On',
                    value: bookedStr,
                  ),
                  const Divider(height: 16, thickness: 0.5, color: Color(0xFFE2E8F0)),
                  _buildDetailRow(
                    label: 'Table / Package',
                    value: table,
                  ),
                  const Divider(height: 16, thickness: 0.5, color: Color(0xFFE2E8F0)),
                  _buildDetailRow(
                    label: 'Guests',
                    value: '$guests Guests',
                  ),
                  const Divider(height: 16, thickness: 0.5, color: Color(0xFFE2E8F0)),
                  _buildDetailRow(
                    label: 'Total Amount',
                    value: amountStr,
                    valueColor: Colors.black,
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Status Note
            if (isCancelled)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This booking was cancelled.',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (isExpired)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.event_busy_rounded, color: Color(0xFFDC2626), size: 16),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'This event has concluded. Preserved in your history records.',
                        style: TextStyle(
                          color: Color(0xFFDC2626),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 16),

            // Close Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFF1F5F9),
                  side: BorderSide.none,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'CLOSE',
                  style: TextStyle(
                    color: Color(0xFF475569),
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow({
    required String label,
    required String value,
    Color? valueColor,
    bool isBold = false,
    bool isMonospace = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: valueColor ?? const Color(0xFF0F172A),
              fontSize: 12.5,
              fontWeight: isBold ? FontWeight.w900 : FontWeight.w700,
              fontFamily: isMonospace ? 'monospace' : null,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
