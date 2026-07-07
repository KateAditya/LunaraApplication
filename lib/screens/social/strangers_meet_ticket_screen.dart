import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/theme.dart';
import '../../models/strangers_meet_request.dart';

class StrangersMeetTicketScreen extends StatelessWidget {
  final StrangersMeetRequest request;

  const StrangersMeetTicketScreen({super.key, required this.request});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: LunaraTheme.midnightBlack,
      appBar: AppBar(
        title: const Text('Your Ticket', style: TextStyle(fontWeight: FontWeight.w900)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Success Header
              const Icon(Icons.check_circle_outline_rounded, color: Colors.greenAccent, size: 64),
              const SizedBox(height: 16),
              const Text(
                'Payment Successful!',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your strangers meet event is confirmed.',
                style: TextStyle(color: Colors.grey[400], fontSize: 14),
              ),
              const SizedBox(height: 40),

              // Ticket Card
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [LunaraTheme.electricViolet, Color(0xFF5B21B6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Top Section
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'LUNARA MEET',
                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                                ),
                              ),
                              Text(
                                request.ticketId ?? 'TICKET',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          Text(
                            request.subject,
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900, height: 1.2),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            request.tagline,
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 14),
                          ),
                          const SizedBox(height: 32),
                          
                          // Details Grid
                          Row(
                            children: [
                              Expanded(
                                child: _buildTicketDetail('VENUE', request.venue?['name'] ?? 'Unknown Venue'),
                              ),
                              Expanded(
                                child: _buildTicketDetail('CITY', request.venue?['city'] ?? 'Unknown'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTicketDetail('DATE', DateFormat('MMM dd, yyyy').format(request.eventDateTime)),
                              ),
                              Expanded(
                                child: _buildTicketDetail('TIME', DateFormat('hh:mm a').format(request.eventDateTime)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              Expanded(
                                child: _buildTicketDetail('PERSONS', '${request.numberOfPersons} pax'),
                              ),
                              Expanded(
                                child: _buildTicketDetail('HOST', '${request.user?['firstName'] ?? ''} ${request.user?['lastName'] ?? ''}'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Divider (dashed line)
                    Row(
                      children: [
                        Container(width: 12, height: 24, decoration: const BoxDecoration(color: LunaraTheme.midnightBlack, borderRadius: BorderRadius.horizontal(right: Radius.circular(12)))),
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
                                    width: 5, height: 2,
                                    child: DecoratedBox(decoration: BoxDecoration(color: Colors.white54)),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        Container(width: 12, height: 24, decoration: const BoxDecoration(color: LunaraTheme.midnightBlack, borderRadius: BorderRadius.horizontal(left: Radius.circular(12)))),
                      ],
                    ),

                    // Bottom Section (QR)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
                      ),
                      child: Column(
                        children: [
                          QrImageView(
                            data: request.ticketId ?? request.id,
                            version: QrVersions.auto,
                            size: 160.0,
                            backgroundColor: Colors.white,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Scan at venue to verify',
                            style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              // Action Buttons
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    // Just a placeholder for saving/sharing
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Take a screenshot to save your ticket!')));
                  },
                  icon: const Icon(Icons.download_rounded, color: Colors.white),
                  label: const Text('SAVE TICKET', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Pop back to My Requests
                  Navigator.pop(context);
                },
                child: const Text('BACK TO REQUESTS', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
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
          style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
