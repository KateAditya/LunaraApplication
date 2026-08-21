import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../services/api_service.dart';

class SmartCheckoutSheet extends StatefulWidget {
  final String title;
  final String subtitle;
  final double itemPrice;
  final Map<String, dynamic>? metadata;
  final Future<bool> Function() onWalletPayment;
  final Future<dynamic> Function() onDirectPayment;
  final Future<dynamic> Function(double shortfallAmount) onHybridPayment;

  const SmartCheckoutSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.itemPrice,
    this.metadata,
    required this.onWalletPayment,
    required this.onDirectPayment,
    required this.onHybridPayment,
  });

  static Future<bool?> show({
    required BuildContext context,
    required String title,
    required String subtitle,
    required double itemPrice,
    Map<String, dynamic>? metadata,
    required Future<bool> Function() onWalletPayment,
    required Future<dynamic> Function() onDirectPayment,
    required Future<dynamic> Function(double shortfallAmount) onHybridPayment,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SmartCheckoutSheet(
        title: title,
        subtitle: subtitle,
        itemPrice: itemPrice,
        metadata: metadata,
        onWalletPayment: onWalletPayment,
        onDirectPayment: onDirectPayment,
        onHybridPayment: onHybridPayment,
      ),
    );
  }

  @override
  State<SmartCheckoutSheet> createState() => _SmartCheckoutSheetState();
}

class _SmartCheckoutSheetState extends State<SmartCheckoutSheet> {
  bool _isLoadingWallet = true;
  bool _isProcessing = false;
  double _availableBalance = 0.0;

  @override
  void initState() {
    super.initState();
    _fetchWalletBalance();
  }

  Future<void> _fetchWalletBalance() async {
    final data = await ApiService.fetchWalletData();
    if (mounted) {
      setState(() {
        if (data != null && data['wallet'] != null) {
          _availableBalance = double.tryParse(
                (data['wallet']['availableBalance'] ?? data['wallet']['balance'] ?? 0.0).toString(),
              ) ??
              0.0;
        }
        _isLoadingWallet = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasEnoughBalance = _availableBalance >= widget.itemPrice;
    final shortfall = (widget.itemPrice - _availableBalance).clamp(0.0, double.infinity);

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag Handle
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Title Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.account_balance_wallet_rounded, color: LunaraTheme.electricViolet, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                        color: Colors.black,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.subtitle,
                      style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Price Breakdown Box
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1E1035), Color(0xFF2E1B4E)],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'TOTAL PAYABLE',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1),
                    ),
                    Text(
                      '₹${widget.itemPrice.toStringAsFixed(2)}',
                      style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: Colors.white.withValues(alpha: 0.12)),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.account_balance_wallet_outlined, color: Colors.white70, size: 14),
                        const SizedBox(width: 6),
                        Text(
                          'Available Wallet Credit',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    _isLoadingWallet
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 1.5))
                        : Text(
                            '₹${_availableBalance.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: hasEnoughBalance ? const Color(0xFF10B981) : Colors.amber,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Hybrid Shortfall Alert (If insufficient balance)
          if (!_isLoadingWallet && !hasEnoughBalance)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFCD34D)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 11, color: Color(0xFF92400E), height: 1.3),
                        children: [
                          const TextSpan(text: 'Wallet balance is short by '),
                          TextSpan(
                            text: '₹${shortfall.toStringAsFixed(0)}',
                            style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFFB45309)),
                          ),
                          const TextSpan(text: '. Select Smart Hybrid Pay to add shortfall and complete purchase.'),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          // Action Buttons
          if (_isProcessing)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: LunaraTheme.electricViolet, strokeWidth: 2.5),
                  SizedBox(height: 14),
                  Text(
                    'Connecting to Secure Payment Gateway...',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            )
          else ...[
            // Primary Smart Wallet / Hybrid Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  setState(() => _isProcessing = true);
                  if (hasEnoughBalance) {
                    final success = await widget.onWalletPayment();
                    if (mounted) {
                      setState(() => _isProcessing = false);
                      if (success) navigator.pop(true);
                    }
                  } else {
                    final dynamic res = await widget.onHybridPayment(shortfall);
                    if (mounted) {
                      setState(() => _isProcessing = false);
                      if (res == true) {
                        navigator.pop(true);
                      } else if (res != false && res != null) {
                        navigator.pop(res);
                      }
                    }
                  }
                },
                icon: Icon(
                  hasEnoughBalance ? Icons.flash_on_rounded : Icons.add_card_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                label: Text(
                  hasEnoughBalance
                      ? 'PAY ₹${widget.itemPrice.toStringAsFixed(0)} WITH SMART WALLET'
                      : 'ADD ₹${shortfall.toStringAsFixed(0)} & COMPLETE PURCHASE',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Colors.white),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: hasEnoughBalance ? LunaraTheme.electricViolet : const Color(0xFFD97706),
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // Direct Payment Gateway Option
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  setState(() => _isProcessing = true);
                  try {
                    final dynamic res = await widget.onDirectPayment();
                    if (mounted) {
                      setState(() => _isProcessing = false);
                      if (res == true) {
                        navigator.pop(true);
                      } else if (res == false) {
                        // Keep sheet open so user can retry or pay with wallet
                      } else {
                        // Legacy callers returning void/null: pop
                        navigator.pop(res);
                      }
                    }
                  } catch (e) {
                    if (mounted) {
                      setState(() => _isProcessing = false);
                    }
                  }
                },
                icon: const Icon(Icons.payment_rounded, color: Colors.black87, size: 18),
                label: Text(
                  'DIRECT PAYMENT GATEWAY (PAY ₹${widget.itemPrice.toStringAsFixed(0)})',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.black87),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.grey[300]!),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
