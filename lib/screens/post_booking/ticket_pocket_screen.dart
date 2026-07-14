import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../discovery/digital_ticket_screen.dart';
import 'checkin_assist_screen.dart';

class TicketPocketScreen extends StatefulWidget {
  const TicketPocketScreen({super.key});

  @override
  State<TicketPocketScreen> createState() => _TicketPocketScreenState();
}

class _TicketPocketScreenState extends State<TicketPocketScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<dynamic> _allBookings = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadBookings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBookings() async {
    setState(() {
      _isLoading = true;
    });
    final bookings = await ApiService.fetchBookings();
    if (mounted) {
      setState(() {
        _allBookings = bookings ?? [];
        _isLoading = false;
      });
    }
  }

  bool _isActiveBooking(Map<String, dynamic> booking) {
    try {
      final dateStr = booking['bookingDate']?.toString();
      if (dateStr == null) return false;

      final bookingDate = DateTime.parse(dateStr);
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final bookingDateStart = DateTime(bookingDate.year, bookingDate.month, bookingDate.day);

      final status = booking['status']?.toString().toLowerCase();
      if (status == 'cancelled' || status == 'completed' || status == 'no_show') {
        return false;
      }

      return bookingDateStart.isAtSameMomentAs(todayStart) || bookingDateStart.isAfter(todayStart);
    } catch (_) {
      return false;
    }
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

  String _formatBookingDateTime(String bookingDateStr, String startTimeStr) {
    try {
      final date = DateTime.parse(bookingDateStr);
      final timeParts = startTimeStr.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final fullDateTime = DateTime(date.year, date.month, date.day, hour, minute);
      final formattedDate = DateFormat('EEE, MMM d').format(fullDateTime).toUpperCase();
      final formattedTime = DateFormat('h:mm a').format(fullDateTime);
      return '$formattedDate • $formattedTime';
    } catch (_) {
      return '$bookingDateStr • $startTimeStr';
    }
  }

  String _formatTablePackage(String? tablePackage) {
    if (tablePackage == null || tablePackage.toLowerCase() == 'none') {
      return 'GENERAL';
    }
    return tablePackage.toUpperCase();
  }

  String _getBookingStatus(Map<String, dynamic> booking, bool isActive) {
    final status = booking['status']?.toString().toLowerCase();
    if (status == 'cancelled') return 'CANCELLED';
    if (status == 'no_show') return 'NO SHOW';

    if (isActive) {
      if (status == 'pending') return 'PENDING';
      return 'CONFIRMED';
    } else {
      if (status == 'completed') return 'USED';
      return 'EXPIRED';
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
            _buildTabBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: LunaraTheme.electricViolet,
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildActiveTickets(),
                        _buildPastTickets(),
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
      padding: const EdgeInsets.all(20.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const Text(
            'TICKET POCKET',
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

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          gradient: LunaraTheme.cardGradient,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        labelColor: Colors.black,
        unselectedLabelColor: Colors.black,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 2,
        ),
        dividerHeight: 0,
        tabs: const [
          Tab(text: 'ACTIVE'),
          Tab(text: 'PAST'),
        ],
      ),
    );
  }

  Widget _buildActiveTickets() {
    final activeBookings = _allBookings.where((b) {
      if (b is Map<String, dynamic>) {
        return _isActiveBooking(b);
      }
      return false;
    }).toList();

    if (activeBookings.isEmpty) {
      return _buildEmptyState('NO ACTIVE TICKETS FOUND');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: activeBookings.length,
      itemBuilder: (context, index) {
        final booking = activeBookings[index] as Map<String, dynamic>;
        return _buildTicketCard(booking, isActive: true);
      },
    );
  }

  Widget _buildPastTickets() {
    final pastBookings = _allBookings.where((b) {
      if (b is Map<String, dynamic>) {
        return !_isActiveBooking(b);
      }
      return false;
    }).toList();

    if (pastBookings.isEmpty) {
      return _buildEmptyState('NO PAST TICKETS FOUND');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: pastBookings.length,
      itemBuilder: (context, index) {
        final booking = pastBookings[index] as Map<String, dynamic>;
        return _buildTicketCard(booking, isActive: false);
      },
    );
  }

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.confirmation_number_outlined,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            message,
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

  Widget _buildTicketCard(Map<String, dynamic> booking, {required bool isActive}) {
    final status = _getBookingStatus(booking, isActive);
    final statusColor = switch (status) {
      'CONFIRMED' => LunaraTheme.electricViolet,
      'PENDING' => Colors.amber,
      'USED' => Colors.black,
      'EXPIRED' => Colors.red.shade400,
      _ => Colors.black,
    };

    final venue = booking['venue'] as Map<String, dynamic>?;
    final venueName = venue?['name']?.toString() ?? 'GENERAL VENUE';
    final imageUrl = _getVenueImageUrl(venue);
    final bookingDate = booking['bookingDate']?.toString() ?? '';
    final startTime = booking['startTime']?.toString() ?? '';
    final dateStr = _formatBookingDateTime(bookingDate, startTime);
    final table = _formatTablePackage(booking['tablePackage']?.toString());
    final guests = booking['numberOfGuests'] ?? 1;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GestureDetector(
        onTap: () {
          if (isActive) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => CheckInAssistScreen(
                  venueName: venueName,
                  date: dateStr,
                  table: table,
                  guests: guests.toString(),
                  imageUrl: imageUrl,
                  status: status,
                ),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DigitalTicketScreen(
                  venue: venue ?? {'name': venueName, 'imageUrl': imageUrl},
                  date: dateStr,
                  table: table,
                  guests: guests.toString(),
                  package: table,
                  ticketId: booking['ticketCode'] ?? booking['id']?.toString().substring(0, 8),
                ),
              ),
            );
          }
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LunaraTheme.cardGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: LunaraTheme.premiumCardShadow,
            border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
          ),
          child: Column(
            children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  image: DecorationImage(
                    image: NetworkImage(imageUrl),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.8),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            venueName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            dateStr,
                            style: const TextStyle(
                              color: LunaraTheme.electricViolet,
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          boxShadow: [
                            BoxShadow(
                              color: statusColor.withValues(alpha: 0.2),
                              blurRadius: 8,
                            )
                          ],
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _infoChip(Icons.table_bar_outlined, table),
                    _infoChip(Icons.group_outlined, '$guests GUESTS'),
                    if (isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          gradient: LunaraTheme.primaryGradient,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: const Text(
                          'CHECK IN',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: Colors.white,
                          ),
                        ),
                      )
                    else
                      Icon(Icons.chevron_right, color: Colors.grey[300]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoChip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.grey[400], size: 16),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}
