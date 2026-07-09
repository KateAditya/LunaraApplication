import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme.dart';

class PartyPlanTicketScreen extends StatelessWidget {
  final Map<String, dynamic> request;
  final Map<String, dynamic> plan;
  final bool isHost;

  const PartyPlanTicketScreen({
    super.key,
    required this.request,
    required this.plan,
    required this.isHost,
  });

  @override
  Widget build(BuildContext context) {
    final venue = plan['venue'] ?? {};
    final venueName = venue['name'] ?? 'Unknown Venue';
    final venueCity = venue['city'] ?? 'Unknown City';
    final venueArea = venue['area'] ?? '';
    final planDateTime = plan['planDateTime'] != null
        ? DateTime.tryParse(plan['planDateTime'].toString())?.toLocal() ??
              DateTime.now()
        : DateTime.now();

    final hostUser = plan['user'] ?? plan['host'] ?? {};
    final hostName =
        '${hostUser['firstName'] ?? ''} ${hostUser['lastName'] ?? ''}'.trim();
    final cleanHostName = hostName.isNotEmpty ? hostName : 'Host';

    final joinerUser = request['requester'] ?? {};
    final joinerName =
        '${joinerUser['firstName'] ?? ''} ${joinerUser['lastName'] ?? ''}'
            .trim();
    final cleanJoinerName = joinerName.isNotEmpty ? joinerName : 'Joiner';

    final ticketId = (request['id']?.toString() ?? 'TICKET').toUpperCase();
    final description =
        plan['message'] ?? plan['description'] ?? 'Party Plan Vibe';

    return Scaffold(
      backgroundColor: LunaraTheme.midnightBlack,
      appBar: AppBar(
        title: const Text(
          'PARTY PLAN TICKET',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 2,
            fontSize: 16,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Success Indicator
              const Icon(
                Icons.stars_rounded,
                color: Colors.greenAccent,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Booking Confirmed!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Both deposits are paid. Show this at the venue.',
                style: TextStyle(color: Colors.grey[400], fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // The Ticket Card
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [LunaraTheme.electricViolet, Color(0xFF4C1D95)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Top Info Section
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'LUNARA VIBE',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ),
                              Text(
                                ticketId.length > 12
                                    ? ticketId.substring(0, 12)
                                    : ticketId,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Text(
                            description,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              height: 1.2,
                            ),
                          ),
                          const SizedBox(height: 24),

                          // Details Grid
                          Row(
                            children: [
                              Expanded(
                                child: _buildTicketDetail(
                                  'VENUE',
                                  '$venueName, ${venueArea.isNotEmpty ? "$venueArea, " : ""}$venueCity',
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTicketDetail(
                                  'DATE',
                                  DateFormat(
                                    'MMM dd, yyyy',
                                  ).format(planDateTime),
                                ),
                              ),
                              Expanded(
                                child: _buildTicketDetail(
                                  'TIME',
                                  DateFormat('hh:mm a').format(planDateTime),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTicketDetail(
                                  'HOST',
                                  isHost ? 'You (Host)' : cleanHostName,
                                ),
                              ),
                              Expanded(
                                child: _buildTicketDetail(
                                  'JOINER',
                                  !isHost ? 'You (Joiner)' : cleanJoinerName,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Dashed Divider line
                    Row(
                      children: [
                        Container(
                          width: 12,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: LunaraTheme.midnightBlack,
                            borderRadius: BorderRadius.horizontal(
                              right: Radius.circular(12),
                            ),
                          ),
                        ),
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              return Flex(
                                direction: Axis.horizontal,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                mainAxisSize: MainAxisSize.max,
                                children: List.generate(
                                  (constraints.constrainWidth() / 10).floor(),
                                  (index) => const SizedBox(
                                    width: 5,
                                    height: 2,
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Container(
                          width: 12,
                          height: 24,
                          decoration: const BoxDecoration(
                            color: LunaraTheme.midnightBlack,
                            borderRadius: BorderRadius.horizontal(
                              left: Radius.circular(12),
                            ),
                          ),
                        ),
                      ],
                    ),

                    // QR Code Section
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(24),
                        ),
                      ),
                      child: Column(
                        children: [
                          QrImageView(
                            data: 'PARTYPLAN_TICKET_$ticketId',
                            version: QrVersions.auto,
                            size: 160.0,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Scan at venue entry to check-in',
                            style: TextStyle(
                              color: Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Screenshot Protection Notice
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.2),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.security,
                      color: LunaraTheme.electricViolet,
                      size: 16,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'SCREENSHOT SECURITY ACTIVE',
                      style: TextStyle(
                        color: LunaraTheme.electricViolet,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Action Buttons
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Take a screenshot to save your ticket!'),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                  label: const Text(
                    'SAVE TICKET',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                },
                child: const Text(
                  'CLOSE',
                  style: TextStyle(
                    color: Colors.grey,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTicketDetail(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.6),
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
