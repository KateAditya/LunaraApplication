import 'dart:math';
import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../widgets/glass_card.dart';
import '../../widgets/action_button.dart';

class GuestlistScreen extends StatefulWidget {
  final Map<String, dynamic> venue;

  const GuestlistScreen({super.key, required this.venue});

  @override
  State<GuestlistScreen> createState() => _GuestlistScreenState();
}

class _GuestlistScreenState extends State<GuestlistScreen> {
  int _guestCount = 1;
  final double _pricePerGuest = 499.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: LunaraTheme.midnightBlack),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      _buildVIPHeader(),
                      const SizedBox(height: 40),
                      _buildInfoCard(),
                      const SizedBox(height: 32),
                      _buildGuestCounter(),
                      const SizedBox(height: 32),
                      _buildPriceSummary(),
                      const SizedBox(height: 32),
                      _buildTerms(),
                    ],
                  ),
                ),
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const Spacer(),
          Text(
            'GUESTLIST',
            style: LunaraTheme.headingStyle.copyWith(
              fontSize: 18,
              letterSpacing: 4,
            ),
          ),
          const Spacer(),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildVIPHeader() {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.amber, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.3),
                blurRadius: 20,
              ),
            ],
          ),
          child: const Icon(Icons.star, color: Colors.amber, size: 40),
        ),
        const SizedBox(height: 24),
        Text(
          'VIP ACCESS REQUEST',
          style: LunaraTheme.headingStyle.copyWith(fontSize: 24),
        ),
        const SizedBox(height: 8),
        Text(
          'FOR ${widget.venue['name'] ?? 'THE VENUE'}',
          style: const TextStyle(
            color: Colors.white54,
            letterSpacing: 2,
            fontSize: 12,
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard() {
    return GlassCard(
      padding: const EdgeInsets.all(24),
      borderRadius: BorderRadius.circular(24),
      borderColor: Colors.amber.withValues(alpha: 0.3),
      child: Column(
        children: [
          _infoRow(Icons.calendar_today, 'DATE', 'TONIGHT, OCT 24'),
          const Divider(color: Colors.white10, height: 32),
          _infoRow(Icons.access_time, 'ENTRY TIME', 'BEFORE 11:30 PM'),
          const Divider(color: Colors.white10, height: 32),
          _infoRow(
            Icons.person_add_outlined,
            'PLUS ONE',
            'ALLOWED (+${_guestCount - 1})',
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, color: Colors.amber, size: 20),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 14,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGuestCounter() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'NUMBER OF GUESTS',
          style: LunaraTheme.headingStyle.copyWith(
            fontSize: 14,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 16),
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          borderRadius: BorderRadius.circular(20),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: () {
                  if (_guestCount > 1) {
                    setState(() => _guestCount--);
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _guestCount > 1
                        ? LunaraTheme.primaryRich.withValues(alpha: 0.2)
                        : Colors.white10,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _guestCount > 1
                          ? LunaraTheme.primaryRich
                          : Colors.white10,
                    ),
                  ),
                  child: Icon(
                    Icons.remove,
                    color: _guestCount > 1
                        ? LunaraTheme.primaryRich
                        : Colors.white24,
                  ),
                ),
              ),
              const SizedBox(width: 32),
              Text(
                '$_guestCount',
                style: LunaraTheme.headingStyle.copyWith(fontSize: 36),
              ),
              const SizedBox(width: 32),
              GestureDetector(
                onTap: () {
                  if (_guestCount < 10) {
                    setState(() => _guestCount++);
                  }
                },
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _guestCount < 10
                        ? LunaraTheme.primaryRich.withValues(alpha: 0.2)
                        : Colors.white10,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _guestCount < 10
                          ? LunaraTheme.primaryRich
                          : Colors.white10,
                    ),
                  ),
                  child: Icon(
                    Icons.add,
                    color: _guestCount < 10
                        ? LunaraTheme.primaryRich
                        : Colors.white24,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPriceSummary() {
    final total = _pricePerGuest * _guestCount;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: BorderRadius.circular(20),
      borderColor: LunaraTheme.accentVivid.withValues(alpha: 0.3),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Cover charge per person',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              Text(
                '₹${_pricePerGuest.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Guests',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              Text(
                'x $_guestCount',
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOTAL',
                style: LunaraTheme.headingStyle.copyWith(fontSize: 16),
              ),
              Text(
                '₹${total.toStringAsFixed(0)}',
                style: LunaraTheme.headingStyle.copyWith(
                  fontSize: 20,
                  color: LunaraTheme.accentVivid,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTerms() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'REQUIREMENTS:',
          style: TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        _termItem('21+ Government ID required at entry.'),
        _termItem('Dress code: Upscale/Nightlife chic.'),
        _termItem('Guestlist does not guarantee entry if venue is full.'),
        _termItem('Cover charge includes one complimentary drink.'),
      ],
    );
  }

  Widget _termItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: LunaraTheme.accentVivid,
            size: 14,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final total = _pricePerGuest * _guestCount;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: LunaraActionButton(
        text: 'PAY ₹${total.toStringAsFixed(0)} & JOIN',
        onPressed: () => _showPaymentConfirmation(context, total),
      ),
    );
  }

  void _showPaymentConfirmation(BuildContext context, double total) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: LunaraTheme.midnightBlack,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          title: Text(
            'CONFIRM PAYMENT',
            style: LunaraTheme.headingStyle.copyWith(fontSize: 20),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              _paymentRow('Venue', widget.venue['name'] ?? 'The Venue'),
              _paymentRow('Date', 'Tonight, Oct 24'),
              _paymentRow('Entry', 'Before 11:30 PM'),
              _paymentRow('Guests', '$_guestCount'),
              const Divider(color: Colors.white10, height: 24),
              _paymentRow(
                'Total',
                '₹${total.toStringAsFixed(0)}',
                isBold: true,
              ),
              const SizedBox(height: 20),
              // Mock payment options
              const Text(
                'Select payment method:',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _paymentMethodChip('UPI', Icons.account_balance),
                  _paymentMethodChip('Card', Icons.credit_card),
                  _paymentMethodChip('Wallet', Icons.account_balance_wallet),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text(
                'CANCEL',
                style: TextStyle(color: Colors.white38),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: LunaraTheme.primaryRich,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () {
                Navigator.pop(ctx);
                _showSuccessDialog(context);
              },
              child: const Text(
                'CONFIRM & PAY',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _paymentRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white54,
              fontSize: isBold ? 14 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: isBold ? LunaraTheme.accentVivid : Colors.white,
              fontSize: isBold ? 16 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentMethodChip(String label, IconData icon) {
    bool isSelected = label == 'UPI'; // Example: UPI is selected
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      borderRadius: BorderRadius.circular(12),
      opacity: isSelected ? 0.1 : 0.05,
      borderColor: isSelected
          ? LunaraTheme.accentVivid.withValues(alpha: 0.5)
          : Colors.white.withValues(alpha: 0.1),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: LunaraTheme.accentVivid, size: 20),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
      ),
    );
  }

  void _showSuccessDialog(BuildContext context) {
    final confirmationCode = 'LNR-${Random().nextInt(9000) + 1000}';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: LunaraTheme.midnightBlack,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: LunaraTheme.accentVivid.withValues(alpha: 0.5),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: LunaraTheme.accentVivid.withValues(alpha: 0.15),
                  border: Border.all(color: LunaraTheme.accentVivid, width: 2),
                ),
                child: const Icon(
                  Icons.check,
                  color: LunaraTheme.accentVivid,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'YOU\'RE ON THE LIST!',
                style: LunaraTheme.headingStyle.copyWith(fontSize: 22),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Payment successful. Your guestlist spot at ${widget.venue['name'] ?? 'the venue'} is confirmed.',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              GlassCard(
                padding: const EdgeInsets.all(16),
                borderRadius: BorderRadius.circular(16),
                borderColor: Colors.white.withValues(alpha: 0.7),
                child: Column(
                  children: [
                    const Text(
                      'CONFIRMATION CODE',
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      confirmationCode,
                      style: LunaraTheme.headingStyle.copyWith(
                        fontSize: 28,
                        color: Colors.amber,
                        letterSpacing: 4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Guests: $_guestCount  •  Tonight',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Show this code at the venue entrance',
                style: TextStyle(
                  color: LunaraTheme.accentVivid,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          actions: [
            Center(
              child: TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context);
                },
                child: const Text(
                  'DONE',
                  style: TextStyle(
                    color: LunaraTheme.accentVivid,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
