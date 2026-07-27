import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../discovery/digital_ticket_screen.dart';

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
    final tickets = await ApiService.fetchAllUserTickets();
    if (mounted) {
      setState(() {
        _allBookings = tickets;
        _isLoading = false;
      });
    }
  }

  bool _isActiveBooking(Map<String, dynamic> booking) {
    try {
      final status = booking['status']?.toString().toLowerCase();
      if (status == 'cancelled' ||
          status == 'completed' ||
          status == 'no_show' ||
          status == 'expired') {
        return false;
      }
      final dateStr = booking['bookingDate']?.toString();
      if (dateStr == null || dateStr.isEmpty) return true;

      final bookingDate = DateTime.parse(dateStr).toLocal();
      final now = DateTime.now();
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

  String _getVenueImageUrl(Map<String, dynamic>? venue) {
    if (venue == null) return 'https://picsum.photos/seed/venue/600/400';

    String normalize(String path) {
      final clean = path.replaceAll('\\', '/');
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        return clean;
      }
      return '${ApiService.baseUrl}/${clean.startsWith('/') ? clean.substring(1) : clean}';
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
      final img = images[0];
      if (img is Map) {
        final path = img['filePath'] ?? img['url'] ?? img['filePath'];
        if (path != null && path.toString().isNotEmpty) {
          return normalize(path.toString());
        }
      } else if (img is String && img.isNotEmpty) {
        return normalize(img);
      }
    }

    final gallery = venue['gallery'];
    if (gallery is List && gallery.isNotEmpty) {
      final img = gallery[0];
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
    try {
      final date = DateTime.parse(bookingDateStr).toLocal();
      final timeParts = startTimeStr.split(':');
      final hour = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final fullDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      );
      final formattedDate = DateFormat(
        'EEE, MMM d',
      ).format(fullDateTime).toUpperCase();
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

  Widget _buildExpirationTimelineBar(
    Map<String, dynamic> booking,
    bool isActive,
  ) {
    final dateStr = booking['bookingDate']?.toString();
    final startTimeStr = booking['startTime']?.toString() ?? '20:00';

    String timelineText = 'EXPIRED';
    Color timelineColor = Colors.grey;
    double progressRatio = 0.0;

    try {
      if (dateStr != null && dateStr.isNotEmpty) {
        final bDate = DateTime.parse(dateStr).toLocal();
        final parts = startTimeStr.split(':');
        final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 20 : 20;
        final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;

        final eventDateTime = DateTime(
          bDate.year,
          bDate.month,
          bDate.day,
          h,
          m,
        );
        final expirationTime = eventDateTime.add(const Duration(hours: 3));
        final now = DateTime.now();

        if (now.isAfter(expirationTime)) {
          timelineText =
              'EXPIRED ON ${DateFormat('MMM d, h:mm a').format(expirationTime)}';
          timelineColor = Colors.red.shade400;
          progressRatio = 1.0;
        } else if (now.isAfter(eventDateTime)) {
          final remaining = expirationTime.difference(now);
          final hrs = remaining.inHours;
          final mins = remaining.inMinutes % 60;
          timelineText = 'EXPIRES IN ${hrs}h ${mins}m (POST-CHECKIN)';
          timelineColor = Colors.amber.shade800;
          progressRatio = 1.0 - (remaining.inSeconds / (3 * 3600));
        } else {
          final remaining = eventDateTime.difference(now);
          if (remaining.inDays > 0) {
            timelineText =
                'EVENT IN ${remaining.inDays} DAYS (${DateFormat('MMM d').format(eventDateTime)})';
          } else {
            final hrs = remaining.inHours;
            final mins = remaining.inMinutes % 60;
            timelineText = 'STARTS IN ${hrs}h ${mins}m';
          }
          timelineColor = LunaraTheme.electricViolet;
          progressRatio = 0.35;
        }
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: timelineColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: timelineColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.timer_outlined, size: 14, color: timelineColor),
                  const SizedBox(width: 6),
                  Text(
                    'EXPIRATION TIMELINE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: timelineColor,
                    ),
                  ),
                ],
              ),
              Flexible(
                child: Text(
                  timelineText,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: timelineColor,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (isActive) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressRatio.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: timelineColor.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation<Color>(timelineColor),
              ),
            ),
          ],
        ],
      ),
    );
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
                      children: [_buildActiveTickets(), _buildPastTickets()],
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
      if (b is Map) {
        try {
          return _isActiveBooking(Map<String, dynamic>.from(b));
        } catch (_) {
          return false;
        }
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
        final booking = Map<String, dynamic>.from(activeBookings[index] as Map);
        return _buildTicketCard(booking, isActive: true);
      },
    );
  }

  Widget _buildPastTickets() {
    final pastBookings = _allBookings.where((b) {
      if (b is Map) {
        try {
          return !_isActiveBooking(Map<String, dynamic>.from(b));
        } catch (_) {
          return false;
        }
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
        final booking = Map<String, dynamic>.from(pastBookings[index] as Map);
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

  Widget _buildTicketCard(
    Map<String, dynamic> booking, {
    required bool isActive,
  }) {
    final status = _getBookingStatus(booking, isActive);
    final statusColor = switch (status) {
      'CONFIRMED' => LunaraTheme.electricViolet,
      'PENDING' => Colors.amber,
      'USED' => Colors.black,
      'EXPIRED' => Colors.red.shade400,
      _ => Colors.black,
    };

    final venue = booking['venue'] as Map<String, dynamic>?;
    final venueName =
        venue?['name']?.toString() ??
        booking['venueName']?.toString() ??
        'GENERAL VENUE';
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
                ticketId:
                    booking['ticketCode'] ??
                    booking['id']?.toString().substring(0, 8),
                ticketUrl: booking['ticketUrl'] ?? booking['ticket_url'],
              ),
            ),
          );
        },
        child: Container(
          decoration: BoxDecoration(
            gradient: LunaraTheme.cardGradient,
            borderRadius: BorderRadius.circular(24),
            boxShadow: LunaraTheme.premiumCardShadow,
            border: Border.all(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
            ),
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
                            ),
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
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildExpirationTimelineBar(booking, isActive),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _infoChip(Icons.table_bar_outlined, table),
                        _infoChip(Icons.group_outlined, '$guests GUESTS'),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            gradient: isActive
                                ? LunaraTheme.primaryGradient
                                : null,
                            color: isActive ? null : Colors.grey[200],
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Text(
                            'VIEW TICKET',
                            style: TextStyle(
                              fontSize: 10,
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

  Widget _infoChip(IconData icon, String label) {
    return Flexible(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.grey[400], size: 16),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.black,
                fontSize: 12,
                fontWeight: FontWeight.w900,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
