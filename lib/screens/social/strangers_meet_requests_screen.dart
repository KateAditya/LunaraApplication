import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../services/api_service.dart';
import '../../models/strangers_meet_request.dart';
import 'strangers_meet_payment_screen.dart';
import 'strangers_meet_ticket_screen.dart';
import 'post_detail_screen.dart';

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
    final eventPassed = req.eventDateTime.isBefore(DateTime.now());
    
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PostDetailScreen(
              post: {
                'id': req.id,
                'type': 'strangers_meet',
              },
              venue: req.venue,
            ),
          ),
        ).then((_) => _loadRequests());
      },
      child: Container(
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
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: LunaraTheme.electricViolet.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: LunaraTheme.electricViolet.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.rocket_launch_rounded,
                        color: LunaraTheme.electricViolet,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Admin approved your request! Pay deposit of ₹${req.paymentAmount?.toStringAsFixed(0) ?? '0'} to publish it to the Home Screen.',
                          style: const TextStyle(
                            color: LunaraTheme.electricViolet,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
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
                      child: const Text('PAY PLATFORM FEE & PUBLISH', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
              ],
  
              if (isApproved && isPaid && req.ticketId != null) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _onViewTicket(req),
                        icon: const Icon(Icons.local_activity_rounded, color: LunaraTheme.electricViolet, size: 16),
                        label: const Text('VIEW TICKET', style: TextStyle(color: LunaraTheme.electricViolet, fontWeight: FontWeight.bold, fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: LunaraTheme.electricViolet),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    if (req.status != 'completed') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _onMarkCompleted(req),
                          icon: const Icon(Icons.check_circle_outline_rounded, color: Colors.white, size: 16),
                          label: const Text('MEET SUCCESSFUL', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
  
              if (isApproved && isPaid && (req.status == 'completed' || eventPassed)) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                
                // Dynamic Financial Breakdown Card
                Builder(builder: (context) {
                  final deposit = req.paymentAmount ?? 0.0;
                  final totalSeats = req.numberOfPersons;
                  final filled = req.slotsFilled;
                  final unfilled = totalSeats - filled;
                  final platformChargePerSeat = req.platformChargePerSeat ?? (totalSeats > 0 ? deposit / totalSeats : 0.0);
                  
                  final refundForUnfilled = unfilled * platformChargePerSeat;
                  final ticketRevenue = filled * req.chargesPerHead;
                  final finalPayout = ticketRevenue + refundForUnfilled;
                  final profit = finalPayout - deposit;
  
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'DYNAMIC SETTLEMENT BREAKDOWN',
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.purple.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '$filled/$totalSeats Seats Filled',
                                style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.purple),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildFinancialRow('Initial Platform Deposit', '- ₹${deposit.toStringAsFixed(0)}', isNegative: true),
                        const SizedBox(height: 6),
                        _buildFinancialRow('Participant Revenue ($filled × ₹${req.chargesPerHead.toStringAsFixed(0)})', '+ ₹${ticketRevenue.toStringAsFixed(0)}', isPositive: true),
                        const SizedBox(height: 6),
                        _buildFinancialRow('Unfilled Seats Refund ($unfilled × ₹${platformChargePerSeat.toStringAsFixed(0)})', '+ ₹${refundForUnfilled.toStringAsFixed(0)}', isPositive: true),
                        const Divider(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Total Settlement Amount', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text('₹${finalPayout.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w900, color: Colors.black)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Net Profit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                            Text(
                              '${profit >= 0 ? '+' : ''}₹${profit.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                color: profit >= 0 ? Colors.green : Colors.orange,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
  
                const SizedBox(height: 12),
                if (req.settlementStatus == 'none') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _onRequestSettlement(req),
                      icon: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 16),
                      label: const Text('REQUEST SETTLEMENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LunaraTheme.electricViolet,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ] else if (req.settlementStatus == 'requested') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.hourglass_empty_rounded, color: Colors.orange, size: 16),
                            SizedBox(width: 8),
                            Text('Settlement Requested', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Settling To: ${req.bankDetailsSummary}', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                      ],
                    ),
                  ),
                ] else if (req.settlementStatus == 'paid') ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: Colors.green, size: 16),
                            SizedBox(width: 8),
                            Text('Settlement Paid', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 13)),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text('Amount: ₹${req.settlementAmount?.toStringAsFixed(2) ?? "0.00"}', style: TextStyle(color: Colors.grey[800], fontSize: 13, fontWeight: FontWeight.w600)),
                        Text('Method: ${req.settlementMethod ?? "N/A"}', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                        Text('Txn ID: ${req.settlementTransactionId ?? "N/A"}', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                        if (req.settlementDate != null)
                          Text('Date: ${DateFormat('MMM dd, yyyy • hh:mm a').format(req.settlementDate!)}', style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinancialRow(String label, String value, {bool isPositive = false, bool isNegative = false}) {
    Color valColor = Colors.black87;
    if (isPositive) valColor = Colors.green;
    if (isNegative) valColor = Colors.red;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: valColor)),
      ],
    );
  }

  Future<void> _onMarkCompleted(StrangersMeetRequest req) async {
    setState(() => _isLoading = true);
    try {
      final success = await ApiService.completeStrangersMeet(req.id);
      if (!mounted) return;
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Meetup marked as successfully completed! 🎉')),
        );
        _loadRequests();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      final errorStr = e.toString().replaceAll('Exception: ', '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorStr), backgroundColor: Colors.red),
      );
    }
  }

  void _onRequestSettlement(StrangersMeetRequest req) {
    // Default pre-fill with the bank details they provided during creation
    final defaultDetails = req.bankDetailsSummary;
    final controller = TextEditingController(text: defaultDetails);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Request Settlement', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Confirm your payout details below. Admin will transfer your earnings to this account:'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: 'e.g. UPI ID: name@upi or Bank details',
                labelText: 'Settlement Payout Details',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () async {
              final bankDetails = controller.text.trim();
              if (bankDetails.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter settlement details')),
                );
                return;
              }
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              try {
                final success = await ApiService.submitStrangersMeetSettlement(req.id, bankDetails);
                if (!mounted) return;
                if (success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Settlement request submitted successfully!')),
                  );
                  _loadRequests();
                }
              } catch (e) {
                if (!mounted) return;
                setState(() => _isLoading = false);
                final errorStr = e.toString().replaceAll('Exception: ', '');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(errorStr), backgroundColor: Colors.red),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: LunaraTheme.electricViolet),
            child: const Text('REQUEST'),
          ),
        ],
      ),
    );
  }


  Widget _buildStatusBadge(String status, String paymentStatus) {
    Color bg;
    Color text;
    String label = status.toUpperCase();

    if (status == 'pending') {
      bg = Colors.orange.withValues(alpha: 0.15);
      text = Colors.orange[800]!;
      label = 'PENDING APPROVAL';
    } else if (status == 'rejected') {
      bg = Colors.red.withValues(alpha: 0.15);
      text = Colors.red[800]!;
      label = 'REJECTED';
    } else {
      if (paymentStatus == 'paid') {
        bg = Colors.green.withValues(alpha: 0.15);
        text = Colors.green[800]!;
        label = 'PAID & LIVE';
      } else {
        bg = Colors.amber.withValues(alpha: 0.2);
        text = Colors.amber[900]!;
        label = 'APPROVED - PAYMENT PENDING';
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
