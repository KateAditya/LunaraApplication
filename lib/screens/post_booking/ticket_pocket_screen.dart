import 'package:flutter/material.dart';
import '../../core/theme.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
              child: TabBarView(
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
          const SizedBox(width: 48),
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
    final tickets = [
      _TicketData(
        venue: 'ELARA VELVET',
        date: 'SAT, FEB 22 • 10:30 PM',
        table: 'VIP V1',
        guests: 6,
        status: 'CONFIRMED',
        imageUrl: 'https://picsum.photos/seed/11/600/400',
      ),
      _TicketData(
        venue: 'NEON PARADISE',
        date: 'FRI, FEB 28 • 11:00 PM',
        table: 'BOOTH B3',
        guests: 4,
        status: 'PENDING',
        imageUrl: 'https://picsum.photos/seed/12/600/400',
      ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: tickets.length,
      itemBuilder: (context, index) =>
          _buildTicketCard(tickets[index], isActive: true),
    );
  }

  Widget _buildPastTickets() {
    final tickets = [
      _TicketData(
        venue: 'ULTRA CLUB',
        date: 'SAT, FEB 8 • 10:00 PM',
        table: 'TABLE T4',
        guests: 5,
        status: 'USED',
        imageUrl: 'https://picsum.photos/seed/13/600/400',
      ),
      _TicketData(
        venue: 'SKYLINE TERRACE',
        date: 'FRI, JAN 31 • 9:30 PM',
        table: 'VIP V3',
        guests: 8,
        status: 'EXPIRED',
        imageUrl: 'https://picsum.photos/seed/14/600/400',
      ),
    ];

    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: tickets.length,
      itemBuilder: (context, index) =>
          _buildTicketCard(tickets[index], isActive: false),
    );
  }

  Widget _buildTicketCard(_TicketData ticket, {required bool isActive}) {
    final statusColor = switch (ticket.status) {
      'CONFIRMED' => LunaraTheme.electricViolet,
      'PENDING' => Colors.amber,
      'USED' => Colors.black,
      'EXPIRED' => Colors.red.shade400,
      _ => Colors.black,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: GestureDetector(
        onTap: () {
          if (isActive) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CheckInAssistScreen()),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DigitalTicketScreen()),
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
              // Venue image header
              Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(24),
                  ),
                  image: DecorationImage(
                    image: NetworkImage(ticket.imageUrl),
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
                            ticket.venue,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            ticket.date,
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
                          ticket.status,
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
              // Info row
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _infoChip(Icons.table_bar_outlined, ticket.table),
                    _infoChip(Icons.group_outlined, '${ticket.guests} GUESTS'),
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
          style: TextStyle(
            color: Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _TicketData {
  final String venue, date, table, status, imageUrl;
  final int guests;
  const _TicketData({
    required this.venue,
    required this.date,
    required this.table,
    required this.guests,
    required this.status,
    required this.imageUrl,
  });
}
