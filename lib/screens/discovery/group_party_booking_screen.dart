import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../models/venue.dart';

import '../../services/api_service.dart';
import 'payment_confirmation_screen.dart';
import '../../services/app_tour_service.dart';

class GroupPartyBookingScreen extends StatefulWidget {
  const GroupPartyBookingScreen({super.key});

  @override
  State<GroupPartyBookingScreen> createState() =>
      _GroupPartyBookingScreenState();
}

class _GroupPartyBookingScreenState extends State<GroupPartyBookingScreen> {
  List<Venue> _venues = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVenues();
  }

  Future<void> _loadVenues() async {
    try {
      final venues = await ApiService.fetchVenues();
      if (mounted) {
        setState(() {
          _venues = venues
              .where((v) => v.status?.toLowerCase() == 'live')
              .toList();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppTourService.showGroupPartyTour(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('GROUP PARTIES', style: TextStyle(letterSpacing: 2)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(
                color: LunaraTheme.electricViolet,
              ),
            )
          : CustomScrollView(
              slivers: [
                SliverToBoxAdapter(child: _buildPromotionalBanner()),
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Padding(
                        padding: EdgeInsets.fromLTRB(24, 24, 24, 16),
                        child: Text(
                          'POPULAR PUBS',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 340,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          scrollDirection: Axis.horizontal,
                          itemCount: _venues.length,
                          itemBuilder: (context, index) {
                            return _buildVenueCard(_venues[index]);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPromotionalBanner() {
    return Container(
      key: AppTourService.groupPartyBannerKey,
      margin: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      child: Stack(
        clipBehavior: Clip.antiAlias,
        children: [
          // Background with Gradient and Decorative Elements
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFFB952EB),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB952EB).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
            ),
          ),
          // Decorative Blurred Circles
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.1),
              ),
            ),
          ),
          Positioned(
            bottom: -30,
            left: 20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ),
          // Banner Content - Defines the height of the Stack
          SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Text(
                      'LIMITED OFFER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'FIRST MONTH\nJOINING FREE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Join Lunara today and enjoy exclusive\ngroup booking perks with zero fees.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Icon/Badge on the right
          // Positioned(
          //   right: 20,
          //   bottom: 20,
          //   child: Container(
          //     padding: const EdgeInsets.all(12),
          //     decoration: BoxDecoration(
          //       color: Colors.white,
          //       shape: BoxShape.circle,
          //       boxShadow: [
          //         BoxShadow(
          //           color: Colors.black.withValues(alpha: 0.1),
          //           blurRadius: 10,
          //         ),
          //       ],
          //     ),
          //     child: const Icon(
          //       Icons.bolt_rounded,
          //       color: LunaraTheme.electricViolet,
          //       size: 32,
          //     ),
          //   ),
          // ),
        ],
      ),
    );
  }

  Widget _buildVenueCard(Venue venue) {
    return GestureDetector(
      onTap: () => _showBookingModal(venue),
      child: Container(
        width: 280,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFF3EEFF), Color(0xFFF8F4FF), Color(0xFFEEE6FF)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x1A7F00FF), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0x0D7F00FF),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
            BoxShadow(
              color: const Color(0x0A7F00FF),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              child: Stack(
                children: [
                  Image.network(
                    venue.imageUrl ?? '',
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      height: 160,
                      width: double.infinity,
                      color: Colors.grey[200],
                      child: const Icon(Icons.broken_image, color: Colors.grey),
                    ),
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return Container(
                        height: 160,
                        color: Colors.grey[50],
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      );
                    },
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.amber[50],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            color: Colors.amber,
                            size: 14,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            venue.averageRating.toString(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          venue.name.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    (venue.type ?? 'Venue').toUpperCase(),
                    style: const TextStyle(
                      color: LunaraTheme.electricViolet,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_rounded,
                        color: Colors.grey,
                        size: 14,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        venue.city,
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBookingModal(Venue venue) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _BookingDetailsModal(venue: venue),
    );
  }
}

class _BookingDetailsModal extends StatefulWidget {
  final Venue venue;

  const _BookingDetailsModal({required this.venue});

  @override
  State<_BookingDetailsModal> createState() => _BookingDetailsModalState();
}

class _BookingDetailsModalState extends State<_BookingDetailsModal> {
  int _noOfFriends = 1;
  late final TextEditingController _friendsController = TextEditingController(
    text: _noOfFriends.toString(),
  );
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _optMobileController = TextEditingController();
  
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final TextEditingController _dateController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      AppTourService.showGroupPartyBookingTour(context);
    });
  }

  @override
  void dispose() {
    _friendsController.dispose();
    _mobileController.dispose();
    _optMobileController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double basePrice = widget.venue.tableBookingCharges ?? 0;
    final double subtotal = basePrice * _noOfFriends;
    final double discountPercent = widget.venue.discountPercentage ?? 0;
    final double discountAmount = (subtotal * discountPercent) / 100;
    final double totalPrice = subtotal - discountAmount;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'BOOKING AT ${widget.venue.name.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // No of Friends Selector
                  const Text(
                    'NUMBER OF FRIENDS',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    key: AppTourService.groupPartyFriendsKey,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Icon(
                          Icons.people_alt_rounded,
                          color: LunaraTheme.electricViolet,
                        ),
                        Row(
                          children: [
                            _buildCounterButton(Icons.remove, () {
                              if (_noOfFriends > 1) {
                                setState(() {
                                  _noOfFriends--;
                                  _friendsController.text = _noOfFriends
                                      .toString();
                                });
                              }
                            }),
                            Container(
                              width: 60,
                              margin: const EdgeInsets.symmetric(
                                horizontal: 12,
                              ),
                              child: TextField(
                                controller: _friendsController,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  contentPadding: EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  border: InputBorder.none,
                                ),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onChanged: (value) {
                                  if (value.isNotEmpty) {
                                    int parsed = int.tryParse(value) ?? 1;
                                    final int maxGuests =
                                        widget.venue.capacity ?? 20;
                                    if (parsed > maxGuests) {
                                      parsed = maxGuests;
                                      _friendsController.text = maxGuests
                                          .toString();
                                      _friendsController.selection =
                                          TextSelection.fromPosition(
                                            TextPosition(
                                              offset: maxGuests
                                                  .toString()
                                                  .length,
                                            ),
                                          );
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Maximum $maxGuests friends allowed',
                                          ),
                                        ),
                                      );
                                    }
                                    setState(() {
                                      _noOfFriends = parsed;
                                    });
                                  }
                                },
                              ),
                            ),
                            _buildCounterButton(Icons.add, () {
                              final int maxGuests = widget.venue.capacity ?? 20;
                              if (_noOfFriends < maxGuests) {
                                setState(() {
                                  _noOfFriends++;
                                  _friendsController.text = _noOfFriends
                                      .toString();
                                });
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Maximum $maxGuests friends allowed',
                                    ),
                                  ),
                                );
                              }
                            }),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'DATE & TIME',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: () async {
                      final date = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 60)),
                      );
                      if (date != null) {
                        if (!context.mounted) return;
                        final time = await showTimePicker(
                          context: context,
                          initialTime: TimeOfDay.now(),
                        );
                        if (time != null) {
                          setState(() {
                            _selectedDate = date;
                            _selectedTime = time;
                            final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
                            final min = time.minute.toString().padLeft(2, '0');
                            final ampm = time.hour >= 12 ? 'PM' : 'AM';
                            _dateController.text = "${date.day}/${date.month}/${date.year} at $hour:$min $ampm";
                          });
                        }
                      }
                    },
                    child: AbsorbPointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: TextField(
                          controller: _dateController,
                          decoration: InputDecoration(
                            hintText: 'Select Date & Time *',
                            hintStyle: TextStyle(
                              color: Colors.grey[400],
                              fontSize: 13,
                            ),
                            prefixIcon: const Icon(
                              Icons.calendar_today_rounded,
                              color: Color(0xFF7C3AED),
                              size: 20,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'CONTACT DETAILS',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: TextField(
                      controller: _mobileController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'Mobile Number *',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.phone,
                          color: LunaraTheme.electricViolet,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey[50],
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[200]!),
                    ),
                    child: TextField(
                      controller: _optMobileController,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: 'Optional Mobile Number',
                        hintStyle: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 13,
                        ),
                        prefixIcon: const Icon(
                          Icons.phone_android,
                          color: LunaraTheme.electricViolet,
                          size: 20,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Price Details Section
                  const Text(
                    'PRICING DETAILS',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFFF3EEFF),
                          Color(0xFFF8F4FF),
                          Color(0xFFEEE6FF),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: const Color(0x1A7F00FF),
                        width: 1.2,
                      ),
                    ),
                    child: Column(
                      children: [
                        _buildPriceRow(
                          'Table Booking Charges ($_noOfFriends)',
                          subtotal,
                          icon: Icons.person_rounded,
                        ),
                        if (discountPercent > 0) ...[
                          const SizedBox(height: 12),
                          _buildPriceRow(
                            'Discount ($discountPercent%)',
                            -discountAmount,
                            isDiscount: true,
                          ),
                        ],
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Divider(height: 1),
                        ),
                        _buildPriceRow(
                          'Total Amount',
                          totalPrice,
                          isTotal: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    key: AppTourService.groupPartyProceedButtonKey,
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final parsed = int.tryParse(_friendsController.text);
                        if (parsed == null || parsed < 1) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Please enter a valid number of friends.',
                              ),
                            ),
                          );
                          return;
                        }
                        final int maxGuests = widget.venue.capacity ?? 20;
                        if (parsed > maxGuests) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Maximum $maxGuests friends allowed.',
                              ),
                            ),
                          );
                          return;
                        }
                        if (_selectedDate == null || _selectedTime == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Please select Date and Time.'),
                            ),
                          );
                          return;
                        }

                        if (_mobileController.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Mobile number is required.'),
                            ),
                          );
                          return;
                        }
                        setState(() {
                          _noOfFriends = parsed;
                        });

                        final hour = _selectedTime!.hour % 12 == 0 ? 12 : _selectedTime!.hour % 12;
                        final min = _selectedTime!.minute.toString().padLeft(2, '0');
                        final ampm = _selectedTime!.hour >= 12 ? 'PM' : 'AM';
                        final formattedTime = '$hour:$min $ampm';

                        final parentContext = context;
                        Navigator.pop(context);
                        Navigator.push(
                          parentContext,
                          MaterialPageRoute(
                            builder: (_) => PaymentConfirmationScreen(
                              venue: widget.venue.toMap(),
                              date:
                                  '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}',
                              package: 'Group Party Booking',
                              time: formattedTime,
                              table: 'Group Party',
                              guests: '$parsed Friends',
                              totalPrice: '₹${totalPrice.toStringAsFixed(0)}',
                              showSplitBill: false,
                              mobileNumber: _mobileController.text.trim(),
                              optionalMobileNumber: _optMobileController.text
                                  .trim(),
                            ),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LunaraTheme.electricViolet,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'PROCEED TO PAYMENT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCounterButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey[300]!),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: LunaraTheme.electricViolet),
      ),
    );
  }

  Widget _buildPriceRow(
    String label,
    double amount, {
    bool isDiscount = false,
    bool isTotal = false,
    IconData? icon,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 16 : 14,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
                color: isTotal ? Colors.black : Colors.black87,
              ),
            ),
            if (icon != null) ...[
              const SizedBox(width: 4),
              Icon(
                icon,
                size: 14,
                color: isTotal ? LunaraTheme.electricViolet : Colors.black54,
              ),
            ],
          ],
        ),
        Text(
          '${amount < 0 ? "-" : ""}₹ ${amount.abs().toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: isTotal ? 20 : 16,
            fontWeight: FontWeight.w700,
            color: isDiscount
                ? const Color(0xFF10B981)
                : (isTotal ? LunaraTheme.electricViolet : Colors.black),
          ),
        ),
      ],
    );
  }
}
