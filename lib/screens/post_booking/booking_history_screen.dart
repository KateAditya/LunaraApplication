import 'package:flutter/material.dart';
import '../../core/theme.dart';

class BookingHistoryScreen extends StatefulWidget {
  const BookingHistoryScreen({super.key});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  String _selectedMonth = 'FEB 2026';

  final List<_BookingEntry> _bookings = [
    const _BookingEntry(
      venue: 'ELARA VELVET',
      date: 'Sat, Feb 22',
      time: '10:30 PM',
      table: 'VIP V1',
      amount: '₹12,500',
      rating: 5,
      imageUrl: 'https://picsum.photos/seed/16/600/400',
    ),
    const _BookingEntry(
      venue: 'NEON PARADISE',
      date: 'Fri, Feb 14',
      time: '11:00 PM',
      table: 'BOOTH B3',
      amount: '₹8,200',
      rating: 4,
      imageUrl: 'https://picsum.photos/seed/17/600/400',
    ),
    const _BookingEntry(
      venue: 'ULTRA CLUB',
      date: 'Sat, Feb 8',
      time: '10:00 PM',
      table: 'TABLE T4',
      amount: '₹6,800',
      rating: 3,
      imageUrl: 'https://picsum.photos/seed/18/600/400',
    ),
    const _BookingEntry(
      venue: 'SKYLINE TERRACE',
      date: 'Fri, Jan 31',
      time: '9:30 PM',
      table: 'VIP V3',
      amount: '₹15,000',
      rating: 5,
      imageUrl: 'https://picsum.photos/seed/19/600/400',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            _buildMonthSelector(),
            _buildSummaryRow(),
            Expanded(child: _buildTimeline()),
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
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildMonthSelector() {
    final months = ['JAN 2026', 'FEB 2026'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: months.map((month) {
          final isSelected = _selectedMonth == month;
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
    );
  }

  Widget _buildSummaryRow() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Row(
        children: [
          _summaryCard('NIGHTS OUT', '4', LunaraTheme.electricViolet),
          const SizedBox(width: 12),
          _summaryCard('TOTAL SPENT', '₹42.5K', Colors.black),
          const SizedBox(width: 12),
          _summaryCard('AVG RATING', '4.3★', Colors.amber[700]!),
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
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      itemCount: _bookings.length,
      itemBuilder: (context, index) {
        final booking = _bookings[index];
        final isLast = index == _bookings.length - 1;
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Timeline line + dot
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
              // Booking card
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
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
                        // Venue thumbnail
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            image: DecorationImage(
                              image: NetworkImage(booking.imageUrl),
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
                                booking.venue,
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
                                '${booking.date} • ${booking.time}',
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
                                      booking.table,
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
                                    booking.amount,
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
                        // Star rating
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                5,
                                (i) => Icon(
                                  i < booking.rating
                                      ? Icons.star_rounded
                                      : Icons.star_outline_rounded,
                                  size: 14,
                                  color: i < booking.rating
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
            ],
          ),
        );
      },
    );
  }
}

class _BookingEntry {
  final String venue, date, time, table, amount, imageUrl;
  final int rating;
  const _BookingEntry({
    required this.venue,
    required this.date,
    required this.time,
    required this.table,
    required this.amount,
    required this.rating,
    required this.imageUrl,
  });
}
