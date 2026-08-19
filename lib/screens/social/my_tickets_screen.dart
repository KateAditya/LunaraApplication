import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/lunara_ticket_widget.dart';
import 'large_party_ticket_screen.dart';

class MyTicketsScreen extends StatefulWidget {
  const MyTicketsScreen({super.key});

  @override
  State<MyTicketsScreen> createState() => _MyTicketsScreenState();
}

class _MyTicketsScreenState extends State<MyTicketsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = [
    'Upcoming',
    'Active',
    'Used',
    'Expired',
    'Cancelled',
  ];

  bool _isLoading = true;
  List<Map<String, dynamic>> _tickets = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _fetchTickets();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) {
      _fetchTickets();
    }
  }

  Future<void> _fetchTickets() async {
    setState(() => _isLoading = true);
    final tabName = _tabs[_tabController.index].toLowerCase();
    final data = await ApiService.getUserTickets(tab: tabName);
    if (mounted) {
      setState(() {
        _tickets = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleDownloadPdf(String ticketId) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Generating secure ticket download link...'),
      ),
    );
    final res = await ApiService.getTicketDownloadUrl(ticketId);
    if (res['success'] == true && res['downloadUrl'] != null) {
      final String rawUrl = res['downloadUrl'];
      final fullUrl = ApiService.formatImageUrl(rawUrl) ?? rawUrl;
      final uri = Uri.parse(fullUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open PDF: $fullUrl')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Ticket expired or unavailable.'),
          ),
        );
      }
    }
  }

  Future<void> _handleShareTicket(String ticketId) async {
    final res = await ApiService.createTicketShareToken(ticketId);
    if (res['success'] == true && res['shareText'] != null) {
      final String shareText = res['shareText'];
      await Clipboard.setData(ClipboardData(text: shareText));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ticket share link copied to clipboard! Ready to share on WhatsApp.',
            ),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Failed to generate share link'),
          ),
        );
      }
    }
  }

  void _showTicketDetailsModal(Map<String, dynamic> ticket) {
    final isExpired =
        ticket['isExpired'] == true || ticket['status'] == 'EXPIRED';
    final ticketId = ticket['ticketId'] ?? ticket['id'] ?? 'LUN-TICKET';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: const BoxDecoration(
            color: Color(0xFF0F0C1B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isExpired ? 'EXPIRED TICKET' : 'DIGITAL TICKET',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: LunaraTicketWidget(
                    topSection: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                (ticket['bookingType'] ?? 'DIGITAL TICKET')
                                    .toString()
                                    .toUpperCase()
                                    .replaceAll('_', ' '),
                                style: TextStyle(
                                  color: LunaraTheme.electricViolet,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 12,
                                  letterSpacing: 1.2,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isExpired
                                      ? Colors.red.withValues(alpha: 0.2)
                                      : Colors.green.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isExpired
                                        ? Colors.red
                                        : Colors.green,
                                  ),
                                ),
                                child: Text(
                                  (ticket['status'] ?? 'ACTIVE')
                                      .toString()
                                      .toUpperCase(),
                                  style: TextStyle(
                                    color: isExpired
                                        ? Colors.red
                                        : Colors.green,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Text(
                            ticket['venueName'] ?? 'LUNARA VENUE',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ticket['venueAddress'] ?? '',
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 16,
                                color: Colors.white70,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formatDate(ticket['eventStartAt']),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(
                                Icons.timer_outlined,
                                size: 15,
                                color: isExpired ? Colors.red.shade400 : LunaraTheme.cyberCyan,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isExpired
                                    ? 'Expired: ${_formatDate(ticket['expiresAt'] ?? ticket['eventEndAt'])}'
                                    : 'Valid Until: ${_formatDate(ticket['expiresAt'] ?? ticket['eventEndAt'])}',
                                style: TextStyle(
                                  color: isExpired ? Colors.red.shade300 : LunaraTheme.cyberCyan,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    bottomSection: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          if (isExpired) ...[
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.3),
                                ),
                              ),
                              child: const Column(
                                children: [
                                  Icon(
                                    Icons.info_outline_rounded,
                                    color: Colors.redAccent,
                                    size: 32,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'This ticket has expired',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'The event date has passed. This ticket is retained for your booking history records.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Container(
                              height: 160,
                              width: 160,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: LunaraTheme.electricViolet
                                        .withValues(alpha: 0.3),
                                    blurRadius: 15,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.qr_code_2_rounded,
                                  size: 140,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Ticket ID: $ticketId',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                letterSpacing: 1.0,
                              ),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Present QR code at venue entrance for gate verification',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 11,
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                          if (!isExpired) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () =>
                                        _handleShareTicket(ticketId),
                                    icon: const Icon(
                                      Icons.share_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Share'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white,
                                      side: const BorderSide(
                                        color: Colors.white30,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () =>
                                        _handleDownloadPdf(ticketId),
                                    icon: const Icon(
                                      Icons.download_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Download PDF'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          LunaraTheme.electricViolet,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 12,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
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

  String _formatDate(dynamic dateStr) {
    if (dateStr == null) return 'TBD';
    try {
      final dt = DateTime.parse(dateStr.toString()).toLocal();
      return DateFormat('EEE, dd MMM yyyy • hh:mm a').format(dt);
    } catch (_) {
      return dateStr.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LunaraTheme.midnightBlack,
      appBar: AppBar(
        backgroundColor: LunaraTheme.midnightBlack,
        elevation: 0,
        title: const Text(
          'MY TICKETS',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: LunaraTheme.electricViolet,
          labelColor: LunaraTheme.electricViolet,
          unselectedLabelColor: Colors.white54,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: LunaraTheme.electricViolet,
              ),
            )
          : _tickets.isEmpty
          ? _buildEmptyState()
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _tickets.length,
              itemBuilder: (context, index) {
                final ticket = _tickets[index];
                return _buildTicketCard(ticket);
              },
            ),
    );
  }

  Widget _buildEmptyState() {
    final tabName = _tabs[_tabController.index];
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.confirmation_number_outlined,
              size: 64,
              color: Colors.white.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              'No $tabName Tickets',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your $tabName digital tickets will appear here once bookings are confirmed.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTicketCard(Map<String, dynamic> ticket) {
    final isExpired =
        ticket['isExpired'] == true || ticket['status'] == 'EXPIRED';
    final status = (ticket['status'] ?? 'ACTIVE').toString().toUpperCase();
    final ticketId = ticket['ticketId'] ?? ticket['id'] ?? 'LUN-TICKET';

    Color statusColor;
    if (isExpired) {
      statusColor = Colors.red;
    } else if (status == 'USED') {
      statusColor = Colors.orange;
    } else if (status == 'CANCELLED') {
      statusColor = Colors.redAccent;
    } else {
      statusColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      color: const Color(0xFF161226),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: statusColor.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  ticketId,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    isExpired ? 'EXPIRED' : status,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              ticket['venueName'] ?? 'Lunara Venue',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              ticket['venueAddress'] ?? '',
              style: const TextStyle(color: Colors.white60, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.event_rounded,
                  size: 16,
                  color: LunaraTheme.electricViolet,
                ),
                const SizedBox(width: 6),
                Text(
                  _formatDate(ticket['eventStartAt']),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      final bookingType = (ticket['bookingType'] ?? '').toString().toLowerCase();
                      if (bookingType == 'group_party' || bookingType == 'group_party_small') {
                        // Navigate to dedicated group party ticket screen
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => LargePartyTicketScreen(
                              booking: {
                                'id': ticket['bookingId'],
                                'bookingId': ticket['bookingId'],
                                'bookingDate': ticket['eventStartAt'],
                                'partyDate': ticket['eventStartAt'],
                                'startTime': ticket['startTime'] ?? '08:00 PM',
                                'status': 'confirmed',
                                'paymentStatus': 'paid',
                                'venue': ticket['venue'] ?? {},
                                'venueName': ticket['venueName'],
                                'venueAddress': ticket['venueAddress'],
                                'ticketCode': ticket['ticketId'],
                                'ticketUrl': ticket['pdfUrl'],
                                'numberOfGuests': ticket['numberOfGuests'] ?? '?',
                                // Without this, the ticket screen's initial
                                // (pre-refetch) render defaults totalAmount to
                                // 0 and shows "FREE" even for a paid booking.
                                'totalAmount': ticket['totalAmount'],
                              },
                              venue: ticket['venue'] is Map
                                  ? Map<dynamic, dynamic>.from(ticket['venue'] as Map)
                                  : {},
                            ),
                          ),
                        );
                      } else {
                        _showTicketDetailsModal(ticket);
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.electricViolet,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      isExpired ? 'VIEW BOOKING HISTORY' : 'VIEW TICKET',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
                if (!isExpired) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(
                      Icons.share_rounded,
                      color: Colors.white70,
                    ),
                    onPressed: () => _handleShareTicket(ticketId),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.download_rounded,
                      color: Colors.white70,
                    ),
                    onPressed: () => _handleDownloadPdf(ticketId),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
