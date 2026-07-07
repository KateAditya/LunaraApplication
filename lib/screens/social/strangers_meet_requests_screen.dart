import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../models/strangers_meet_request.dart';
import 'strangers_meet_payment_screen.dart';
import 'strangers_meet_ticket_screen.dart';

class StrangersMeetRequestsScreen extends StatefulWidget {
  const StrangersMeetRequestsScreen({super.key});

  @override
  State<StrangersMeetRequestsScreen> createState() => _StrangersMeetRequestsScreenState();
}

class _StrangersMeetRequestsScreenState extends State<StrangersMeetRequestsScreen> {
  String _selectedFilter = 'pending'; // 'pending', 'approved', 'rejected'
  bool _isLoading = true;
  List<StrangersMeetRequest> _requests = [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    final requests = await ApiService.fetchMyStrangersMeetRequests(status: _selectedFilter);
    if (mounted) {
      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    }
  }

  void _onProceedToPayment(StrangersMeetRequest req) {
    if (req.paymentAmount == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StrangersMeetPaymentScreen(
          request: req,
          onPaymentSuccess: () {
            // Reload the list when returning
            _loadRequests();
          },
        ),
      ),
    );
  }

  void _onViewTicket(StrangersMeetRequest req) {
    if (req.ticketId == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StrangersMeetTicketScreen(request: req),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text(
          'My Meet Requests',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: Column(
        children: [
          // Filters
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildFilterChip('Pending', 'pending'),
                _buildFilterChip('Approved', 'approved'),
                _buildFilterChip('Rejected', 'rejected'),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: LunaraTheme.electricViolet))
                : _requests.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadRequests,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _requests.length,
                          itemBuilder: (context, index) {
                            final req = _requests[index];
                            return _buildRequestCard(req);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return GestureDetector(
      onTap: () {
        if (_selectedFilter != value) {
          setState(() {
            _selectedFilter = value;
            _isLoading = true;
          });
          _loadRequests();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? LunaraTheme.electricViolet : Colors.grey[100],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[600],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox_rounded, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            'No $_selectedFilter requests',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCard(StrangersMeetRequest req) {
    final isApproved = req.status == 'approved';
    final isPaid = req.paymentStatus == 'paid';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: LunaraTheme.electricViolet.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    req.subject,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildStatusBadge(req.status, req.paymentStatus),
              ],
            ),
            const SizedBox(height: 8),
            
            // Tagline
            Text(
              req.tagline,
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 16),

            // Details
            _buildDetailRow(Icons.location_on_rounded, req.venue?['name'] ?? 'Unknown Venue'),
            const SizedBox(height: 8),
            _buildDetailRow(Icons.calendar_today_rounded, DateFormat('MMM dd, yyyy • hh:mm a').format(req.eventDateTime)),
            const SizedBox(height: 8),
            _buildDetailRow(Icons.people_alt_rounded, '${req.numberOfPersons} persons'),
            
            if (req.adminNotes != null && req.adminNotes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Admin Note: ${req.adminNotes}',
                        style: const TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // Actions
            if (isApproved && !isPaid) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Amount to Pay', style: TextStyle(color: Colors.grey[500], fontSize: 12)),
                      Text(
                        '₹${req.paymentAmount?.toStringAsFixed(0) ?? '0'}',
                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black),
                      ),
                    ],
                  ),
                  ElevatedButton(
                    onPressed: () => _onProceedToPayment(req),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: LunaraTheme.electricViolet,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: const Text('PROCEED TO PAYMENT', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ],

            if (isApproved && isPaid && req.ticketId != null) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _onViewTicket(req),
                  icon: const Icon(Icons.local_activity_rounded, color: LunaraTheme.electricViolet),
                  label: const Text('VIEW TICKET', style: TextStyle(color: LunaraTheme.electricViolet, fontWeight: FontWeight.bold)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: LunaraTheme.electricViolet),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status, String paymentStatus) {
    Color bg;
    Color text;
    String label = status.toUpperCase();

    if (status == 'pending') {
      bg = Colors.orange.withValues(alpha: 0.1);
      text = Colors.orange;
    } else if (status == 'rejected') {
      bg = Colors.red.withValues(alpha: 0.1);
      text = Colors.red;
    } else {
      if (paymentStatus == 'paid') {
        bg = Colors.green.withValues(alpha: 0.1);
        text = Colors.green;
        label = 'PAID';
      } else {
        bg = LunaraTheme.electricViolet.withValues(alpha: 0.1);
        text = LunaraTheme.electricViolet;
        label = 'APPROVED';
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: text,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[500]),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: Colors.grey[700], fontSize: 13),
          ),
        ),
      ],
    );
  }
}
