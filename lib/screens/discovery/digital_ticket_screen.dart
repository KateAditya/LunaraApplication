import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../services/api_service.dart';

class DigitalTicketScreen extends StatelessWidget {
  final Map<dynamic, dynamic>? venue;
  final String? date;
  final String? package;
  final String? time;
  final String? table;
  final String? guests;
  final String? totalPrice;
  final String? ticketId;

  const DigitalTicketScreen({
    super.key,
    this.venue,
    this.date,
    this.package,
    this.time,
    this.table,
    this.guests,
    this.totalPrice,
    this.ticketId,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [_buildGlowingTicket()],
                    ),
                  ),
                ),
              ),
            ),
            _buildFooter(context),
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
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
          const Text(
            'DIGITAL TICKET',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.black,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.black, size: 20),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildGlowingTicket() {
    final String venueName = venue?['name']?.toString() ?? 'ELARA VELVET';
    final String venueImage = (venue?['imageUrl'] ?? venue?['images']?[0]?['filePath'] ?? 'https://picsum.photos/seed/29/600/400').toString();
    final String cleanVenueImage = venueImage.startsWith('/') ? '${ApiService.baseUrl}$venueImage' : venueImage;

    final String displayDate = date ?? 'SAT, OCT 24';
    final String displayTime = time ?? '10:30 PM';
    final String displayDateTime = '$displayDate • $displayTime';

    final String displayTable = table ?? 'VIP V1';
    final String displayGuests = guests != null ? '$guests GUESTS' : '6 GUESTS';
    final String displayStatus = 'VERIFIED';
    final String finalTicketId = (ticketId ?? 'TICKET').toUpperCase();

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LunaraTheme.cardGradient,
            borderRadius: BorderRadius.circular(32),
            boxShadow: LunaraTheme.premiumCardShadow,
            border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.05)),
          ),
          child: Column(
            children: [
              // Event Banner Section
              Container(
                height: 180,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(32),
                  ),
                  image: DecorationImage(
                    image: NetworkImage(cleanVenueImage),
                    fit: BoxFit.cover,
                  ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(32),
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
                  padding: const EdgeInsets.all(24),
                  alignment: Alignment.bottomLeft,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        venueName.toUpperCase(),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                      ),
                      Text(
                        displayDateTime.toUpperCase(),
                        style: const TextStyle(
                          color: LunaraTheme.electricViolet,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // QR Code Section
              Container(
                padding: const EdgeInsets.all(40),
                color: Colors.white,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    QrImageView(
                      data: 'LUNARA_TICKET_$finalTicketId',
                      version: QrVersions.auto,
                      size: 180.0,
                      backgroundColor: Colors.white,
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.verified,
                          color: LunaraTheme.electricViolet,
                          size: 24,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Bottom Ticket Info
              Container(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ticketLabelValue('TABLE', displayTable),
                        _ticketLabelValue('GUESTS', displayGuests),
                        _ticketLabelValue('STATUS', displayStatus),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'ADMIT ONE + FRIENDS',
                      style: TextStyle(
                        color: Colors.grey[400],
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
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
                'SCREENSHOT PROTECTION ACTIVE',
                style: TextStyle(
                  color: LunaraTheme.electricViolet,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _ticketLabelValue(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey[400],
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          LunaraActionButton(
            text: 'ADD TO APPLE WALLET',
            icon: Icons.add_to_home_screen,
            onPressed: () {
              debugPrint('ADD TO APPLE WALLET clicked');
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.white,
                      ),
                      SizedBox(width: 12),
                      Text('TICKET ADDED TO WALLET'),
                    ],
                  ),
                  backgroundColor: LunaraTheme.electricViolet,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
            child: Text(
              'GO TO DASHBOARD',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
