import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../widgets/lunara_profile_image.dart';
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

  void _shareTicket(BuildContext context) {
    final venueName = venue?['name'] ?? 'Unknown Venue';
    final dateStr = date ?? 'SAT, OCT 24';
    final timeStr = time ?? '10:30 PM';
    final ticketIdStr = ticketId ?? 'TICKET';
    final tableStr = table ?? 'VIP V1';
    final guestsStr = guests ?? '1';

    final shareText = 'My Digital Ticket on Lunara is Confirmed! 🥳\n\n'
        'Venue: $venueName\n'
        'Date: $dateStr • $timeStr\n'
        'Table: $tableStr\n'
        'Guests: $guestsStr\n'
        'Ticket ID: $ticketIdStr\n\n'
        'Let\'s vibe together! 💜';

    final box = context.findRenderObject() as RenderBox?;
    Share.share(
      shareText,
      subject: 'My Lunara Ticket',
      sharePositionOrigin: box != null
          ? box.localToGlobal(Offset.zero) & box.size
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LunaraTheme.midnightBlack,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [_buildGlowingTicket(context)],
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
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
          const Text(
            'DIGITAL TICKET',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              letterSpacing: 4,
              color: Colors.white,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: Colors.white, size: 20),
            onPressed: () => _shareTicket(context),
          ),
        ],
      ),
    );
  }

  Widget _buildGlowingTicket(BuildContext context) {
    final String venueName = venue?['name']?.toString() ?? 'ELARA VELVET';
    final String venueCity = venue?['city']?.toString() ?? 'Unknown City';
    final String venueArea = venue?['area']?.toString() ?? '';
    final String venueAddress = venue?['address']?.toString() ?? '${venueArea.isNotEmpty ? "$venueArea, " : ""}$venueCity';
    final images = venue?['images'];
    final String venueImage = (venue?['imageUrl'] ?? (images is List && images.isNotEmpty ? (images.first?['filePath']?.toString() ?? '') : '') ?? 'https://picsum.photos/seed/29/600/400').toString();
    final String cleanVenueImage = venueImage.startsWith('/') ? '${ApiService.baseUrl}$venueImage' : venueImage;

    final String displayDate = date ?? 'SAT, OCT 24';
    final String displayTime = time ?? '10:30 PM';
    final String displayDateTime = '$displayDate • $displayTime';

    final String displayTable = table ?? 'VIP V1';
    final String displayGuests = guests != null ? '$guests GUESTS' : '6 GUESTS';
    final String displayStatus = 'VERIFIED';
    final String finalTicketId = (ticketId ?? 'TICKET').toUpperCase();

    final hostUser = ApiService.cachedCurrentUser;
    final cleanHostName = hostUser != null ? '${hostUser.firstName} ${hostUser.lastName}'.trim() : 'Guest User';
    final hostUsername = hostUser != null ? '@${hostUser.firstName.toLowerCase()}.${hostUser.lastName.toLowerCase()}' : '@guest';

    final double amountPaid = double.tryParse((totalPrice ?? '0').replaceAll(RegExp(r'[^0-9.]'), '')) ?? 199.0;

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: LunaraTheme.cardGradient,
            borderRadius: BorderRadius.circular(32),
            boxShadow: LunaraTheme.premiumCardShadow,
            border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.1)),
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
                          color: LunaraTheme.cyberCyan,
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
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
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          mainAxisSize: MainAxisSize.max,
                          children: List.generate(
                            (constraints.constrainWidth() / 10).floor(),
                            (index) => const SizedBox(
                              width: 5,
                              height: 2,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white30,
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

              // Dynamic Info & Profiles Section (Replacing QR)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Column(
                  children: [
                    // Dual Profile Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        // Host Column
                        Expanded(
                          child: Column(
                            children: [
                              if (hostUser != null)
                                LunaraProfileImage(
                                  user: hostUser,
                                  radius: 32,
                                  showGradientBorder: true,
                                  isInteractive: true,
                                )
                              else
                                CircleAvatar(
                                  radius: 32,
                                  backgroundColor: Colors.white.withValues(alpha: 0.1),
                                  child: const Icon(Icons.person, color: Colors.white70, size: 28),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                cleanHostName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                              Text(
                                hostUsername,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 10,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: LunaraTheme.electricViolet.withValues(alpha: 0.5), width: 1),
                                ),
                                child: const Text(
                                  'TICKET HOLDER',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Link Icon
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.link_rounded,
                            color: LunaraTheme.cyberCyan,
                            size: 18,
                          ),
                        ),
                        // Add Joiner / Share Column
                        Expanded(
                          child: GestureDetector(
                            onTap: () => _shareTicket(context),
                            child: Column(
                              children: [
                                Container(
                                  width: 68,
                                  height: 68,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LunaraTheme.primaryGradient,
                                    boxShadow: [
                                      BoxShadow(
                                        color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.person_add_rounded,
                                      color: Colors.white,
                                      size: 24,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Invite Partner',
                                  style: TextStyle(
                                    color: LunaraTheme.cyberCyan,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const Text(
                                  'Tap to share',
                                  style: TextStyle(
                                    color: Colors.white30,
                                    fontSize: 10,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: LunaraTheme.cyberCyan.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: LunaraTheme.cyberCyan.withValues(alpha: 0.4), width: 1),
                                  ),
                                  child: const Text(
                                    'TAP TO SHARE',
                                    style: TextStyle(
                                      color: LunaraTheme.cyberCyan,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Payment details card
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: LunaraTheme.cyberCyan.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.account_balance_wallet_rounded,
                                  color: LunaraTheme.cyberCyan,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'PAYMENT METHOD',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  SizedBox(height: 2),
                                  Text(
                                    'UPI / Net Banking',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'AMOUNT PAID',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Text(
                                    '₹${amountPaid.toStringAsFixed(0)}',
                                    style: const TextStyle(
                                      color: Colors.greenAccent,
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                    decoration: BoxDecoration(
                                      color: Colors.greenAccent.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'PAID',
                                      style: TextStyle(
                                        color: Colors.greenAccent,
                                        fontSize: 7,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Venue Details Card with map navigation
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  image: DecorationImage(
                                    image: NetworkImage(
                                      cleanVenueImage.isNotEmpty
                                          ? cleanVenueImage
                                          : 'https://picsum.photos/seed/venue/100/100',
                                    ),
                                    fit: BoxFit.cover,
                                  ),
                                  border: Border.all(color: Colors.white24),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      venueName.toUpperCase(),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      venueAddress,
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const Divider(color: Colors.white12, height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 32,
                            child: TextButton.icon(
                              onPressed: () async {
                                final mapUrl = Uri.parse(
                                  'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent("$venueName, $venueAddress")}',
                                );
                                if (await canLaunchUrl(mapUrl)) {
                                  await launchUrl(mapUrl, mode: LaunchMode.externalApplication);
                                }
                              },
                              icon: const Icon(
                                Icons.map_rounded,
                                color: LunaraTheme.cyberCyan,
                                size: 14,
                              ),
                              label: const Text(
                                'VIEW MAP DIRECTIONS',
                                style: TextStyle(
                                  color: LunaraTheme.cyberCyan,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                padding: EdgeInsets.zero,
                                backgroundColor: LunaraTheme.cyberCyan.withValues(alpha: 0.08),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Bottom Ticket Info
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _ticketLabelValue('TABLE', displayTable),
                        _ticketLabelValue('GUESTS', displayGuests),
                        _ticketLabelValue('STATUS', displayStatus),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'ADMIT ONE + FRIENDS • TICKET ID: $finalTicketId',
                      style: TextStyle(
                        color: Colors.grey[500],
                        fontSize: 9,
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
            color: Colors.grey[500],
            fontSize: 9,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
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
                color: Colors.grey[500],
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
