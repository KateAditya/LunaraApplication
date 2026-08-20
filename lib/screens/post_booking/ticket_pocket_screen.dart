import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../discovery/digital_ticket_screen.dart';
import '../social/large_party_ticket_screen.dart';
import '../social/party_plan_ticket_screen.dart';
import '../social/strangers_meet_ticket_screen.dart';
import '../../models/strangers_meet_request.dart';

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

    // Format Expiration String
    final String expiryDateFormatted = expirationTime != null
        ? DateFormat('EEE, MMM d, yyyy • h:mm a').format(expirationTime)
        : (eventStart != null
            ? DateFormat('EEE, MMM d, yyyy • h:mm a').format(eventStart.add(const Duration(hours: 4)))
            : 'END OF EVENT');

    // Status badge label & theme
    String badgeLabel = 'VALID';
    Color themeColor = LunaraTheme.electricViolet;
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
      themeColor = LunaraTheme.electricViolet;
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

    final String totalPriceStr = booking['totalAmount']?.toString() ??
        booking['paymentAmount']?.toString() ??
        '';
    final double amountPaid = double.tryParse(totalPriceStr.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
    final String displayAmount = amountPaid > 0 ? '₹${amountPaid.toStringAsFixed(0)}' : 'FREE';

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GestureDetector(
        onTap: () {
          // Party plan tickets have dedicated matched UI
          final isPartyPlan = booking['isPartyPlan'] == true ||
              booking['type'] == 'party_plan' ||
              booking['bookingType'] == 'party_plan';
          if (isPartyPlan) {
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

          // Group party tickets have richer data via LargePartyTicketScreen
          final isGroupParty = booking['isGroupParty'] == true ||
              booking['isSmallGroupParty'] == true ||
              booking['bookingType'] == 'group_party';
          if (isGroupParty) {
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
          final isStrangersMeet = booking['bookingType'] == 'strangers_meet' ||
              booking['type'] == 'strangers_meet' ||
              booking['isStrangersMeet'] == true;
          if (isStrangersMeet) {
            try {
              final req = StrangersMeetRequest.fromJson(
                  Map<String, dynamic>.from(booking['rawRequest'] ?? booking['plan'] ?? booking));
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => StrangersMeetTicketScreen(request: req),
                ),
              );
              return;
            } catch (_) {}
          }
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
                status: status,
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
                  child: Stack(
                    children: [
                      Align(
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
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildTicketExpirationCard(booking, isActive: isActive),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
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

  Widget _infoChip(IconData icon, String label, {int flex = 1}) {
    return Flexible(
      flex: flex,
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
