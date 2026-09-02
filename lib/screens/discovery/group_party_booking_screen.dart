// ignore_for_file: use_build_context_synchronously
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../core/theme.dart';
import '../../models/venue.dart';

import '../../services/api_service.dart';
import '../../services/app_tour_service.dart';
import '../../widgets/venue_timing_error_dialog.dart';
import '../../widgets/venue_cover_charge_notice.dart';
import '../../widgets/top_notification_banner.dart';
import '../../widgets/subscription_limit_dialog.dart';
import '../../widgets/smart_checkout_sheet.dart';
import '../../widgets/dialogs/time_lock_blocked_dialog.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../social/large_party_ticket_screen.dart';


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
                        height: 360,
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
                            (venue.averageRating > 0
                                    ? venue.averageRating
                                    : 4.5)
                                .toStringAsFixed(1),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              color: Colors.grey,
                              size: 14,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                venue.city,
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE100FF), Color(0xFF7F00FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF7F00FF,
                              ).withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Text(
                          'BOOK NOW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
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
      builder: (modalCtx) => _BookingDetailsModal(
        venue: venue,
        rootContext: context,
      ),
    );
  }
}

class _BookingDetailsModal extends StatefulWidget {
  final Venue venue;
  final BuildContext rootContext;

  const _BookingDetailsModal({
    required this.venue,
    required this.rootContext,
  });

  @override
  State<_BookingDetailsModal> createState() => _BookingDetailsModalState();
}

class _BookingDetailsModalState extends State<_BookingDetailsModal> {
  int _noOfFriends = 2;
  late final TextEditingController _friendsController = TextEditingController(
    text: _noOfFriends.toString(),
  );
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _optMobileController = TextEditingController();

  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  final TextEditingController _dateController = TextEditingController();

  final TextEditingController _partySubjectController = TextEditingController();
  final TextEditingController _partyRequirementController =
      TextEditingController();
  final TextEditingController _partyDescriptionController =
      TextEditingController();

  String _foodPreference = 'Both';
  String _drinkPreference = 'Both';

  void _showValidationError(String message, {Map<String, dynamic>? errorData}) {
    if (message.contains('Free Plan limit') ||
        message.contains('PARTY_PLAN_LIMIT_REACHED') ||
        message.contains('Upgrade to VIP') ||
        (message.contains('limit') && message.contains('Party Plan'))) {
      showSubscriptionLimitDialog(
        context,
        feature: SubLimitFeature.partyCreation,
        customMessage: message,
      );
      return;
    }

    final isTimeLock = (errorData != null &&
            (errorData['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
                errorData['conflictingEventType'] != null)) ||
        message.contains('at least 4 hours apart') ||
        message.contains('FOUR_HOUR_TIME_LOCK') ||
        message.contains('Time Locked') ||
        (message.contains('already have a') && message.contains('4 hours'));

    if (isTimeLock) {
      final payload = Map<String, dynamic>.from(errorData ?? {});
      if (!payload.containsKey('message') || payload['message'] == null) {
        payload['message'] = message;
      }
      if (!payload.containsKey('conflictingEventTitle') || payload['conflictingEventTitle'] == null) {
        payload['conflictingEventTitle'] = widget.venue.name;
      }
      TimeLockBlockedDialog.show(context, errorData: payload);
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            const SizedBox(width: 8),
            const Text(
              'Validation Error',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ],
        ),
        content: Text(message, style: const TextStyle(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(
              'OK',
              style: TextStyle(
                color: LunaraTheme.electricViolet,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownPreference({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.only(left: 6, right: 4),
          decoration: BoxDecoration(
            color: Colors.grey[50],
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButtonFormField<String>(
              initialValue: value,
              isExpanded: true,
              decoration: InputDecoration(
                prefixIcon: Icon(
                  icon,
                  color: LunaraTheme.electricViolet,
                  size: 16,
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 24,
                  minHeight: 18,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              items: items.map((String val) {
                return DropdownMenuItem<String>(
                  value: val,
                  child: Text(
                    val,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.grey[200]!),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: LunaraTheme.electricViolet),
      ),
    );
  }

  String _formatTimeOfBooking(String? timeStr) {
    if (timeStr == null || timeStr.isEmpty) return '';
    try {
      final parts = timeStr.split(':');
      if (parts.length >= 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final ampm = hour >= 12 ? 'PM' : 'AM';
        final formattedHour = hour % 12 == 0 ? 12 : hour % 12;
        final formattedMinute = minute.toString().padLeft(2, '0');
        return '$formattedHour:$formattedMinute $ampm';
      }
    } catch (_) {}
    return timeStr;
  }

  Future<void> _handleDateSelection(DateTime date) async {
    final yyyy = date.year;
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    final dateStr = '$yyyy-$mm-$dd';
    if (widget.venue.closedDates != null &&
        widget.venue.closedDates!.contains(dateStr)) {
      VenueTimingErrorDialog.show(
        context,
        venueName: widget.venue.name,
        daysOpen: widget.venue.daysOpen,
        openingTime: widget.venue.openingTime,
        closingTime: widget.venue.closingTime,
        closedDates: widget.venue.closedDates,
      );
      return;
    }

    final weekdaysMap = {
      1: 'Monday',
      2: 'Tuesday',
      3: 'Wednesday',
      4: 'Thursday',
      5: 'Friday',
      6: 'Saturday',
      7: 'Sunday',
    };
    final weekdayName = weekdaysMap[date.weekday];
    final isOpenOnWeekday =
        weekdayName != null &&
        widget.venue.daysOpen != null &&
        widget.venue.daysOpen!.any((d) {
          final str = d.toString().trim().toLowerCase();
          final fullDay = weekdayName.toLowerCase();
          final shortDay = weekdayName.substring(0, 3).toLowerCase();
          return str.contains(fullDay) || str.contains(shortDay);
        });
    if (!isOpenOnWeekday &&
        widget.venue.daysOpen != null &&
        widget.venue.daysOpen!.isNotEmpty) {
      VenueTimingErrorDialog.show(
        context,
        venueName: widget.venue.name,
        daysOpen: widget.venue.daysOpen,
        openingTime: widget.venue.openingTime,
        closingTime: widget.venue.closingTime,
        closedDates: widget.venue.closedDates,
      );
      return;
    }

    final time = await showTimePicker(
      context: context,
      initialTime: _selectedTime ?? TimeOfDay.now(),
    );

    if (time != null) {
      if (!mounted) return;
      final selectedDateTime = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
      if (selectedDateTime.isBefore(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selected date and time cannot be in the past.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }

      final invalidReason = widget.venue.getInvalidReason(date, time);
      if (invalidReason != null) {
        VenueTimingErrorDialog.show(
          context,
          venueName: widget.venue.name,
          daysOpen: widget.venue.daysOpen,
          openingTime: widget.venue.openingTime,
          closingTime: widget.venue.closingTime,
          closedDates: widget.venue.closedDates,
        );
        return;
      }

      setState(() {
        _selectedDate = date;
        _selectedTime = time;
        final formattedTime = _formatTimeOfBooking(
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
        );
        _dateController.text =
            "${DateFormat('MMM dd, yyyy').format(date)} at $formattedTime";
      });
    }
  }

  Future<void> _handleCustomDateSelection() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );

    if (date != null) {
      await _handleDateSelection(date);
    }
  }

  bool _isTimeSlotValid(TimeOfDay time, [DateTime? specificDate]) {
    final activeDate = specificDate ?? _selectedDate;
    if (activeDate == null) return true;

    final invalidReason = widget.venue.getInvalidReason(activeDate, time);
    if (invalidReason != null) {
      return false;
    }

    final selectedDateTime = DateTime(
      activeDate.year,
      activeDate.month,
      activeDate.day,
      time.hour,
      time.minute,
    );
    final minAllowedDateTime = DateTime.now().add(const Duration(hours: 1));
    if (selectedDateTime.isBefore(minAllowedDateTime)) {
      return false;
    }
    return true;
  }

  @override
  void initState() {
    super.initState();
    final userPhone = ApiService.cachedCurrentUser?.phone;
    if (userPhone != null && userPhone.isNotEmpty) {
      final clean = userPhone.replaceAll(RegExp(r'\D'), '');
      if (clean.length >= 10) {
        _mobileController.text = clean.substring(clean.length - 10);
      }
    }
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
    _partySubjectController.dispose();
    _partyRequirementController.dispose();
    _partyDescriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double basePrice = widget.venue.tableBookingCharges ?? 0;
    final double subtotal = basePrice * _noOfFriends;
    final double discountPercent = widget.venue.discountPercentage ?? 0;
    final double discountAmount = (subtotal * discountPercent) / 100;
    final double totalPrice = subtotal - discountAmount;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    bool isVenueOpen(DateTime date) {
      final closedDates = widget.venue.closedDates;
      if (closedDates != null) {
        final yyyy = date.year;
        final mm = date.month.toString().padLeft(2, '0');
        final dd = date.day.toString().padLeft(2, '0');
        final dateStr = '$yyyy-$mm-$dd';
        if (closedDates.contains(dateStr)) {
          return false;
        }
      }

      final weekdaysMap = {
        1: 'Monday',
        2: 'Tuesday',
        3: 'Wednesday',
        4: 'Thursday',
        5: 'Friday',
        6: 'Saturday',
        7: 'Sunday',
      };
      final weekdayName = weekdaysMap[date.weekday];
      if (widget.venue.daysOpen != null && widget.venue.daysOpen!.isNotEmpty) {
        final isOpenOnWeekday =
            weekdayName != null &&
            widget.venue.daysOpen!.any((d) {
              final str = d.toString().trim().toLowerCase();
              final fullDay = weekdayName.toLowerCase();
              final shortDay = weekdayName.substring(0, 3).toLowerCase();
              return str.contains(fullDay) || str.contains(shortDay);
            });
        if (!isOpenOnWeekday) {
          return false;
        }
      }
      return true;
    }

    final List<DateTime> dynamicDates = [];
    DateTime checkDate = today;
    while (dynamicDates.length < 6) {
      if (isVenueOpen(checkDate)) {
        dynamicDates.add(checkDate);
      }
      checkDate = checkDate.add(const Duration(days: 1));
    }

    Widget buildDateChip(String label, DateTime dateVal, bool isSelected) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _selectedDate = dateVal;
            if (_selectedTime != null &&
                !_isTimeSlotValid(_selectedTime!, dateVal)) {
              _selectedTime = null;
            }
            if (_selectedDate != null && _selectedTime != null) {
              final formattedTime = _formatTimeOfBooking(
                '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}',
              );
              _dateController.text =
                  "${DateFormat('MMM dd, yyyy').format(_selectedDate!)} at $formattedTime";
            } else if (_selectedDate != null) {
              _dateController.text = DateFormat(
                'MMM dd, yyyy',
              ).format(_selectedDate!);
            } else {
              _dateController.text = '';
            }
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF7C3AED) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF7C3AED) : Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                DateFormat('MMM d').format(dateVal),
                style: TextStyle(
                  color: isSelected ? Colors.white70 : Colors.black54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildCustomChip(bool isSelected) {
      return GestureDetector(
        onTap: _handleCustomDateSelection,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFF7C3AED) : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF7C3AED) : Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_today_rounded,
                    size: 12,
                    color: isSelected ? Colors.white : Colors.black87,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Custom',
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _selectedDate != null &&
                        !dynamicDates.any(
                          (d) =>
                              d.year == _selectedDate!.year &&
                              d.month == _selectedDate!.month &&
                              d.day == _selectedDate!.day,
                        )
                    ? DateFormat('MMM d').format(_selectedDate!)
                    : 'Choose Date',
                style: TextStyle(
                  color: isSelected ? Colors.white70 : Colors.black54,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      );
    }

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
                  // Total Group Size Selector
                  const Text(
                    'TOTAL GROUP SIZE (INCLUDING YOURSELF)',
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
                              if (_noOfFriends > 2) {
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
                                        widget.venue.capacity ?? 500;
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
                              final int maxGuests =
                                  widget.venue.capacity ?? 500;
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
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        ...dynamicDates.map((dateVal) {
                          String label = '';
                          if (dateVal.year == today.year &&
                              dateVal.month == today.month &&
                              dateVal.day == today.day) {
                            label = 'Today';
                          } else if (dateVal.year == tomorrow.year &&
                              dateVal.month == tomorrow.month &&
                              dateVal.day == tomorrow.day) {
                            label = 'Tomorrow';
                          } else {
                            label = DateFormat('E').format(dateVal);
                          }

                          final isSelected =
                              _selectedDate != null &&
                              _selectedDate!.year == dateVal.year &&
                              _selectedDate!.month == dateVal.month &&
                              _selectedDate!.day == dateVal.day;

                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: buildDateChip(label, dateVal, isSelected),
                          );
                        }),
                        buildCustomChip(
                          _selectedDate != null &&
                              !dynamicDates.any(
                                (d) =>
                                    d.year == _selectedDate!.year &&
                                    d.month == _selectedDate!.month &&
                                    d.day == _selectedDate!.day,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'SELECT TIME SLOT',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Builder(
                    builder: (context) {
                      final predefinedTimes = [
                        const TimeOfDay(hour: 19, minute: 0), // 7 PM
                        const TimeOfDay(hour: 20, minute: 0), // 8 PM
                        const TimeOfDay(hour: 21, minute: 0), // 9 PM
                        const TimeOfDay(hour: 22, minute: 0), // 10 PM
                        const TimeOfDay(hour: 23, minute: 0), // 11 PM
                        const TimeOfDay(hour: 0, minute: 0), // 12 AM
                      ];

                      final validTimes = predefinedTimes
                          .where((t) => _isTimeSlotValid(t))
                          .toList();

                      String formatTimeOfDay(TimeOfDay tod) {
                        final hour = tod.hour == 0
                            ? 12
                            : (tod.hour > 12 ? tod.hour - 12 : tod.hour);
                        final ampm = tod.hour >= 12 ? 'PM' : 'AM';
                        return '$hour:00 $ampm';
                      }

                      Widget buildTimeChip(
                        String label,
                        TimeOfDay tod,
                        bool isSelected,
                      ) {
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedTime = tod;
                              if (_selectedDate != null) {
                                final formattedTime = _formatTimeOfBooking(
                                  '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}',
                                );
                                _dateController.text =
                                    "${DateFormat('MMM dd, yyyy').format(_selectedDate!)} at $formattedTime";
                              }
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF7C3AED)
                                  : Colors.grey[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFF7C3AED)
                                    : Colors.grey[300]!,
                                width: 1,
                              ),
                            ),
                            child: Text(
                              label,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      }

                      // Determine if selected time is a custom time (not in validTimes)
                      bool isCustomSelected = false;
                      if (_selectedTime != null) {
                        isCustomSelected = !validTimes.any(
                          (t) =>
                              t.hour == _selectedTime!.hour &&
                              t.minute == _selectedTime!.minute,
                        );
                      }

                      return SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          children: [
                            ...validTimes.map((tod) {
                              final label = formatTimeOfDay(tod);
                              final isSelected =
                                  _selectedTime != null &&
                                  _selectedTime!.hour == tod.hour &&
                                  _selectedTime!.minute == tod.minute;

                              return Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: buildTimeChip(label, tod, isSelected),
                              );
                            }),
                            GestureDetector(
                              onTap: () async {
                                final TimeOfDay? picked = await showTimePicker(
                                  context: context,
                                  initialTime:
                                      _selectedTime ??
                                      const TimeOfDay(hour: 22, minute: 0),
                                );
                                if (picked != null) {
                                  if (!mounted) return;
                                  if (!_isTimeSlotValid(picked)) {
                                    VenueTimingErrorDialog.show(
                                      context,
                                      venueName: widget.venue.name,
                                      daysOpen: widget.venue.daysOpen,
                                      openingTime: widget.venue.openingTime,
                                      closingTime: widget.venue.closingTime,
                                      closedDates: widget.venue.closedDates,
                                    );
                                    return;
                                  }
                                  setState(() {
                                    _selectedTime = picked;
                                    if (_selectedDate != null) {
                                      final formattedTime = _formatTimeOfBooking(
                                        '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
                                      );
                                      _dateController.text =
                                          "${DateFormat('MMM dd, yyyy').format(_selectedDate!)} at $formattedTime";
                                    }
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isCustomSelected
                                      ? const Color(0xFF7C3AED)
                                      : Colors.grey[50],
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isCustomSelected
                                        ? const Color(0xFF7C3AED)
                                        : Colors.grey[300]!,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.access_time,
                                      size: 12,
                                      color: isCustomSelected
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isCustomSelected
                                          ? _formatTimeOfBooking(
                                              '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}',
                                            )
                                          : 'Custom',
                                      style: TextStyle(
                                        color: isCustomSelected
                                            ? Colors.white
                                            : Colors.black87,
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
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      if (_selectedDate != null) {
                        _handleDateSelection(_selectedDate!);
                      } else {
                        _handleCustomDateSelection();
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
                            hintText: 'Selected Date & Time *',
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
                  if (_noOfFriends > 20) ...[
                    const Text(
                      'LARGE PARTY DETAILS',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: LunaraTheme.electricViolet,
                        letterSpacing: 1.5,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _partySubjectController,
                      decoration: _inputDecoration('Party Subject *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _partyRequirementController,
                      decoration: _inputDecoration('Party Requirement *'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _partyDescriptionController,
                      maxLines: 3,
                      decoration: _inputDecoration('Description (optional)'),
                    ),
                    const SizedBox(height: 24),
                  ],
                  // Food & Drink Preference Section
                  const Text(
                    'FOOD & DRINK PREFERENCE',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildDropdownPreference(
                          label: 'Food Preference',
                          value: _foodPreference,
                          items: const ['Veg', 'Non-Veg', 'Both'],
                          icon: Icons.restaurant,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _foodPreference = val;
                              });
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _buildDropdownPreference(
                          label: 'Drink Preference',
                          value: _drinkPreference,
                          items: const ['Alcoholic', 'Non-Alcoholic', 'Both'],
                          icon: Icons.local_bar,
                          onChanged: (val) {
                            if (val != null) {
                              setState(() {
                                _drinkPreference = val;
                              });
                            }
                          },
                        ),
                      ),
                    ],
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
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
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
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
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
                  if (_noOfFriends <= 20) ...[
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
                            overrideText: subtotal <= 0 ? 'FREE' : null,
                            icon: Icons.person_rounded,
                          ),
                          if (discountPercent > 0 && subtotal > 0) ...[
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
                            overrideText: totalPrice <= 0 ? 'FREE (₹0)' : null,
                            isTotal: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                  const VenueCoverChargeNoticeCard(),
                  const SizedBox(height: 16),
                  SizedBox(
                    key: AppTourService.groupPartyProceedButtonKey,

                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final parsed = int.tryParse(_friendsController.text);
                        if (parsed == null || parsed < 2) {
                          _showValidationError(
                            'Please enter a valid number of friends (minimum 2).',
                          );
                          return;
                        }
                        final int maxGuests = widget.venue.capacity ?? 500;
                        if (parsed > maxGuests) {
                          _showValidationError(
                            'Maximum $maxGuests friends allowed.',
                          );
                          return;
                        }
                        if (_selectedDate == null || _selectedTime == null) {
                          _showValidationError('Please select Date and Time.');
                          return;
                        }

                        final selectedDateTime = DateTime(
                          _selectedDate!.year,
                          _selectedDate!.month,
                          _selectedDate!.day,
                          _selectedTime!.hour,
                          _selectedTime!.minute,
                        );
                        if (selectedDateTime.isBefore(DateTime.now())) {
                          _showValidationError(
                            'Selected date and time cannot be in the past.',
                          );
                          return;
                        }

                        final invalidReason = widget.venue.getInvalidReason(
                          _selectedDate!,
                          _selectedTime!,
                        );
                        if (invalidReason != null) {
                          _showValidationError(invalidReason);
                          return;
                        }

                        final mobileNum = _mobileController.text.trim();
                        final phoneRegex = RegExp(r'^\d{10}$');
                        if (mobileNum.isEmpty) {
                          _showValidationError('Mobile number is required.');
                          return;
                        }
                        if (!phoneRegex.hasMatch(mobileNum)) {
                          _showValidationError(
                            'Please enter a valid 10-digit mobile number.',
                          );
                          return;
                        }

                        final optMobileNum = _optMobileController.text.trim();
                        if (optMobileNum.isNotEmpty &&
                            !phoneRegex.hasMatch(optMobileNum)) {
                          _showValidationError(
                            'Please enter a valid 10-digit alternate mobile number.',
                          );
                          return;
                        }

                        if (_noOfFriends > 20) {
                          if (_partySubjectController.text.trim().isEmpty) {
                            _showValidationError('Party Subject is required.');
                            return;
                          }
                          if (_partyRequirementController.text.trim().isEmpty) {
                            _showValidationError(
                              'Party Requirement is required.',
                            );
                            return;
                          }

                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => const Center(
                              child: CircularProgressIndicator(
                                color: LunaraTheme.electricViolet,
                              ),
                            ),
                          );

                          bool success = false;
                          String errorMsg =
                              'Failed to submit request. Please try again later.';
                          try {
                            success = await ApiService.submitLargePartyRequest(
                              venueId: widget.venue.id,
                              date:
                                  '${_selectedDate!.year}-${_selectedDate!.month.toString().padLeft(2, '0')}-${_selectedDate!.day.toString().padLeft(2, '0')}',
                              time:
                                  '${_selectedTime!.hour.toString().padLeft(2, '0')}:${_selectedTime!.minute.toString().padLeft(2, '0')}',
                              guests: parsed,
                              subject: _partySubjectController.text,
                              requirement: _partyRequirementController.text,
                              description: _partyDescriptionController.text,
                              mobileNumber: _mobileController.text.trim(),
                              optionalMobileNumber:
                                  _optMobileController.text.trim().isEmpty
                                  ? null
                                  : _optMobileController.text.trim(),
                            );
                          } catch (e) {
                            success = false;
                            final eStr = e.toString();
                            if (eStr.startsWith('Exception: ')) {
                              errorMsg = eStr.substring(11);
                            } else {
                              errorMsg = eStr;
                            }
                          }

                          if (!context.mounted) return;
                          Navigator.pop(context); // Close loading dialog

                          if (!success) {
                            _showValidationError(errorMsg);
                            return;
                          }

                          Navigator.pop(context); // close bottom sheet

                          showDialog(
                            context: context,
                            builder: (ctx2) => AlertDialog(
                              title: const Text('Request Submitted'),
                              content: const Text(
                                'Your large party request has been submitted to the admin for approval. You will see it in your Live Feed once approved.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.pop(ctx2); // close dialog
                                  },
                                  child: const Text('OK'),
                                ),
                              ],
                            ),
                          );
                          return;
                        }

                        setState(() {
                          _noOfFriends = parsed;
                        });

                        final hour = _selectedTime!.hour % 12 == 0
                            ? 12
                            : _selectedTime!.hour % 12;
                        final min = _selectedTime!.minute.toString().padLeft(
                          2,
                          '0',
                        );
                        final ampm = _selectedTime!.hour >= 12 ? 'PM' : 'AM';
                        final formattedTime = '$hour:$min $ampm';

                        final parentContext = context;
                        final partyDateStr = selectedDateTime.toIso8601String();

                        if (totalPrice <= 0) {
                          // Free Group Party Instant Confirmation
                          showDialog(
                            context: context,
                            barrierDismissible: false,
                            builder: (ctx) => const Center(
                              child: CircularProgressIndicator(
                                color: LunaraTheme.electricViolet,
                              ),
                            ),
                          );

                          final result = await ApiService.createGroupParty(
                            venueId: widget.venue.id,
                            numberOfFriends: parsed,
                            partyDate: partyDateStr,
                            startTime: formattedTime,
                            mobileNumber: _mobileController.text.trim(),
                            optionalMobileNumber: _optMobileController.text.trim().isEmpty
                                ? null
                                : _optMobileController.text.trim(),
                            foodPreference: _foodPreference,
                            drinkPreference: _drinkPreference,
                          );

                          // Close loading dialog safely
                          if (mounted) {
                            Navigator.of(context, rootNavigator: true).pop();
                          }
                          // Close booking bottom sheet
                          if (mounted) {
                            Navigator.pop(context);
                          }

                          if (result != null && result['success'] == true) {
                            final groupPartyId = (result['data'] is Map)
                                ? result['data']['id']?.toString()
                                : result['id']?.toString();

                            TopNotificationBanner.show(
                              title: 'Group Party Confirmed! 🎉',
                              body: 'Your free group party at ${widget.venue.name} is confirmed!',
                              data: {'type': 'group_party_confirmed', 'partyId': groupPartyId},
                            );

                            final navContext = widget.rootContext.mounted ? widget.rootContext : parentContext;
                            Navigator.push(
                              navContext,
                              MaterialPageRoute(
                                builder: (_) => LargePartyTicketScreen(
                                  booking: {
                                    'id': groupPartyId,
                                    'bookingId': groupPartyId,
                                    'bookingDate': partyDateStr,
                                    'partyDate': partyDateStr,
                                    'startTime': formattedTime,
                                    'status': 'confirmed',
                                    'paymentStatus': 'paid',
                                    'venue': widget.venue.toMap(),
                                    'venueName': widget.venue.name,
                                    'numberOfGuests': parsed,
                                    'partySubject': 'Group Party',
                                    'totalAmount': 0,
                                  },
                                  venue: widget.venue.toMap(),
                                ),
                              ),
                            );
                          } else {
                            final String errorMsg =
                                result?['message'] ?? 'Failed to initiate booking. Please try again.';
                            _showValidationError(errorMsg, errorData: result);
                          }
                          return;
                        }

                        // Paid Group Party Flow - Open Smart Checkout directly on rootContext
                        Navigator.pop(context); // Close the booking parameters bottom sheet

                        String? createdGroupPartyId;
                        final rootContext = widget.rootContext;

                        final bool? sheetSuccess = await SmartCheckoutSheet.show(
                          context: rootContext,
                          title: widget.venue.name,
                          subtitle: 'Group Party Booking ($parsed Friends)',
                          itemPrice: totalPrice,
                          onWalletPayment: () async {
                            final result = await ApiService.createGroupParty(
                              venueId: widget.venue.id,
                              numberOfFriends: parsed,
                              partyDate: partyDateStr,
                              startTime: formattedTime,
                              mobileNumber: _mobileController.text.trim(),
                              optionalMobileNumber: _optMobileController.text.trim().isEmpty
                                  ? null
                                  : _optMobileController.text.trim(),
                              foodPreference: _foodPreference,
                              drinkPreference: _drinkPreference,
                            );

                            if (result == null || result['success'] != true) {
                              if (rootContext.mounted) {
                                final isTimeLock = (result != null &&
                                        (result['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
                                            result['conflictingEventType'] != null)) ||
                                    (result?['message']?.toString().contains('4 hours') == true);
                                if (isTimeLock) {
                                  final payload = Map<String, dynamic>.from(result ?? {});
                                  if (!payload.containsKey('conflictingEventTitle')) {
                                    payload['conflictingEventTitle'] = widget.venue.name;
                                  }
                                  TimeLockBlockedDialog.show(rootContext, errorData: payload);
                                } else {
                                  ScaffoldMessenger.of(rootContext).showSnackBar(
                                    SnackBar(
                                      content: Text(result?['message'] ?? 'Failed to initiate group party booking'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                              return false;
                            }

                            createdGroupPartyId = (result['data'] is Map)
                                ? (result['data']['id']?.toString() ?? '')
                                : (result['id']?.toString() ?? '');

                            final walletRes = await ApiService.payWithWallet(
                              amount: totalPrice,
                              planId: createdGroupPartyId,
                              bookingId: createdGroupPartyId,
                              paymentType: 'group_party',
                            );

                            if (walletRes != null && walletRes['success'] == true) {
                              final transactionId = walletRes['data']?['transactionId']?.toString() ?? 'wallet';
                              final verifySuccess = await ApiService.verifyGroupPartyPayment(
                                razorpayOrderId: 'order_mock_wallet',
                                razorpayPaymentId: 'wallet_$transactionId',
                                razorpaySignature: 'mock_signature',
                                partyId: createdGroupPartyId,
                              );

                              if (verifySuccess) {
                                return true;
                              }
                            }

                            // Cleanup pending attempt on failure
                            if (createdGroupPartyId != null && createdGroupPartyId!.isNotEmpty) {
                              await ApiService.cancelPendingGroupParty(createdGroupPartyId!);
                              createdGroupPartyId = null;
                            }

                            if (rootContext.mounted) {
                              ScaffoldMessenger.of(rootContext).showSnackBar(
                                SnackBar(
                                  content: Text(walletRes?['message'] ?? 'Wallet payment failed'),
                                  backgroundColor: Colors.redAccent,
                                ),
                              );
                            }
                            return false;
                          },
                          onDirectPayment: () async {
                            final result = await ApiService.createGroupParty(
                              venueId: widget.venue.id,
                              numberOfFriends: parsed,
                              partyDate: partyDateStr,
                              startTime: formattedTime,
                              mobileNumber: _mobileController.text.trim(),
                              optionalMobileNumber: _optMobileController.text.trim().isEmpty
                                  ? null
                                  : _optMobileController.text.trim(),
                              foodPreference: _foodPreference,
                              drinkPreference: _drinkPreference,
                            );

                            if (result == null || result['success'] != true) {
                              if (rootContext.mounted) {
                                final isTimeLock = (result != null &&
                                        (result['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
                                            result['conflictingEventType'] != null)) ||
                                    (result?['message']?.toString().contains('4 hours') == true);
                                if (isTimeLock) {
                                  final payload = Map<String, dynamic>.from(result ?? {});
                                  if (!payload.containsKey('conflictingEventTitle')) {
                                    payload['conflictingEventTitle'] = widget.venue.name;
                                  }
                                  TimeLockBlockedDialog.show(rootContext, errorData: payload);
                                } else {
                                  ScaffoldMessenger.of(rootContext).showSnackBar(
                                    SnackBar(
                                      content: Text(result?['message'] ?? 'Failed to initiate group party'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                              return false;
                            }

                            final orderId = result['razorpayOrderId']?.toString() ?? '';
                            final amountInPaise = (result['amount'] is int && (result['amount'] as int) > 0)
                                ? result['amount'] as int
                                : (totalPrice * 100).round();
                            final keyId = result['razorpayKeyId']?.toString() ?? 'rzp_test_T1rwVokR7tFger';
                            createdGroupPartyId = (result['data'] is Map)
                                ? (result['data']['id']?.toString() ?? '')
                                : (result['id']?.toString() ?? '');

                            if (kIsWeb) {
                              final success = await ApiService.verifyGroupPartyPayment(
                                razorpayOrderId: orderId.isNotEmpty ? orderId : 'order_mock_direct',
                                razorpayPaymentId: 'pay_direct_${DateTime.now().millisecondsSinceEpoch}',
                                razorpaySignature: 'mock_signature',
                                partyId: createdGroupPartyId,
                              );
                              if (success) {
                                TopNotificationBanner.show(
                                  title: 'Group Party Confirmed! 🎉',
                                  body: 'Your payment was verified successfully. Digital ticket generated!',
                                  data: {'type': 'group_party_confirmed', 'partyId': createdGroupPartyId},
                                );
                                if (rootContext.mounted) {
                                  Navigator.push(
                                    rootContext,
                                    MaterialPageRoute(
                                      builder: (_) => LargePartyTicketScreen(
                                        booking: {
                                          'id': createdGroupPartyId,
                                          'bookingId': createdGroupPartyId,
                                          'bookingDate': partyDateStr,
                                          'partyDate': partyDateStr,
                                          'startTime': formattedTime,
                                          'status': 'confirmed',
                                          'paymentStatus': 'paid',
                                          'venue': widget.venue.toMap(),
                                          'venueName': widget.venue.name,
                                          'numberOfGuests': parsed,
                                          'partySubject': 'Group Party',
                                          'totalAmount': totalPrice,
                                        },
                                        venue: widget.venue.toMap(),
                                      ),
                                    ),
                                  );
                                }
                                return true;
                              }
                              return false;
                            }

                            final rzp = Razorpay();
                            rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
                              try { rzp.clear(); } catch (_) {}

                              if (rootContext.mounted) {
                                showDialog(
                                  context: rootContext,
                                  barrierDismissible: false,
                                  builder: (ctx) => const Center(
                                    child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
                                  ),
                                );
                              }

                              try {
                                final success = await ApiService.verifyGroupPartyPayment(
                                  razorpayOrderId: response.orderId ?? orderId,
                                  razorpayPaymentId: response.paymentId ?? 'mock_payment',
                                  razorpaySignature: response.signature ?? 'mock_signature',
                                  partyId: createdGroupPartyId,
                                );

                                if (rootContext.mounted) {
                                  Navigator.of(rootContext, rootNavigator: true).pop();
                                }

                                if (success) {
                                  TopNotificationBanner.show(
                                    title: 'Group Party Confirmed! 🎉',
                                    body: 'Your payment was verified successfully. Digital ticket generated!',
                                    data: {'type': 'group_party_confirmed', 'partyId': createdGroupPartyId},
                                  );
                                  if (rootContext.mounted) {
                                    Navigator.push(
                                      rootContext,
                                      MaterialPageRoute(
                                        builder: (_) => LargePartyTicketScreen(
                                          booking: {
                                            'id': createdGroupPartyId,
                                            'bookingId': createdGroupPartyId,
                                            'bookingDate': partyDateStr,
                                            'partyDate': partyDateStr,
                                            'startTime': formattedTime,
                                            'status': 'confirmed',
                                            'paymentStatus': 'paid',
                                            'venue': widget.venue.toMap(),
                                            'venueName': widget.venue.name,
                                            'numberOfGuests': parsed,
                                            'partySubject': 'Group Party',
                                            'totalAmount': totalPrice,
                                          },
                                          venue: widget.venue.toMap(),
                                        ),
                                      ),
                                    );
                                  }
                                } else {
                                  if (createdGroupPartyId != null && createdGroupPartyId!.isNotEmpty) {
                                    await ApiService.cancelPendingGroupParty(createdGroupPartyId!);
                                    createdGroupPartyId = null;
                                  }
                                  if (rootContext.mounted) {
                                    ScaffoldMessenger.of(rootContext).showSnackBar(
                                      const SnackBar(
                                        content: Text('Payment verification failed. Group party booking could not be confirmed.'),
                                        backgroundColor: Colors.redAccent,
                                      ),
                                    );
                                  }
                                }
                              } catch (e) {
                                debugPrint('verifyGroupPartyPayment error: $e');
                                if (rootContext.mounted) {
                                  Navigator.of(rootContext, rootNavigator: true).pop();
                                }
                                if (createdGroupPartyId != null && createdGroupPartyId!.isNotEmpty) {
                                  await ApiService.cancelPendingGroupParty(createdGroupPartyId!);
                                  createdGroupPartyId = null;
                                }
                                if (rootContext.mounted) {
                                  ScaffoldMessenger.of(rootContext).showSnackBar(
                                    SnackBar(
                                      content: Text('Payment verification error: $e'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            });

                            rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) async {
                              try { rzp.clear(); } catch (_) {}
                              if (createdGroupPartyId != null && createdGroupPartyId!.isNotEmpty) {
                                await ApiService.cancelPendingGroupParty(createdGroupPartyId!);
                                createdGroupPartyId = null;
                              }
                              if (rootContext.mounted) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(
                                  SnackBar(
                                    content: Text('Payment cancelled: ${response.message ?? "Payment was interrupted"}'),
                                    backgroundColor: Colors.black87,
                                  ),
                                );
                              }
                            });

                            rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
                              try { rzp.clear(); } catch (_) {}
                              debugPrint('External wallet selected: ${response.walletName}');
                            });

                            final options = {
                              'key': keyId.isNotEmpty ? keyId : 'rzp_test_T1rwVokR7tFger',
                              'amount': amountInPaise,
                              'name': 'Lunara – Group Party',
                              'description': 'Group Party for $parsed Friends at ${widget.venue.name}',
                              if (orderId.isNotEmpty && !orderId.startsWith('order_mock_')) 'order_id': orderId,
                              'prefill': {
                                'contact': _mobileController.text.trim().isNotEmpty
                                    ? _mobileController.text.trim()
                                    : '9999999999',
                                'email': 'party@lunara.com',
                              },
                              'theme': {'color': '#7F00FF'},
                            };

                            try {
                              rzp.open(options);
                              return true;
                            } catch (e) {
                              debugPrint('Razorpay open error: $e');
                              if (createdGroupPartyId != null && createdGroupPartyId!.isNotEmpty) {
                                await ApiService.cancelPendingGroupParty(createdGroupPartyId!);
                                createdGroupPartyId = null;
                              }
                              if (rootContext.mounted) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(
                                  SnackBar(
                                    content: Text('Could not open payment gateway: $e'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                              return false;
                            }
                          },
                          onHybridPayment: (shortfallAmount) async {
                            final orderData = await ApiService.createWalletRechargeOrder(shortfallAmount);
                            if (orderData == null) {
                              if (rootContext.mounted) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to initiate wallet recharge. Please try again.'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                              return false;
                            }

                            final String rzpOrderId = orderData['orderId'] ?? orderData['id'] ?? '';
                            final rzpKey = orderData['keyId']?.toString() ?? 'rzp_test_T1rwVokR7tFger';

                            if (kIsWeb) {
                              final recharged = await ApiService.verifyWalletRecharge(
                                amount: shortfallAmount,
                                razorpayOrderId: rzpOrderId.isNotEmpty ? rzpOrderId : 'order_mock_recharge',
                                razorpayPaymentId: 'pay_mock_${DateTime.now().millisecondsSinceEpoch}',
                                razorpaySignature: 'mock_sig',
                              );
                              if (recharged) {
                                final result = await ApiService.createGroupParty(
                                  venueId: widget.venue.id,
                                  numberOfFriends: parsed,
                                  partyDate: partyDateStr,
                                  startTime: formattedTime,
                                  mobileNumber: _mobileController.text.trim(),
                                  optionalMobileNumber: _optMobileController.text.trim().isEmpty
                                      ? null
                                      : _optMobileController.text.trim(),
                                  foodPreference: _foodPreference,
                                  drinkPreference: _drinkPreference,
                                );
                                createdGroupPartyId = (result != null && result['data'] is Map)
                                    ? (result['data']['id']?.toString() ?? '')
                                    : (result?['id']?.toString() ?? '');

                                final walletRes = await ApiService.payWithWallet(
                                  amount: totalPrice,
                                  planId: createdGroupPartyId,
                                  bookingId: createdGroupPartyId,
                                  paymentType: 'group_party',
                                );
                                if (walletRes != null && walletRes['success'] == true) {
                                  final transactionId = walletRes['data']?['transactionId']?.toString() ?? 'wallet';
                                  await ApiService.verifyGroupPartyPayment(
                                    razorpayOrderId: 'order_mock_wallet',
                                    razorpayPaymentId: 'wallet_$transactionId',
                                    razorpaySignature: 'mock_signature',
                                    partyId: createdGroupPartyId,
                                  );
                                  TopNotificationBanner.show(
                                    title: 'Group Party Confirmed! 🎉',
                                    body: 'Your payment was verified successfully. Digital ticket generated!',
                                    data: {'type': 'group_party_confirmed', 'partyId': createdGroupPartyId},
                                  );
                                  if (rootContext.mounted) {
                                    Navigator.push(
                                      rootContext,
                                      MaterialPageRoute(
                                        builder: (_) => LargePartyTicketScreen(
                                          booking: {
                                            'id': createdGroupPartyId,
                                            'bookingId': createdGroupPartyId,
                                            'bookingDate': partyDateStr,
                                            'partyDate': partyDateStr,
                                            'startTime': formattedTime,
                                            'status': 'confirmed',
                                            'paymentStatus': 'paid',
                                            'venue': widget.venue.toMap(),
                                            'venueName': widget.venue.name,
                                            'numberOfGuests': parsed,
                                            'partySubject': 'Group Party',
                                            'totalAmount': totalPrice,
                                          },
                                          venue: widget.venue.toMap(),
                                        ),
                                      ),
                                    );
                                  }
                                  return true;
                                }
                              }
                              return false;
                            }

                            final rzp = Razorpay();
                            rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
                              try { rzp.clear(); } catch (_) {}

                              if (rootContext.mounted) {
                                showDialog(
                                  context: rootContext,
                                  barrierDismissible: false,
                                  builder: (ctx) => const Center(
                                    child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
                                  ),
                                );
                              }

                              try {
                                final recharged = await ApiService.verifyWalletRecharge(
                                  amount: shortfallAmount,
                                  razorpayOrderId: response.orderId ?? rzpOrderId,
                                  razorpayPaymentId: response.paymentId ?? 'mock_pay',
                                  razorpaySignature: response.signature ?? 'mock_sig',
                                );
                                if (recharged) {
                                  final result = await ApiService.createGroupParty(
                                    venueId: widget.venue.id,
                                    numberOfFriends: parsed,
                                    partyDate: partyDateStr,
                                    startTime: formattedTime,
                                    mobileNumber: _mobileController.text.trim(),
                                    optionalMobileNumber: _optMobileController.text.trim().isEmpty
                                        ? null
                                        : _optMobileController.text.trim(),
                                    foodPreference: _foodPreference,
                                    drinkPreference: _drinkPreference,
                                  );
                                  createdGroupPartyId = (result != null && result['data'] is Map)
                                      ? (result['data']['id']?.toString() ?? '')
                                      : (result?['id']?.toString() ?? '');

                                  final walletRes = await ApiService.payWithWallet(
                                    amount: totalPrice,
                                    planId: createdGroupPartyId,
                                    bookingId: createdGroupPartyId,
                                    paymentType: 'group_party',
                                  );
                                  if (walletRes != null && walletRes['success'] == true) {
                                    final transactionId = walletRes['data']?['transactionId']?.toString() ?? 'wallet';
                                    await ApiService.verifyGroupPartyPayment(
                                      razorpayOrderId: 'order_mock_wallet',
                                      razorpayPaymentId: 'wallet_$transactionId',
                                      razorpaySignature: 'mock_signature',
                                      partyId: createdGroupPartyId,
                                    );

                                    if (rootContext.mounted) {
                                      Navigator.of(rootContext, rootNavigator: true).pop();
                                    }

                                    TopNotificationBanner.show(
                                      title: 'Group Party Confirmed! 🎉',
                                      body: 'Your payment was verified successfully. Digital ticket generated!',
                                      data: {'type': 'group_party_confirmed', 'partyId': createdGroupPartyId},
                                    );
                                    if (rootContext.mounted) {
                                      Navigator.push(
                                        rootContext,
                                        MaterialPageRoute(
                                          builder: (_) => LargePartyTicketScreen(
                                            booking: {
                                              'id': createdGroupPartyId,
                                              'bookingId': createdGroupPartyId,
                                              'bookingDate': partyDateStr,
                                              'partyDate': partyDateStr,
                                              'startTime': formattedTime,
                                              'status': 'confirmed',
                                              'paymentStatus': 'paid',
                                              'venue': widget.venue.toMap(),
                                              'venueName': widget.venue.name,
                                              'numberOfGuests': parsed,
                                              'partySubject': 'Group Party',
                                              'totalAmount': totalPrice,
                                            },
                                            venue: widget.venue.toMap(),
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  }
                                }

                                if (rootContext.mounted) {
                                  Navigator.of(rootContext, rootNavigator: true).pop();
                                }
                                if (createdGroupPartyId != null && createdGroupPartyId!.isNotEmpty) {
                                  await ApiService.cancelPendingGroupParty(createdGroupPartyId!);
                                  createdGroupPartyId = null;
                                }
                                if (rootContext.mounted) {
                                  ScaffoldMessenger.of(rootContext).showSnackBar(
                                    const SnackBar(
                                      content: Text('Hybrid payment failed during party completion.'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (rootContext.mounted) {
                                  Navigator.of(rootContext, rootNavigator: true).pop();
                                }
                                if (createdGroupPartyId != null && createdGroupPartyId!.isNotEmpty) {
                                  await ApiService.cancelPendingGroupParty(createdGroupPartyId!);
                                  createdGroupPartyId = null;
                                }
                                if (rootContext.mounted) {
                                  ScaffoldMessenger.of(rootContext).showSnackBar(
                                    SnackBar(
                                      content: Text('Hybrid payment error: $e'),
                                      backgroundColor: Colors.redAccent,
                                    ),
                                  );
                                }
                              }
                            });

                            rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) async {
                              try { rzp.clear(); } catch (_) {}
                              if (createdGroupPartyId != null && createdGroupPartyId!.isNotEmpty) {
                                await ApiService.cancelPendingGroupParty(createdGroupPartyId!);
                                createdGroupPartyId = null;
                              }
                              if (rootContext.mounted) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(
                                  SnackBar(content: Text('Recharge cancelled: ${response.message ?? "Payment was interrupted"}')),
                                );
                              }
                            });

                            rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
                              try { rzp.clear(); } catch (_) {}
                            });

                            final rechargeOptions = {
                              'key': rzpKey.isNotEmpty ? rzpKey : 'rzp_test_T1rwVokR7tFger',
                              'amount': (shortfallAmount * 100).round(),
                              'name': 'Lunara Wallet Recharge',
                              'description': 'Recharge ₹${shortfallAmount.toStringAsFixed(0)} for Group Party Booking',
                              if (rzpOrderId.isNotEmpty && !rzpOrderId.startsWith('order_mock_')) 'order_id': rzpOrderId,
                              'prefill': {
                                'contact': _mobileController.text.trim().isNotEmpty
                                    ? _mobileController.text.trim()
                                    : '9999999999',
                                'email': 'party@lunara.com',
                              },
                              'theme': {'color': '#7F00FF'},
                            };

                            try {
                              rzp.open(rechargeOptions);
                              return true;
                            } catch (e) {
                              debugPrint('Recharge Razorpay open error: $e');
                              if (rootContext.mounted) {
                                ScaffoldMessenger.of(rootContext).showSnackBar(
                                  SnackBar(
                                    content: Text('Could not open recharge gateway: $e'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                              return false;
                            }
                          },
                        );

                        if (sheetSuccess == true && createdGroupPartyId != null && createdGroupPartyId!.isNotEmpty) {
                          TopNotificationBanner.show(
                            title: 'Group Party Confirmed! 🎉',
                            body: 'Your payment was verified successfully. Digital ticket generated!',
                            data: {'type': 'group_party_confirmed', 'partyId': createdGroupPartyId},
                          );
                          if (rootContext.mounted) {
                            Navigator.pushReplacement(
                              rootContext,
                              MaterialPageRoute(
                                builder: (_) => LargePartyTicketScreen(
                                  booking: {
                                    'id': createdGroupPartyId,
                                    'bookingId': createdGroupPartyId,
                                    'bookingDate': partyDateStr,
                                    'partyDate': partyDateStr,
                                    'startTime': formattedTime,
                                    'status': 'confirmed',
                                    'paymentStatus': 'paid',
                                    'venue': widget.venue.toMap(),
                                    'venueName': widget.venue.name,
                                    'numberOfGuests': parsed,
                                    'partySubject': 'Group Party',
                                    'totalAmount': totalPrice,
                                  },
                                  venue: widget.venue.toMap(),
                                ),
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: LunaraTheme.electricViolet,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _noOfFriends > 20
                            ? 'SUBMIT REQUEST'
                            : (totalPrice <= 0
                                ? 'CONFIRM FREE BOOKING'
                                : 'PROCEED TO PAYMENT'),
                        style: const TextStyle(
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
    String? overrideText,
  }) {
    final String formattedText = overrideText ??
        (amount == 0 && !isDiscount
            ? 'FREE'
            : '${amount < 0 ? "-" : ""}₹ ${amount.abs().toStringAsFixed(0)}');

    final Color textColor = isDiscount || (amount == 0 && !isTotal)
        ? const Color(0xFF10B981)
        : (isTotal ? LunaraTheme.electricViolet : Colors.black);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: isTotal ? 16 : 14,
                    fontWeight: isTotal ? FontWeight.bold : FontWeight.w600,
                    color: isTotal ? Colors.black : Colors.black87,
                  ),
                  overflow: TextOverflow.ellipsis,
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
        ),
        const SizedBox(width: 8),
        Text(
          formattedText,
          style: TextStyle(
            fontSize: isTotal ? 20 : 16,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
      ],
    );
  }
}
