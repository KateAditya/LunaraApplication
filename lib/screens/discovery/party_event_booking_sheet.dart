import 'package:flutter/material.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../widgets/action_button.dart';
import 'digital_ticket_screen.dart';

class PartyEventBookingSheet extends StatefulWidget {
  final Map<String, dynamic> event;

  const PartyEventBookingSheet({super.key, required this.event});

  @override
  State<PartyEventBookingSheet> createState() => _PartyEventBookingSheetState();
}

class _PartyEventBookingSheetState extends State<PartyEventBookingSheet> {
  int _quantity = 1;
  bool _isProcessing = false;

  void _processBooking() async {
    setState(() => _isProcessing = true);
    final eventId = widget.event['eventId'];
    final entryPrice = (widget.event['entryPrice'] ?? 0) as num;

    final bookingRes = await ApiService.createPartyBooking(
      partyEventId: eventId,
      quantity: _quantity,
    );

    if (bookingRes != null && bookingRes['success'] == true) {
      if (entryPrice == 0) {
        // Free event
        if (mounted) {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DigitalTicketScreen(
                venue: widget.event['venueMap'],
                date: widget.event['date'],
                package: 'Party Ticket',
                time: '8:00 PM', // Fallback time
                guests: _quantity.toString(),
                totalPrice: '0',
                ticketId: bookingRes['data']?['ticketCode'] ?? '',
                status: 'CONFIRMED',
              ),
            ),
          );
        }
      } else {
        // Paid event - simulate Razorpay
        final razorpayOrderId = bookingRes['razorpayOrderId'];
        final bookingId = bookingRes['data']['id'];

        final payRes = await ApiService.payNowBooking(bookingId);
        
        if (mounted) {
          setState(() => _isProcessing = false);
          Navigator.pop(context);
          if (payRes != null) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => DigitalTicketScreen(
                  venue: widget.event['venueMap'],
                  date: widget.event['date'],
                  package: 'Party Ticket',
                  time: '8:00 PM',
                  guests: _quantity.toString(),
                  totalPrice: (entryPrice * _quantity).toStringAsFixed(2),
                  ticketId: payRes['ticketCode'] ?? '',
                  status: 'CONFIRMED',
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Payment failed. Please try again.')),
            );
          }
        }
      }
    } else {
      if (mounted) {
        setState(() => _isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(bookingRes?['message'] ?? 'Failed to book event.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.event['title'] ?? 'Party Event';
    final entryPrice = (widget.event['entryPrice'] ?? 0) as num;
    final remainingSeats = widget.event['remainingSeats'] ?? 999999;
    final isUnlimited = widget.event['isUnlimited'] == true;

    final maxSeats = isUnlimited ? 10 : (remainingSeats > 10 ? 10 : remainingSeats);

    return Container(
      decoration: BoxDecoration(
        color: LunaraTheme.darkBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Book $title',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Number of Tickets',
                style: TextStyle(color: Colors.white70, fontSize: 16),
              ),
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.white),
                    onPressed: _quantity > 1
                        ? () => setState(() => _quantity--)
                        : null,
                  ),
                  Text(
                    '$_quantity',
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline, color: Colors.white),
                    onPressed: _quantity < maxSeats
                        ? () => setState(() => _quantity++)
                        : null,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total Amount',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                entryPrice == 0 ? 'FREE' : '₹${(entryPrice * _quantity).toStringAsFixed(2)}',
                style: const TextStyle(color: LunaraTheme.electricViolet, fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 32),
          LunaraActionButton(
            text: _isProcessing 
                ? 'PROCESSING...' 
                : (entryPrice == 0 ? 'CONFIRM BOOKING' : 'PROCEED TO PAY'),
            onPressed: _isProcessing ? () {} : _processBooking,
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
