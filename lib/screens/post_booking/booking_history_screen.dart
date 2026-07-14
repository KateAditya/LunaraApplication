import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../discovery/digital_ticket_screen.dart';

class BookingHistoryScreen extends StatefulWidget {
  const BookingHistoryScreen({super.key});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  String? _selectedMonth;
  List<dynamic> _allBookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() {
      _isLoading = true;
    });
    final bookings = await ApiService.fetchBookings();
    if (mounted) {
      setState(() {
        _allBookings = bookings ?? [];
        final months = _getAvailableMonths();
        if (months.isNotEmpty) {
          _selectedMonth = months.first;
        }
        _isLoading = false;
      });
    }
  }

  List<String> _getAvailableMonths() {
    if (_allBookings.isEmpty) {
      final now = DateTime.now();
      final currentMonthStr = DateFormat('MMM yyyy').format(now).toUpperCase();
      final prevMonthStr = DateFormat('MMM yyyy').format(DateTime(now.year, now.month - 1)).toUpperCase();
      return [currentMonthStr, prevMonthStr];
    }

    final months = <String>{};
    for (final b in _allBookings) {
      try {
        final dateStr = b['bookingDate']?.toString();
        if (dateStr != null) {
          final dt = DateTime.parse(dateStr);
          final mStr = DateFormat('MMM yyyy').format(dt).toUpperCase();
          months.add(mStr);
        }
      } catch (_) {}
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
    if (_selectedMonth == null) return [];
    return _allBookings.where((b) {
      try {
        final dateStr = b['bookingDate']?.toString();
        if (dateStr == null) return false;
        final dt = DateTime.parse(dateStr);
        final mStr = DateFormat('MMM yyyy').format(dt).toUpperCase();
        return mStr == _selectedMonth;
      } catch (_) {
        return false;
      }
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
        return path.startsWith('http') ? path : '${ApiService.baseUrl}/${path.startsWith('/') ? path.substring(1) : path}';
      }
    }
    final idHash = (venue?['name']?.toString() ?? 'venue').hashCode.abs() % 20;
    return 'https://picsum.photos/seed/$idHash/600/400';
  }

  String _formatBookingDate(String bookingDateStr) {
    try {
      final date = DateTime.parse(bookingDateStr);
      return DateFormat('EEE, MMM d').format(date);
    } catch (_) {
      return bookingDateStr;
    }
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

  @override
  Widget build(BuildContext context) {
    final months = _getAvailableMonths();
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            if (!_isLoading && months.isNotEmpty) _buildMonthSelector(months),
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
      padding: const EdgeInsets.all(20.0),
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

  Widget _buildMonthSelector(List<String> months) {
    final activeMonth = _selectedMonth ?? months.first;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: months.map((month) {
            final isSelected = activeMonth == month;
            return Padding(
              padding: const EdgeInsets.only(right: 12),
              child: GestureDetector(
                onTap: () => setState(() => _selectedMonth = month),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.black : Colors.grey[50],
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isSelected ? Colors.black : Colors.grey[200]!,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : [],
                  ),
                  child: Text(
                    month,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          _summaryCard('NIGHTS OUT', _nightsOut.toString(), LunaraTheme.electricViolet),
          const SizedBox(width: 12),
          _summaryCard('TOTAL SPENT', _totalSpent, Colors.black),
          const SizedBox(width: 12),
          _summaryCard('AVG RATING', _avgRating, Colors.amber[700]!),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          gradient: LunaraTheme.cardGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: LunaraTheme.premiumCardShadow,
          border: Border.all(color: color.withValues(alpha: 0.05)),
        ),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(height: 6),
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 64, color: Colors.grey[300]),
            const SizedBox(height: 16),
            Text(
              'NO BOOKINGS IN THIS PERIOD',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: bookings.length,
      itemBuilder: (context, index) {
        final booking = bookings[index] as Map<String, dynamic>;
        final isLast = index == bookings.length - 1;
        final venue = booking['venue'] as Map<String, dynamic>?;
        final venueName = venue?['name']?.toString() ?? 'GENERAL VENUE';
        final imageUrl = _getVenueImageUrl(venue);
        final bookingDate = booking['bookingDate']?.toString() ?? '';
        final startTime = booking['startTime']?.toString() ?? '';
        final dateStr = _formatBookingDate(bookingDate);
        final timeStr = _formatBookingTime(startTime);
        final table = _formatTablePackage(booking['tablePackage']?.toString());

        final amtVal = double.tryParse(booking['totalAmount']?.toString() ?? '0') ?? 0.0;
        final amountStr = '₹${NumberFormat('#,##,###').format(amtVal.toInt())}';

        final id = booking['id']?.toString() ?? '';
        final rating = (id.hashCode.abs() % 3) + 3; // 3, 4, or 5 stars

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 40,
                child: Column(
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 10),
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: LunaraTheme.electricViolet,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                            blurRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          color: Colors.grey[100],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => DigitalTicketScreen(
                            venue: venue ?? {'name': venueName, 'imageUrl': imageUrl},
                            date: '$dateStr • $timeStr',
                            table: table,
                            guests: (booking['numberOfGuests'] ?? 1).toString(),
                            package: table,
                            ticketId: booking['ticketCode'] ?? booking['id']?.toString().substring(0, 8),
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LunaraTheme.cardGradient,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: LunaraTheme.premiumCardShadow,
                        border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              image: DecorationImage(
                                image: NetworkImage(imageUrl),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  venueName,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$dateStr • $timeStr',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        table,
                                        style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 10,
                                          fontWeight: FontWeight.w900,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      amountStr,
                                      style: const TextStyle(
                                        color: LunaraTheme.electricViolet,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: List.generate(
                                  5,
                                  (i) => Icon(
                                    i < rating
                                        ? Icons.star_rounded
                                        : Icons.star_outline_rounded,
                                    size: 14,
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
}
