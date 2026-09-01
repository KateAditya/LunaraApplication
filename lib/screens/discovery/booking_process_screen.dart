import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../core/theme.dart';
import '../../widgets/action_button.dart';
import '../../widgets/smart_checkout_sheet.dart';
import '../../widgets/top_notification_banner.dart';
import 'digital_ticket_screen.dart';
import '../../services/api_service.dart';
import '../../models/venue.dart';
import '../../widgets/venue_timing_error_dialog.dart';
import 'night_partner_discovery_screen.dart';
import 'night_invite_partner_screen.dart';
import '../../widgets/venue_cover_charge_notice.dart';
import '../../widgets/time_lock_modal.dart';
import '../../widgets/dialogs/time_lock_blocked_dialog.dart';

class BookingProcessScreen extends StatefulWidget {
  final Map<dynamic, dynamic> venue;
  final bool isUpcomingNight;
  final String? upcomingNightDate;
  final String? upcomingNightTime;

  const BookingProcessScreen({
    super.key,
    required this.venue,
    this.isUpcomingNight = false,
    this.upcomingNightDate,
    this.upcomingNightTime,
  });

  @override
  State<BookingProcessScreen> createState() => _BookingProcessScreenState();
}

class _BookingProcessScreenState extends State<BookingProcessScreen> {
  late DateTime _selectedDate;
  String? _selectedTime;
  bool _isGoingSolo = true;
  final TextEditingController _guestsController = TextEditingController();
  final TextEditingController _partySubjectController = TextEditingController();
  final TextEditingController _partyRequirementController =
      TextEditingController();
  final TextEditingController _partyDescriptionController =
      TextEditingController();
  final TextEditingController _partyMobileController = TextEditingController();
  final TextEditingController _partyOptMobileController =
      TextEditingController();
  final TextEditingController _dateController = TextEditingController();

  bool _isVenueOpenOnDate(DateTime date) {
    final closedDates = widget.venue['closedDates'];
    if (closedDates != null && closedDates is List) {
      final yyyy = date.year;
      final mm = date.month.toString().padLeft(2, '0');
      final dd = date.day.toString().padLeft(2, '0');
      final dateStr = '$yyyy-$mm-$dd';
      if (closedDates.contains(dateStr)) {
        return false;
      }
    }

    final daysOpen = widget.venue['daysOpen'];
    if (daysOpen == null || daysOpen is! List || daysOpen.isEmpty) {
      return true; // default to open
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
    if (weekdayName == null) return false;

    return daysOpen.any((d) {
      final str = d.toString().trim().toLowerCase();
      final fullDay = weekdayName.toLowerCase();
      final shortDay = weekdayName.substring(0, 3).toLowerCase();
      return str.contains(fullDay) || str.contains(shortDay);
    });
  }

  bool _isTimeWithinVenueHours(
    TimeOfDay time,
    String? openingStr,
    String? closingStr,
  ) {
    if (openingStr == null ||
        openingStr.isEmpty ||
        closingStr == null ||
        closingStr.isEmpty) {
      return true; // no timing constraint
    }

    final openParts = openingStr.split(':');
    if (openParts.length < 2) return true;
    final openHour = int.tryParse(openParts[0]) ?? 0;
    final openMin = int.tryParse(openParts[1]) ?? 0;

    final closeParts = closingStr.split(':');
    if (closeParts.length < 2) return true;
    final closeHour = int.tryParse(closeParts[0]) ?? 0;
    final closeMin = int.tryParse(closeParts[1]) ?? 0;

    final selectedMinutes = time.hour * 60 + time.minute;
    final openMinutes = openHour * 60 + openMin;
    final closeMinutes = closeHour * 60 + closeMin;

    if (closeMinutes < openMinutes) {
      // Overlap past midnight, e.g. 12:00 PM to 01:30 AM next day
      return selectedMinutes >= openMinutes || selectedMinutes <= closeMinutes;
    } else {
      // Normal hours, e.g. 10:00 AM to 11:00 PM
      return selectedMinutes >= openMinutes && selectedMinutes <= closeMinutes;
    }
  }

  bool _isTimeSlotValid(TimeOfDay time) {
    final venueObj = Venue.fromJson(Map<String, dynamic>.from(widget.venue));
    if (!_isTimeWithinVenueHours(
      time,
      venueObj.openingTime,
      venueObj.closingTime,
    )) {
      return false;
    }
    final selectedDateTime = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      time.hour,
      time.minute,
    );
    final minAllowedDateTime = DateTime.now().add(const Duration(hours: 1));
    if (selectedDateTime.isBefore(minAllowedDateTime)) {
      return false;
    }
    return true;
  }

  DateTime? _parseDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return null;
    try {
      return DateTime.parse(dateStr);
    } catch (_) {}
    try {
      final clean = dateStr.toUpperCase();
      final monthsList = [
        'JAN',
        'FEB',
        'MAR',
        'APR',
        'MAY',
        'JUN',
        'JUL',
        'AUG',
        'SEP',
        'OCT',
        'NOV',
        'DEC',
      ];
      int? foundMonth;
      for (int i = 0; i < monthsList.length; i++) {
        if (clean.contains(monthsList[i])) {
          foundMonth = i + 1;
          break;
        }
      }
      if (foundMonth != null) {
        final dayRegex = RegExp(r'\b(\d{1,2})\b');
        final dayMatch = dayRegex.firstMatch(clean);
        if (dayMatch != null) {
          final day = int.parse(dayMatch.group(1)!);
          final yearRegex = RegExp(r'\b(20\d{2})\b');
          final yearMatch = yearRegex.firstMatch(clean);
          final year = yearMatch != null
              ? int.parse(yearMatch.group(1)!)
              : DateTime.now().year;
          return DateTime(year, foundMonth, day);
        }
      }
    } catch (_) {}
    try {
      final clean = dateStr.replaceAll('/', '-');
      final parts = clean.split('-');
      if (parts.length == 3) {
        if (parts[0].length == 4) {
          return DateTime(
            int.parse(parts[0]),
            int.parse(parts[1]),
            int.parse(parts[2]),
          );
        } else {
          return DateTime(
            int.parse(parts[2]),
            int.parse(parts[1]),
            int.parse(parts[0]),
          );
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void initState() {
    super.initState();
    _guestsController.text = '1';

    if (widget.isUpcomingNight) {
      final parsedDate = _parseDate(widget.upcomingNightDate);
      if (parsedDate != null) {
        _selectedDate = parsedDate;
      } else {
        DateTime initialDate = DateTime.now();
        for (int i = 0; i < 7; i++) {
          final d = DateTime.now().add(Duration(days: i));
          if (_isVenueOpenOnDate(d)) {
            initialDate = d;
            break;
          }
        }
        _selectedDate = initialDate;
      }

      if (widget.upcomingNightTime != null &&
          widget.upcomingNightTime!.isNotEmpty) {
        String timeStr = widget.upcomingNightTime!;
        if (timeStr.toUpperCase().contains('PM') ||
            timeStr.toUpperCase().contains('AM')) {
          final clean = timeStr.toUpperCase();
          final isPm = clean.contains('PM');
          final timeOnly = clean
              .replaceAll('AM', '')
              .replaceAll('PM', '')
              .trim();
          final parts = timeOnly.split(':');
          if (parts.isNotEmpty) {
            int h = int.tryParse(parts[0]) ?? 20;
            int m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
            if (isPm && h < 12) h += 12;
            if (!isPm && h == 12) h = 0;
            _selectedTime =
                '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
          }
        } else {
          _selectedTime = timeStr;
        }
      } else {
        _selectedTime = '20:00';
      }
    } else {
      DateTime initialDate = DateTime.now();
      for (int i = 0; i < 7; i++) {
        final d = DateTime.now().add(Duration(days: i));
        if (_isVenueOpenOnDate(d)) {
          initialDate = d;
          break;
        }
      }
      _selectedDate = initialDate;

      final venueObj = Venue.fromJson(Map<String, dynamic>.from(widget.venue));

      String? defaultTime;
      final openingStr = venueObj.openingTime;
      if (openingStr != null && openingStr.contains(':')) {
        final parts = openingStr.split(':');
        final hour = int.tryParse(parts[0]) ?? 20;
        final minute = int.tryParse(parts[1]) ?? 0;
        final tod = TimeOfDay(hour: hour, minute: minute);

        final selectedDateTime = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          _selectedDate.day,
          tod.hour,
          tod.minute,
        );
        final minAllowedDateTime = DateTime.now().add(const Duration(hours: 1));
        if (_isTimeWithinVenueHours(
              tod,
              venueObj.openingTime,
              venueObj.closingTime,
            ) &&
            !selectedDateTime.isBefore(minAllowedDateTime)) {
          defaultTime =
              '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';
        }
      }

      if (defaultTime == null) {
        final predefinedTimes = [
          const TimeOfDay(hour: 20, minute: 0),
          const TimeOfDay(hour: 21, minute: 0),
          const TimeOfDay(hour: 22, minute: 0),
          const TimeOfDay(hour: 23, minute: 0),
          const TimeOfDay(hour: 0, minute: 0),
          const TimeOfDay(hour: 19, minute: 0),
        ];

        for (final tod in predefinedTimes) {
          final selectedDateTime = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
            tod.hour,
            tod.minute,
          );
          final minAllowedDateTime = DateTime.now().add(
            const Duration(hours: 1),
          );

          if (_isTimeWithinVenueHours(
                tod,
                venueObj.openingTime,
                venueObj.closingTime,
              ) &&
              !selectedDateTime.isBefore(minAllowedDateTime)) {
            defaultTime =
                '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';
            break;
          }
        }
      }

      _selectedTime = defaultTime ?? '21:00';
    }
    _updateDateControllerText();
  }

  void _updateDateControllerText() {
    if (_selectedTime != null) {
      final formattedTime = _formatTimeOfBooking(_selectedTime);
      _dateController.text =
          "${DateFormat('MMM dd, yyyy').format(_selectedDate)} at $formattedTime";
    } else {
      _dateController.text = DateFormat('MMM dd, yyyy').format(_selectedDate);
    }
  }

  Future<void> _handleDateSelection(DateTime date) async {
    final venueObj = Venue.fromJson(Map<String, dynamic>.from(widget.venue));
    TimeOfDay? time;
    if (_selectedTime != null) {
      final parts = _selectedTime!.split(':');
      if (parts.length >= 2) {
        time = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 20,
          minute: int.tryParse(parts[1]) ?? 0,
        );
      }
    }
    time ??= const TimeOfDay(hour: 20, minute: 0);

    if (!_isTimeSlotValid(time)) {
      if (!mounted) return;
      VenueTimingErrorDialog.show(
        context,
        venueName: venueObj.name,
        daysOpen: venueObj.daysOpen,
        openingTime: venueObj.openingTime,
        closingTime: venueObj.closingTime,
        closedDates: venueObj.closedDates,
      );
      return;
    }

    setState(() {
      _selectedDate = date;
      _updateDateControllerText();
    });
  }

  Future<void> _handleCustomDateSelection() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );

    if (date != null) {
      await _handleDateSelection(date);
    }
  }

  @override
  void dispose() {
    _guestsController.dispose();
    _partySubjectController.dispose();
    _partyRequirementController.dispose();
    _partyDescriptionController.dispose();
    _partyMobileController.dispose();
    _partyOptMobileController.dispose();
    _dateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildProgressBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    if (widget.isUpcomingNight) ...[
                      _buildUpcomingNightCard(),
                      const SizedBox(height: 32),
                    ] else ...[
                      _buildDateSelection(),
                      const SizedBox(height: 32),
                      _buildTimeSelection(),
                      const SizedBox(height: 32),
                    ],
                    const Text(
                      'CHOOSE MODE',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                        color: Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _isGoingSolo = true);
                            },
                            child: _buildModeBox(
                              title: 'Going solo',
                              subtitle: 'Table for yourself',
                              icon: Icons.person_rounded,
                              isSelected: _isGoingSolo,
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() => _isGoingSolo = false);
                            },
                            child: _buildModeBox(
                              title: 'With Friends',
                              subtitle: 'Party for group',
                              icon: Icons.group_rounded,
                              isSelected: !_isGoingSolo,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!_isGoingSolo && widget.isUpcomingNight) ...[
                      const SizedBox(height: 28),
                      const Text(
                        'HOW DO YOU WANT TO PLAN YOUR NIGHT?',
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
                            child: GestureDetector(
                              onTap: () {
                                final yyyy = _selectedDate.year;
                                final mm = _selectedDate.month
                                    .toString()
                                    .padLeft(2, '0');
                                final dd = _selectedDate.day.toString().padLeft(
                                  2,
                                  '0',
                                );
                                final dateStr = '$yyyy-$mm-$dd';
                                final timeStr = _selectedTime ?? '20:00';

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NightInvitePartnerScreen(
                                      venue: widget.venue,
                                      date: dateStr,
                                      time: timeStr,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0x1A7F00FF),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: LunaraTheme.electricViolet
                                            .withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.person_add_rounded,
                                        color: LunaraTheme.electricViolet,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Invite Partner',
                                      style: TextStyle(
                                        fontFamily: 'AllroundGothic',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Invite someone you already know',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                final venueId =
                                    widget.venue['id']?.toString() ?? '';
                                final yyyy = _selectedDate.year;
                                final mm = _selectedDate.month
                                    .toString()
                                    .padLeft(2, '0');
                                final dd = _selectedDate.day.toString().padLeft(
                                  2,
                                  '0',
                                );
                                final dateStr = '$yyyy-$mm-$dd';
                                final timeStr = _selectedTime ?? '20:00';

                                // Mark interest authoritatively
                                await ApiService.markNightInterested(
                                  venueId: venueId,
                                  date: dateStr,
                                  time: timeStr,
                                );

                                if (!context.mounted) return;

                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => NightPartnerDiscoveryScreen(
                                      venue: widget.venue,
                                      date: dateStr,
                                      time: timeStr,
                                    ),
                                  ),
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFF3EEFF),
                                      Color(0xFFF8F4FF),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: LunaraTheme.electricViolet
                                        .withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: LunaraTheme.electricViolet,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.favorite_rounded,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Find Partner',
                                      style: TextStyle(
                                        fontFamily: 'AllroundGothic',
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: LunaraTheme.electricViolet,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Find members interested in this night',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[700],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    const VenueCoverChargeNoticeCard(),
                    const SizedBox(height: 20),
                    LunaraActionButton(
                      text: 'BOOK NOW',
                      onPressed: () {
                        _showBookingPopup(context, isSolo: _isGoingSolo);
                      },
                    ),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getFormattedSelectedDate() {
    final List<String> months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final List<String> weekdays = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];
    final weekday = weekdays[_selectedDate.weekday - 1];
    final month = months[_selectedDate.month - 1];
    return '$weekday, ${_selectedDate.day} $month';
  }

  Widget _buildUpcomingNightCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LunaraTheme.electricViolet.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.calendar_today_rounded,
              color: LunaraTheme.electricViolet,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'UPCOMING NIGHT DETECTED',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: LunaraTheme.electricViolet,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_getFormattedSelectedDate()} at ${_formatTimeOfBooking(_selectedTime)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              'BOOKING: ${widget.venue['name']}',
              style: LunaraTheme.headingStyle.copyWith(
                fontSize: 16,
                color: Colors.black,
                fontWeight: FontWeight.w900,
                letterSpacing: 2,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Row(
        children: [
          Expanded(child: _progressSegment(active: true)),
          const SizedBox(width: 8),
          Expanded(child: _progressSegment(active: _selectedTime != null)),
          const SizedBox(width: 8),
          Expanded(child: _progressSegment(active: false)),
        ],
      ),
    );
  }

  Widget _progressSegment({required bool active}) {
    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: active ? LunaraTheme.electricViolet : Colors.grey[200],
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Going Solo Box
  // ─────────────────────────────────────────────────────────

  Widget _buildModeBox({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isSelected
            ? LunaraTheme.electricViolet.withValues(alpha: 0.05)
            : Colors.grey[50],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isSelected ? LunaraTheme.electricViolet : Colors.grey[200]!,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isSelected
                  ? LunaraTheme.electricViolet.withValues(alpha: 0.1)
                  : Colors.grey[200],
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isSelected ? LunaraTheme.electricViolet : Colors.grey[500],
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: isSelected ? LunaraTheme.electricViolet : Colors.black,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
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
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: LunaraTheme.electricViolet),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Date Selection
  // ─────────────────────────────────────────────────────────

  Widget _buildDateSelection() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    final List<DateTime> dynamicDates = [];
    DateTime checkDate = today;
    while (dynamicDates.length < 6) {
      if (_isVenueOpenOnDate(checkDate)) {
        dynamicDates.add(checkDate);
      }
      checkDate = checkDate.add(const Duration(days: 1));
    }

    Widget buildDateChip(String label, DateTime dateVal, bool isSelected) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _selectedDate = dateVal;
            _updateDateControllerText();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? LunaraTheme.electricViolet : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? LunaraTheme.electricViolet
                  : Colors.grey[300]!,
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
            color: isSelected ? LunaraTheme.electricViolet : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? LunaraTheme.electricViolet
                  : Colors.grey[300]!,
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
                !dynamicDates.any(
                      (d) =>
                          d.year == _selectedDate.year &&
                          d.month == _selectedDate.month &&
                          d.day == _selectedDate.day,
                    )
                    ? DateFormat('MMM d').format(_selectedDate)
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SELECT DATE',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 16),
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
                    _selectedDate.year == dateVal.year &&
                    _selectedDate.month == dateVal.month &&
                    _selectedDate.day == dateVal.day;

                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: buildDateChip(label, dateVal, isSelected),
                );
              }),
              buildCustomChip(
                !dynamicDates.any(
                  (d) =>
                      d.year == _selectedDate.year &&
                      d.month == _selectedDate.month &&
                      d.day == _selectedDate.day,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────
  //  Time Selection
  // ─────────────────────────────────────────────────────────

  Widget _buildTimeSelection() {
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

    Widget buildTimeChip(String label, TimeOfDay tod, bool isSelected) {
      return GestureDetector(
        onTap: () {
          setState(() {
            _selectedTime =
                '${tod.hour.toString().padLeft(2, '0')}:${tod.minute.toString().padLeft(2, '0')}';
            _updateDateControllerText();
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? LunaraTheme.electricViolet : Colors.grey[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? LunaraTheme.electricViolet
                  : Colors.grey[300]!,
              width: 1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black87,
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
      final parts = _selectedTime!.split(':');
      if (parts.length >= 2) {
        final selHour = int.tryParse(parts[0]) ?? -1;
        final selMin = int.tryParse(parts[1]) ?? -1;
        isCustomSelected = !validTimes.any(
          (t) => t.hour == selHour && t.minute == selMin,
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SELECT TIME SLOT',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: [
              ...validTimes.map((tod) {
                final label = formatTimeOfDay(tod);
                final parts = _selectedTime?.split(':');
                final isSelected =
                    parts != null &&
                    parts.length >= 2 &&
                    int.tryParse(parts[0]) == tod.hour &&
                    int.tryParse(parts[1]) == tod.minute;

                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: buildTimeChip(label, tod, isSelected),
                );
              }),
              GestureDetector(
                onTap: () async {
                  final TimeOfDay? picked = await showTimePicker(
                    context: context,
                    initialTime: const TimeOfDay(hour: 22, minute: 0),
                    builder: (context, child) {
                      return Theme(
                        data: ThemeData.light().copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: LunaraTheme.electricViolet,
                            onPrimary: Colors.white,
                            surface: Colors.white,
                            onSurface: Colors.black,
                          ),
                          timePickerTheme: TimePickerThemeData(
                            backgroundColor: Colors.white,
                            dialHandColor: LunaraTheme.electricViolet,
                            dialBackgroundColor: Colors.grey[100],
                            hourMinuteTextColor: Colors.black,
                            dayPeriodTextColor: Colors.black,
                            entryModeIconColor: LunaraTheme.electricViolet,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) {
                    if (!mounted) return;
                    if (!_isTimeSlotValid(picked)) {
                      final venueObj = Venue.fromJson(
                        Map<String, dynamic>.from(widget.venue),
                      );
                      VenueTimingErrorDialog.show(
                        context,
                        venueName: venueObj.name,
                        daysOpen: venueObj.daysOpen,
                        openingTime: venueObj.openingTime,
                        closingTime: venueObj.closingTime,
                        closedDates: venueObj.closedDates,
                      );
                      return;
                    }
                    setState(() {
                      _selectedTime =
                          '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                      _updateDateControllerText();
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
                        ? LunaraTheme.electricViolet
                        : Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isCustomSelected
                          ? LunaraTheme.electricViolet
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
                        color: isCustomSelected ? Colors.white : Colors.black87,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isCustomSelected
                            ? _formatTimeOfBooking(_selectedTime)
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
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: () {
            _handleCustomDateSelection();
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
                  hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
                  prefixIcon: const Icon(
                    Icons.calendar_today_rounded,
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
          ),
        ),
      ],
    );
  }

  String _formatTimeOfBooking(String? timeStr) {
    if (timeStr == null) return '10:30 PM';
    try {
      final parts = timeStr.split(':');
      if (parts.length == 2) {
        final hour = int.parse(parts[0]);
        final minute = int.parse(parts[1]);
        final ampm = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour % 12 == 0 ? 12 : hour % 12;
        final displayMinute = minute.toString().padLeft(2, '0');
        return '$displayHour:$displayMinute $ampm';
      }
    } catch (_) {}
    return timeStr;
  }

  void _showBookingPopup(BuildContext outerContext, {required bool isSolo}) {
    if (_selectedTime == null) {
      ScaffoldMessenger.of(outerContext).showSnackBar(
        const SnackBar(content: Text('Please select a time slot first.')),
      );
      return;
    }

    if (isSolo) {
      _guestsController.text = '1';
    } else if (_guestsController.text.isEmpty ||
        _guestsController.text == '1') {
      _guestsController.text = '2'; // Default for friends
    }

    bool isSubmittingBooking = false;

    showModalBottomSheet(
      context: outerContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext bottomSheetCtx) {
        return StatefulBuilder(
          builder: (BuildContext modalCtx, StateSetter setModalState) {
            int guests = int.tryParse(_guestsController.text) ?? 1;
            bool isLargeParty = !isSolo && guests > 20;

            final double rawTableCharge =
                double.tryParse(
                  widget.venue['tableBookingCharges']?.toString() ??
                      widget.venue['table_booking_charges']?.toString() ??
                      widget.venue['pricePerHead']?.toString() ??
                      widget.venue['price_per_head']?.toString() ??
                      '0',
                ) ??
                0.0;
            final double basePrice = rawTableCharge >= 0 ? rawTableCharge : 0.0;
            final double subtotal = basePrice * (isSolo ? 1 : guests);
            final double discountPercent =
                double.tryParse(
                  widget.venue['discountPercentage']?.toString() ??
                      widget.venue['discount_percentage']?.toString() ??
                      '0',
                ) ??
                0.0;
            final double discountAmount = (subtotal * discountPercent) / 100;
            final double totalPrice = (subtotal - discountAmount) < 0
                ? 0.0
                : (subtotal - discountAmount);
            final bool isFreeBooking = totalPrice <= 0;

            return Container(
              margin: EdgeInsets.only(
                top: MediaQuery.of(outerContext).padding.top + 40,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(outerContext).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 8,
                          left: 16,
                          right: 8,
                          bottom: 8,
                        ),
                        child: Column(
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Colors.grey[300],
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'BOOKING AT ${widget.venue['name'].toString().toUpperCase()}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close),
                                  onPressed: () =>
                                      Navigator.pop(bottomSheetCtx),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Divider(height: 1, color: Colors.grey[200]),

                      Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isSolo) ...[
                              const Text(
                                'NUMBER OF FRIENDS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.grey[50],
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.grey[200]!),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.group,
                                      color: LunaraTheme.electricViolet,
                                    ),
                                    const Spacer(),
                                    GestureDetector(
                                      onTap: () {
                                        if (guests > 2) {
                                          setModalState(() {
                                            _guestsController.text =
                                                (guests - 1).toString();
                                          });
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey[300]!,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.remove,
                                          size: 20,
                                          color: LunaraTheme.electricViolet,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    SizedBox(
                                      width: 32,
                                      child: Text(
                                        guests.toString(),
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    GestureDetector(
                                      onTap: () {
                                        final int maxGuests =
                                            int.tryParse(
                                              widget.venue['capacity']
                                                      ?.toString() ??
                                                  '20',
                                            ) ??
                                            20;
                                        if (guests < maxGuests) {
                                          setModalState(() {
                                            _guestsController.text =
                                                (guests + 1).toString();
                                          });
                                        } else {
                                          ScaffoldMessenger.of(
                                            outerContext,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Maximum $maxGuests friends allowed.',
                                              ),
                                            ),
                                          );
                                        }
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          border: Border.all(
                                            color: Colors.grey[300]!,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.add,
                                          size: 20,
                                          color: LunaraTheme.electricViolet,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),
                            ],

                            if (isLargeParty) ...[
                              Container(
                                margin: const EdgeInsets.only(bottom: 20),
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      LunaraTheme.electricViolet.withValues(
                                        alpha: 0.08,
                                      ),
                                      LunaraTheme.electricViolet.withValues(
                                        alpha: 0.03,
                                      ),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: LunaraTheme.electricViolet
                                        .withValues(alpha: 0.2),
                                    width: 1.5,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: LunaraTheme.electricViolet
                                            .withValues(alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.verified_user_rounded,
                                        color: LunaraTheme.electricViolet,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'LARGE GROUP BOOKING (21+)',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 12,
                                              color: LunaraTheme.electricViolet,
                                              letterSpacing: 1,
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          const Text(
                                            'Please fill out the details below. Our team will review and confirm your booking request within 1-5 hours.',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.black87,
                                              height: 1.4,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Text(
                                'LARGE PARTY DETAILS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: LunaraTheme.electricViolet,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _partySubjectController,
                                decoration: _inputDecoration('Party Subject *'),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _partyRequirementController,
                                decoration: _inputDecoration(
                                  'Party Requirement *',
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _partyDescriptionController,
                                maxLines: 3,
                                decoration: _inputDecoration(
                                  'Description (optional)',
                                ),
                              ),
                              const SizedBox(height: 12),
                              // ── Contact Details ─────────────────────
                              const Text(
                                'CONTACT DETAILS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _partyMobileController,
                                keyboardType: TextInputType.phone,
                                decoration: _inputDecoration('Mobile Number *')
                                    .copyWith(
                                      prefixIcon: const Icon(
                                        Icons.phone_rounded,
                                        color: LunaraTheme.electricViolet,
                                        size: 20,
                                      ),
                                    ),
                              ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _partyOptMobileController,
                                keyboardType: TextInputType.phone,
                                decoration:
                                    _inputDecoration(
                                      'Additional Mobile (optional)',
                                    ).copyWith(
                                      prefixIcon: const Icon(
                                        Icons.phone_android_rounded,
                                        color: LunaraTheme.electricViolet,
                                        size: 20,
                                      ),
                                    ),
                              ),
                              const SizedBox(height: 32),
                            ],

                            if (!isLargeParty) ...[
                              const VenueCoverChargeNoticeCard(),
                              const SizedBox(height: 16),
                              const Text(
                                'PRICING DETAILS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black54,
                                  letterSpacing: 1,
                                ),
                              ),

                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: LunaraTheme.electricViolet.withValues(
                                    alpha: 0.05,
                                  ),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: LunaraTheme.electricViolet
                                        .withValues(alpha: 0.1),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Table Booking Charges (${isSolo ? '1' : guests})',
                                          style: const TextStyle(
                                            color: Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          '₹ ${subtotal.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'Discount (${discountPercent.toStringAsFixed(0)}%)',
                                          style: const TextStyle(
                                            color: Colors.black87,
                                          ),
                                        ),
                                        Text(
                                          '₹ ${discountAmount.toStringAsFixed(0)}',
                                          style: const TextStyle(
                                            color: Colors.teal,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Divider(height: 1, color: Colors.grey[300]),
                                    const SizedBox(height: 12),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Total Amount',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          isFreeBooking
                                              ? 'FREE (₹0)'
                                              : '₹ ${totalPrice.toStringAsFixed(0)}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: isFreeBooking
                                                ? Colors.teal
                                                : LunaraTheme.electricViolet,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 32),
                            ],

                            LunaraActionButton(
                              text: isSubmittingBooking
                                  ? 'PROCESSING...'
                                  : (isLargeParty
                                      ? 'SUBMIT REQUEST'
                                      : (isFreeBooking
                                            ? 'BOOK NOW — IT\'S FREE!'
                                            : 'PROCEED TO PAYMENT')),
                              onPressed: isSubmittingBooking
                                  ? null
                                  : () async {
                                if (isSubmittingBooking) return;
                                setModalState(() => isSubmittingBooking = true);

                                try {
                                if (isLargeParty) {
                                  if (_partySubjectController.text
                                          .trim()
                                          .isEmpty ||
                                      _partyRequirementController.text
                                          .trim()
                                          .isEmpty) {
                                    setModalState(() => isSubmittingBooking = false);
                                    ScaffoldMessenger.of(
                                      outerContext,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please fill out the party subject and requirement.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  if (_partyMobileController.text
                                      .trim()
                                      .isEmpty) {
                                    setModalState(() => isSubmittingBooking = false);
                                    ScaffoldMessenger.of(
                                      outerContext,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Mobile number is required for a large party request.',
                                        ),
                                        backgroundColor: Colors.red,
                                      ),
                                    );
                                    return;
                                  }

                                  Navigator.pop(bottomSheetCtx); // Close popup

                                  // Show loading snackbar
                                  ScaffoldMessenger.of(
                                    outerContext,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text('Submitting request...'),
                                    ),
                                  );

                                  bool success = false;
                                  try {
                                    success = await ApiService.submitLargePartyRequest(
                                      venueId: widget.venue['id'],
                                      date:
                                          '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                                      time: _selectedTime!,
                                      guests: guests,
                                      subject: _partySubjectController.text,
                                      requirement:
                                          _partyRequirementController.text,
                                      description:
                                          _partyDescriptionController.text,
                                      mobileNumber: _partyMobileController
                                          .text
                                          .trim(),
                                      optionalMobileNumber:
                                          _partyOptMobileController.text
                                              .trim()
                                              .isEmpty
                                          ? null
                                          : _partyOptMobileController.text
                                                .trim(),
                                    );
                                  } catch (e) {
                                    final eStr = e.toString();
                                    final isTimeLock = eStr.contains('FOUR_HOUR_TIME_LOCK') ||
                                        eStr.contains('4 hours') ||
                                        eStr.contains('already have a');
                                    if (isTimeLock) {
                                      if (!outerContext.mounted) return;
                                      TimeLockBlockedDialog.show(outerContext, errorData: {
                                        'message': eStr.replaceFirst('Exception: ', ''),
                                        'conflictingEventTitle': widget.venue['name']?.toString() ?? 'Venue',
                                      });
                                      return;
                                    }
                                    if (!outerContext.mounted) return;
                                    ScaffoldMessenger.of(
                                      outerContext,
                                    ).showSnackBar(
                                      SnackBar(
                                        content: Text(eStr.replaceFirst('Exception: ', '')),
                                      ),
                                    );
                                    return;
                                  }

                                  if (!success) {
                                    if (!outerContext.mounted) return;
                                    ScaffoldMessenger.of(
                                      outerContext,
                                    ).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Failed to submit request. Please try again later.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }

                                  if (!outerContext.mounted) return;

                                  showDialog(
                                    context: outerContext,
                                    builder: (ctx2) => AlertDialog(
                                      title: const Text('Request Submitted'),
                                      content: const Text(
                                        'Your large party request has been successfully submitted. Our team will review and confirm your booking within 1-5 hours.',
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () {
                                            Navigator.pop(ctx2); // close dialog
                                            if (mounted) {
                                              Navigator.pop(
                                                outerContext,
                                              ); // Go back from booking process screen
                                            }
                                          },
                                          child: const Text('OK'),
                                        ),
                                      ],
                                    ),
                                  );
                                  return;
                                }

                                if (isFreeBooking) {
                                  showDialog(
                                    context: outerContext,
                                    barrierDismissible: false,
                                    builder: (ctx) => const Center(
                                      child: CircularProgressIndicator(
                                        color: LunaraTheme.electricViolet,
                                      ),
                                    ),
                                  );

                                  final bookingRes = await ApiService.createBooking(
                                    venueId: widget.venue['id']?.toString() ?? '',
                                    bookingDate:
                                        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                                    startTime: _selectedTime ?? '22:00',
                                    tablePackage: isSolo ? 'Solo Entry' : 'Confirmation Charges',
                                    goingMode: isSolo ? 'solo' : 'party_request',
                                    numberOfGuests: isSolo ? 1 : guests,
                                    isUpcomingNight: widget.isUpcomingNight,
                                  );

                                  if (outerContext.mounted) {
                                    Navigator.of(outerContext, rootNavigator: true).pop(); // close loader
                                  }

                                  if (bookingRes != null && bookingRes['success'] == true) {
                                    if (bottomSheetCtx.mounted) {
                                      Navigator.pop(bottomSheetCtx);
                                    }
                                    final data = bookingRes['data'];
                                    final createdBookingId = (data != null
                                        ? (data['id'] ?? data['bookingId'])
                                        : bookingRes['bookingId'])?.toString() ?? 'FREE_TICKET';

                                    TopNotificationBanner.show(
                                      title: 'Booking Confirmed! 🎉',
                                      body: 'Your complimentary booking at ${widget.venue['name'] ?? 'Venue'} is confirmed!',
                                      data: {'type': 'booking_confirmed', 'bookingId': createdBookingId},
                                    );

                                    if (outerContext.mounted) {
                                      Navigator.push(
                                        outerContext,
                                        MaterialPageRoute(
                                          builder: (_) => DigitalTicketScreen(
                                            venue: widget.venue,
                                            date:
                                                '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                            package: isSolo ? 'Solo Entry' : 'Free Entry Ticket',
                                            time: _formatTimeOfBooking(
                                              _selectedTime,
                                            ),
                                            table: isSolo ? 'Solo Entry' : 'Standard Table',
                                            guests: isSolo ? '1' : '$guests',
                                            totalPrice: 'FREE (₹0)',
                                            ticketId: createdBookingId,
                                            user: ApiService.cachedCurrentUser,
                                            booking: {
                                              'id': createdBookingId,
                                              'bookingId': createdBookingId,
                                              'venue': widget.venue,
                                              'venueId': widget.venue['id'],
                                              'isSolo': isSolo,
                                              'goingMode': isSolo ? 'solo' : 'party_request',
                                              'bookingType': isSolo ? 'solo' : 'venue_booking',
                                              'category': isSolo ? 'solo' : 'venue_booking',
                                              'totalAmount': 0,
                                              'paymentStatus': 'paid',
                                              'status': 'CONFIRMED',
                                              'tablePackage': isSolo ? 'Solo Entry' : 'Standard Table',
                                              'numberOfGuests': isSolo ? 1 : guests,
                                              'bookingDate': _selectedDate.toIso8601String(),
                                              'startTime': _formatTimeOfBooking(_selectedTime),
                                              'user': ApiService.cachedCurrentUser,
                                            },
                                          ),
                                        ),
                                      );
                                    }
                                    return;
                                  } else if (bookingRes != null &&
                                      (bookingRes['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
                                          bookingRes['conflictingEventType'] != null ||
                                          bookingRes['message']?.toString().contains('4 hours') == true)) {
                                    if (!outerContext.mounted) return;
                                    final payload = Map<String, dynamic>.from(bookingRes);
                                    if (!payload.containsKey('conflictingEventTitle')) {
                                      payload['conflictingEventTitle'] = widget.venue['name']?.toString() ?? 'Venue';
                                    }
                                    TimeLockBlockedDialog.show(outerContext, errorData: payload);
                                    return;
                                  } else if (bookingRes != null &&
                                      const [
                                        'PLAN_TIME_LOCKED',
                                        'PLAN_DAILY_LIMIT_REACHED',
                                        'PLAN_ACTIVE_LIMIT_REACHED',
                                        'PLAN_WEEKLY_LIMIT_REACHED',
                                      ].contains(bookingRes['code'])) {
                                    if (!outerContext.mounted) return;
                                    TimeLockModal.show(
                                      context: outerContext,
                                      reasonCode: bookingRes['code'].toString(),
                                      message:
                                          bookingRes['message'] ??
                                          'Please wait before booking again.',
                                      remainingSeconds:
                                          bookingRes['lock']?['remainingSeconds'] ??
                                          60,
                                      existingPlanId:
                                          bookingRes['lock']?['existingPlanId']
                                              ?.toString(),
                                      existingPlanType:
                                          bookingRes['lock']?['existingPlanType']
                                              ?.toString(),
                                    );
                                    return;
                                  } else {
                                    if (!outerContext.mounted) return;
                                    final errMsg =
                                        bookingRes?['message']?.toString() ??
                                        'Failed to create booking.';
                                    ScaffoldMessenger.of(
                                      outerContext,
                                    ).showSnackBar(
                                      SnackBar(content: Text(errMsg), backgroundColor: Colors.redAccent),
                                    );
                                    return;
                                  }
                                }

                                String? createdBookingId;
                                final bookingDateStr =
                                    '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
                                final formattedTime = _formatTimeOfBooking(_selectedTime);

                                await SmartCheckoutSheet.show(
                                  context: outerContext,
                                  title: widget.venue['name']?.toString() ?? 'Venue',
                                  subtitle: isSolo
                                      ? 'Solo Table Booking'
                                      : 'Table Booking ($guests Guests)',
                                  itemPrice: totalPrice,
                                  onWalletPayment: () async {
                                    final bookingRes = await ApiService.createBooking(
                                      venueId: widget.venue['id']?.toString() ?? '',
                                      bookingDate: bookingDateStr,
                                      startTime: _selectedTime ?? '22:00',
                                      tablePackage: isSolo ? 'Solo Entry' : 'Confirmation Charges',
                                      goingMode: isSolo ? 'solo' : 'party_request',
                                      numberOfGuests: isSolo ? 1 : guests,
                                      isUpcomingNight: widget.isUpcomingNight,
                                    );

                                    if (bookingRes == null || bookingRes['success'] != true) {
                                      if (outerContext.mounted) {
                                        final isTimeLock = (bookingRes != null &&
                                                (bookingRes['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
                                                    bookingRes['conflictingEventType'] != null)) ||
                                            (bookingRes?['message']?.toString().contains('4 hours') == true);
                                        if (isTimeLock) {
                                          final payload = Map<String, dynamic>.from(bookingRes ?? {});
                                          if (!payload.containsKey('conflictingEventTitle')) {
                                            payload['conflictingEventTitle'] = widget.venue['name']?.toString() ?? 'Venue';
                                          }
                                          TimeLockBlockedDialog.show(outerContext, errorData: payload);
                                        } else {
                                          ScaffoldMessenger.of(outerContext).showSnackBar(
                                            SnackBar(
                                              content: Text(bookingRes?['message'] ?? 'Failed to initiate booking'),
                                              backgroundColor: Colors.redAccent,
                                            ),
                                          );
                                        }
                                      }
                                      return false;
                                    }

                                    createdBookingId = (bookingRes['data'] is Map)
                                        ? (bookingRes['data']['id']?.toString() ?? bookingRes['data']['bookingId']?.toString() ?? '')
                                        : (bookingRes['bookingId']?.toString() ?? '');

                                    if (createdBookingId == null || createdBookingId!.isEmpty) {
                                      return false;
                                    }

                                    final walletRes = await ApiService.payWithWallet(
                                      amount: totalPrice,
                                      bookingId: createdBookingId,
                                      paymentType: 'booking_payment',
                                    );

                                    if (walletRes != null && walletRes['success'] == true) {
                                      final transactionId = walletRes['data']?['transactionId']?.toString() ?? 'wallet';
                                      final payNowRes = await ApiService.payNowBooking(
                                        createdBookingId!,
                                        paymentMethod: 'WALLET',
                                        transactionId: transactionId,
                                      );

                                      if (payNowRes != null && payNowRes['success'] == true) {
                                        if (outerContext.mounted) {
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            if (!outerContext.mounted) return;
                                            TopNotificationBanner.show(
                                              title: 'Booking Confirmed! 🎉',
                                              body: 'Your payment was verified successfully. Digital ticket generated!',
                                              data: {'type': 'booking_confirmed', 'bookingId': createdBookingId},
                                            );
                                            Navigator.push(
                                              outerContext,
                                              MaterialPageRoute(
                                                builder: (_) => DigitalTicketScreen(
                                                  venue: widget.venue,
                                                  date: '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                                  package: isSolo ? 'Solo Entry' : 'Standard Table',
                                                  time: formattedTime,
                                                  table: isSolo ? 'Solo Entry' : 'Standard Table',
                                                  guests: isSolo ? '1' : '$guests',
                                                  totalPrice: '₹${totalPrice.toStringAsFixed(0)}',
                                                  ticketId: createdBookingId,
                                                  user: ApiService.cachedCurrentUser,
                                                  booking: {
                                                    'id': createdBookingId,
                                                    'bookingId': createdBookingId,
                                                    'venue': widget.venue,
                                                    'venueId': widget.venue['id'],
                                                    'isSolo': isSolo,
                                                    'goingMode': isSolo ? 'solo' : 'party_request',
                                                    'bookingType': isSolo ? 'solo' : 'venue_booking',
                                                    'category': isSolo ? 'solo' : 'venue_booking',
                                                    'totalAmount': totalPrice,
                                                    'paymentStatus': 'paid',
                                                    'paymentMethod': 'Lunara Wallet',
                                                    'status': 'CONFIRMED',
                                                    'tablePackage': isSolo ? 'Solo Entry' : 'Standard Table',
                                                    'numberOfGuests': isSolo ? 1 : guests,
                                                    'bookingDate': _selectedDate.toIso8601String(),
                                                    'startTime': formattedTime,
                                                    'user': ApiService.cachedCurrentUser,
                                                  },
                                                ),
                                              ),
                                            );
                                          });
                                        }
                                        return true;
                                      }
                                    }

                                    if (createdBookingId != null && createdBookingId!.isNotEmpty) {
                                      await ApiService.cancelPendingBooking(createdBookingId!);
                                      createdBookingId = null;
                                    }
                                    if (outerContext.mounted) {
                                      ScaffoldMessenger.of(outerContext).showSnackBar(
                                        SnackBar(
                                          content: Text(walletRes?['message'] ?? 'Wallet payment failed'),
                                          backgroundColor: Colors.redAccent,
                                        ),
                                      );
                                    }
                                    return false;
                                  },
                                  onDirectPayment: () async {
                                    final bookingRes = await ApiService.createBooking(
                                      venueId: widget.venue['id']?.toString() ?? '',
                                      bookingDate: bookingDateStr,
                                      startTime: _selectedTime ?? '22:00',
                                      tablePackage: isSolo ? 'Solo Entry' : 'Confirmation Charges',
                                      goingMode: isSolo ? 'solo' : 'party_request',
                                      numberOfGuests: isSolo ? 1 : guests,
                                      isUpcomingNight: widget.isUpcomingNight,
                                    );

                                    if (bookingRes == null || bookingRes['success'] != true) {
                                      if (outerContext.mounted) {
                                        final isTimeLock = (bookingRes != null &&
                                                (bookingRes['reason'] == 'FOUR_HOUR_TIME_LOCK' ||
                                                    bookingRes['conflictingEventType'] != null)) ||
                                            (bookingRes?['message']?.toString().contains('4 hours') == true);
                                        if (isTimeLock) {
                                          final payload = Map<String, dynamic>.from(bookingRes ?? {});
                                          if (!payload.containsKey('conflictingEventTitle')) {
                                            payload['conflictingEventTitle'] = widget.venue['name']?.toString() ?? 'Venue';
                                          }
                                          TimeLockBlockedDialog.show(outerContext, errorData: payload);
                                        } else {
                                          ScaffoldMessenger.of(outerContext).showSnackBar(
                                            SnackBar(
                                              content: Text(bookingRes?['message'] ?? 'Failed to initiate booking'),
                                              backgroundColor: Colors.redAccent,
                                            ),
                                          );
                                        }
                                      }
                                      return false;
                                    }

                                    final orderId = bookingRes['razorpayOrderId']?.toString() ?? '';
                                    final amountInPaise = (bookingRes['amount'] is int && (bookingRes['amount'] as int) > 0)
                                        ? bookingRes['amount'] as int
                                        : (totalPrice * 100).round();
                                    final keyId = bookingRes['razorpayKeyId']?.toString() ?? 'rzp_test_T1rwVokR7tFger';
                                    createdBookingId = (bookingRes['data'] is Map)
                                        ? (bookingRes['data']['id']?.toString() ?? bookingRes['data']['bookingId']?.toString() ?? '')
                                        : (bookingRes['bookingId']?.toString() ?? '');

                                    if (kIsWeb) {
                                      if (!outerContext.mounted) return false;
                                      // Explicit Web Payment Confirmation Dialog
                                      final bool? confirmed = await showDialog<bool>(
                                        context: outerContext,
                                        barrierDismissible: false,
                                        builder: (dialogCtx) => AlertDialog(
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          title: Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.all(8),
                                                decoration: BoxDecoration(
                                                  color: LunaraTheme.electricViolet.withValues(alpha: 0.1),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(Icons.payment_rounded, color: LunaraTheme.electricViolet, size: 22),
                                              ),
                                              const SizedBox(width: 12),
                                              const Text('Confirm Payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                            ],
                                          ),
                                          content: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text('Venue: ${widget.venue['name'] ?? 'Venue'}', style: const TextStyle(fontWeight: FontWeight.w600)),
                                              const SizedBox(height: 4),
                                              Text('Date & Time: ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year} • $formattedTime'),
                                              const SizedBox(height: 4),
                                              Text('Guests: ${isSolo ? '1 (Solo)' : '$guests Guests'}'),
                                              const Divider(height: 24),
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  const Text('Total Amount:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                                  Text('₹${totalPrice.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: LunaraTheme.electricViolet)),
                                                ],
                                              ),
                                              const SizedBox(height: 12),
                                              const Text('Complete payment to generate and secure your digital ticket.', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                            ],
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(dialogCtx).pop(false),
                                              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                                            ),
                                            ElevatedButton(
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: LunaraTheme.electricViolet,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                              ),
                                              onPressed: () => Navigator.of(dialogCtx).pop(true),
                                              child: const Text('Pay & Confirm', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirmed != true) {
                                        if (createdBookingId != null && createdBookingId!.isNotEmpty) {
                                          await ApiService.cancelPendingBooking(createdBookingId!);
                                          createdBookingId = null;
                                        }
                                        return false;
                                      }

                                      final payNowRes = await ApiService.payNowBooking(
                                        createdBookingId!,
                                        paymentMethod: 'UPI',
                                        razorpayOrderId: orderId.isNotEmpty ? orderId : 'order_web_${DateTime.now().millisecondsSinceEpoch}',
                                        razorpayPaymentId: 'pay_web_${DateTime.now().millisecondsSinceEpoch}',
                                        razorpaySignature: 'web_signature_${DateTime.now().millisecondsSinceEpoch}',
                                      );
                                      if (payNowRes != null && payNowRes['success'] == true) {
                                        TopNotificationBanner.show(
                                          title: 'Booking Confirmed! 🎉',
                                          body: 'Your payment was verified successfully. Digital ticket generated!',
                                          data: {'type': 'booking_confirmed', 'bookingId': createdBookingId},
                                        );
                                        if (outerContext.mounted) {
                                          Navigator.push(
                                            outerContext,
                                            MaterialPageRoute(
                                              builder: (_) => DigitalTicketScreen(
                                                venue: widget.venue,
                                                date: '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                                package: isSolo ? 'Solo Entry' : 'Standard Table',
                                                time: formattedTime,
                                                table: isSolo ? 'Solo Entry' : 'Standard Table',
                                                guests: isSolo ? '1' : '$guests',
                                                totalPrice: '₹${totalPrice.toStringAsFixed(0)}',
                                                ticketId: createdBookingId,
                                                user: ApiService.cachedCurrentUser,
                                                booking: {
                                                  'id': createdBookingId,
                                                  'bookingId': createdBookingId,
                                                  'venue': widget.venue,
                                                  'venueId': widget.venue['id'],
                                                  'isSolo': isSolo,
                                                  'goingMode': isSolo ? 'solo' : 'party_request',
                                                  'bookingType': isSolo ? 'solo' : 'venue_booking',
                                                  'category': isSolo ? 'solo' : 'venue_booking',
                                                  'totalAmount': totalPrice,
                                                  'paymentStatus': 'paid',
                                                  'paymentMethod': 'UPI / Net Banking',
                                                  'status': 'CONFIRMED',
                                                  'tablePackage': isSolo ? 'Solo Entry' : 'Standard Table',
                                                  'numberOfGuests': isSolo ? 1 : guests,
                                                  'bookingDate': _selectedDate.toIso8601String(),
                                                  'startTime': formattedTime,
                                                  'user': ApiService.cachedCurrentUser,
                                                },
                                              ),
                                            ),
                                          );
                                        }
                                        return true;
                                      } else {
                                        if (createdBookingId != null && createdBookingId!.isNotEmpty) {
                                          await ApiService.cancelPendingBooking(createdBookingId!);
                                          createdBookingId = null;
                                        }
                                        return false;
                                      }
                                    }

                                    final rzp = Razorpay();
                                    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
                                      try { rzp.clear(); } catch (_) {}

                                      if (outerContext.mounted) {
                                        showDialog(
                                          context: outerContext,
                                          barrierDismissible: false,
                                          builder: (ctx) => const Center(
                                            child: CircularProgressIndicator(color: LunaraTheme.electricViolet),
                                          ),
                                        );
                                      }

                                      try {
                                        final payNowRes = await ApiService.payNowBooking(
                                          createdBookingId!,
                                          paymentMethod: 'CARD',
                                          razorpayOrderId: response.orderId ?? orderId,
                                          razorpayPaymentId: response.paymentId ?? 'mock_payment',
                                          razorpaySignature: response.signature ?? 'mock_signature',
                                        );

                                        if (outerContext.mounted) {
                                          Navigator.of(outerContext, rootNavigator: true).pop();
                                        }

                                        if (payNowRes != null && payNowRes['success'] == true) {
                                          TopNotificationBanner.show(
                                            title: 'Booking Confirmed! 🎉',
                                            body: 'Your payment was verified successfully. Digital ticket generated!',
                                            data: {'type': 'booking_confirmed', 'bookingId': createdBookingId},
                                          );
                                          if (outerContext.mounted) {
                                            Navigator.push(
                                              outerContext,
                                              MaterialPageRoute(
                                                builder: (_) => DigitalTicketScreen(
                                                  venue: widget.venue,
                                                  date: '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                                  package: isSolo ? 'Solo Entry' : 'Standard Table',
                                                  time: formattedTime,
                                                  table: isSolo ? 'Solo Entry' : 'Standard Table',
                                                  guests: isSolo ? '1' : '$guests',
                                                  totalPrice: '₹${totalPrice.toStringAsFixed(0)}',
                                                  ticketId: createdBookingId,
                                                  user: ApiService.cachedCurrentUser,
                                                  booking: {
                                                    'id': createdBookingId,
                                                    'bookingId': createdBookingId,
                                                    'venue': widget.venue,
                                                    'venueId': widget.venue['id'],
                                                    'isSolo': isSolo,
                                                    'goingMode': isSolo ? 'solo' : 'party_request',
                                                    'bookingType': isSolo ? 'solo' : 'venue_booking',
                                                    'category': isSolo ? 'solo' : 'venue_booking',
                                                    'totalAmount': totalPrice,
                                                    'paymentStatus': 'paid',
                                                    'paymentMethod': 'UPI / Net Banking',
                                                    'status': 'CONFIRMED',
                                                    'tablePackage': isSolo ? 'Solo Entry' : 'Standard Table',
                                                    'numberOfGuests': isSolo ? 1 : guests,
                                                    'bookingDate': _selectedDate.toIso8601String(),
                                                    'startTime': formattedTime,
                                                    'user': ApiService.cachedCurrentUser,
                                                  },
                                                ),
                                              ),
                                            );
                                          }
                                        } else {
                                           if (createdBookingId != null && createdBookingId!.isNotEmpty) {
                                             await ApiService.cancelPendingBooking(createdBookingId!);
                                             createdBookingId = null;
                                           }
                                           if (outerContext.mounted) {
                                             ScaffoldMessenger.of(outerContext).showSnackBar(
                                               const SnackBar(
                                                 content: Text('Payment verification failed. Booking could not be confirmed.'),
                                                 backgroundColor: Colors.redAccent,
                                               ),
                                             );
                                           }
                                        }
                                      } catch (e) {
                                        debugPrint('payNowBooking error: $e');
                                        if (createdBookingId != null && createdBookingId!.isNotEmpty) {
                                          await ApiService.cancelPendingBooking(createdBookingId!);
                                          createdBookingId = null;
                                        }
                                        if (outerContext.mounted) {
                                          Navigator.of(outerContext, rootNavigator: true).pop();
                                        }
                                      }
                                    });

                                    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) async {
                                      try { rzp.clear(); } catch (_) {}
                                      if (createdBookingId != null && createdBookingId!.isNotEmpty) {
                                        await ApiService.cancelPendingBooking(createdBookingId!);
                                        createdBookingId = null;
                                      }
                                      if (outerContext.mounted) {
                                        ScaffoldMessenger.of(outerContext).showSnackBar(
                                          SnackBar(
                                            content: Text('Payment cancelled or failed: ${response.message ?? 'Unknown error'}'),
                                            backgroundColor: Colors.redAccent,
                                          ),
                                        );
                                      }
                                    });

                                    rzp.on(Razorpay.EVENT_EXTERNAL_WALLET, (ExternalWalletResponse response) {
                                      try { rzp.clear(); } catch (_) {}
                                    });

                                    final user = ApiService.cachedCurrentUser;
                                    final options = {
                                      'key': keyId,
                                      'amount': amountInPaise,
                                      'name': widget.venue['name']?.toString() ?? 'Lunara Booking',
                                      'order_id': orderId,
                                      'description': isSolo
                                          ? 'Solo Table Booking'
                                          : 'Table Booking ($guests Guests)',
                                      'prefill': {
                                        'contact': user?.phone ?? '',
                                        'email': user?.email ?? '',
                                      },
                                      'theme': {'color': '#7B2CBF'},
                                    };

                                    rzp.open(options);
                                    return true;
                                  },
                                  onHybridPayment: (shortfallAmount) async {
                                    final orderData = await ApiService.createWalletRechargeOrder(shortfallAmount);
                                    if (orderData == null) {
                                      if (outerContext.mounted) {
                                        ScaffoldMessenger.of(outerContext).showSnackBar(
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
                                        final bookingRes = await ApiService.createBooking(
                                          venueId: widget.venue['id']?.toString() ?? '',
                                          bookingDate: bookingDateStr,
                                          startTime: _selectedTime ?? '22:00',
                                          tablePackage: isSolo ? 'Solo Entry' : 'Confirmation Charges',
                                          goingMode: isSolo ? 'solo' : 'party_request',
                                          numberOfGuests: isSolo ? 1 : guests,
                                          isUpcomingNight: widget.isUpcomingNight,
                                        );
                                        createdBookingId = (bookingRes != null && bookingRes['data'] is Map)
                                            ? (bookingRes['data']['id']?.toString() ?? bookingRes['data']['bookingId']?.toString() ?? '')
                                            : (bookingRes?['bookingId']?.toString() ?? '');

                                        if (createdBookingId == null || createdBookingId!.isEmpty) {
                                          return false;
                                        }

                                        final walletRes = await ApiService.payWithWallet(
                                          amount: totalPrice,
                                          bookingId: createdBookingId,
                                          paymentType: 'booking_payment',
                                        );
                                        if (walletRes != null && walletRes['success'] == true) {
                                          final transactionId = walletRes['data']?['transactionId']?.toString() ?? 'wallet';
                                          final payNowRes = await ApiService.payNowBooking(
                                            createdBookingId!,
                                            paymentMethod: 'WALLET',
                                            transactionId: transactionId,
                                          );
                                          if (payNowRes != null && payNowRes['success'] == true) {
                                            TopNotificationBanner.show(
                                              title: 'Booking Confirmed! 🎉',
                                              body: 'Your payment was verified successfully. Digital ticket generated!',
                                              data: {'type': 'booking_confirmed', 'bookingId': createdBookingId},
                                            );
                                            if (outerContext.mounted) {
                                              Navigator.push(
                                                outerContext,
                                                MaterialPageRoute(
                                                  builder: (_) => DigitalTicketScreen(
                                                    venue: widget.venue,
                                                    date: '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                                    package: isSolo ? 'Solo Entry' : 'Standard Table',
                                                    time: formattedTime,
                                                    table: isSolo ? 'Solo Entry' : 'Standard Table',
                                                    guests: isSolo ? '1' : '$guests',
                                                    totalPrice: '₹${totalPrice.toStringAsFixed(0)}',
                                                    ticketId: createdBookingId,
                                                    user: ApiService.cachedCurrentUser,
                                                    booking: {
                                                      'id': createdBookingId,
                                                      'bookingId': createdBookingId,
                                                      'venue': widget.venue,
                                                      'venueId': widget.venue['id'],
                                                      'isSolo': isSolo,
                                                      'goingMode': isSolo ? 'solo' : 'party_request',
                                                      'bookingType': isSolo ? 'solo' : 'venue_booking',
                                                      'category': isSolo ? 'solo' : 'venue_booking',
                                                      'totalAmount': totalPrice,
                                                      'paymentStatus': 'paid',
                                                      'paymentMethod': 'Lunara Wallet',
                                                      'status': 'CONFIRMED',
                                                      'tablePackage': isSolo ? 'Solo Entry' : 'Standard Table',
                                                      'numberOfGuests': isSolo ? 1 : guests,
                                                      'bookingDate': _selectedDate.toIso8601String(),
                                                      'startTime': formattedTime,
                                                      'user': ApiService.cachedCurrentUser,
                                                    },
                                                  ),
                                                ),
                                              );
                                            }
                                            return true;
                                          }
                                        }
                                      }
                                      return false;
                                    }

                                    final rzp = Razorpay();
                                    rzp.on(Razorpay.EVENT_PAYMENT_SUCCESS, (PaymentSuccessResponse response) async {
                                      try { rzp.clear(); } catch (_) {}

                                      if (outerContext.mounted) {
                                        showDialog(
                                          context: outerContext,
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
                                          final bookingRes = await ApiService.createBooking(
                                            venueId: widget.venue['id']?.toString() ?? '',
                                            bookingDate: bookingDateStr,
                                            startTime: _selectedTime ?? '22:00',
                                            tablePackage: isSolo ? 'Solo Entry' : 'Confirmation Charges',
                                            goingMode: isSolo ? 'solo' : 'party_request',
                                            numberOfGuests: isSolo ? 1 : guests,
                                            isUpcomingNight: widget.isUpcomingNight,
                                          );
                                          createdBookingId = (bookingRes != null && bookingRes['data'] is Map)
                                              ? (bookingRes['data']['id']?.toString() ?? bookingRes['data']['bookingId']?.toString() ?? '')
                                              : (bookingRes?['bookingId']?.toString() ?? '');

                                          if (createdBookingId != null && createdBookingId!.isNotEmpty) {
                                            final walletRes = await ApiService.payWithWallet(
                                              amount: totalPrice,
                                              bookingId: createdBookingId,
                                              paymentType: 'booking_payment',
                                            );

                                            if (walletRes != null && walletRes['success'] == true) {
                                              final transactionId = walletRes['data']?['transactionId']?.toString() ?? 'wallet';
                                              final payNowRes = await ApiService.payNowBooking(
                                                createdBookingId!,
                                                paymentMethod: 'WALLET',
                                                transactionId: transactionId,
                                              );

                                              if (outerContext.mounted) {
                                                Navigator.of(outerContext, rootNavigator: true).pop();
                                              }

                                              if (payNowRes != null && payNowRes['success'] == true) {
                                                TopNotificationBanner.show(
                                                  title: 'Booking Confirmed! 🎉',
                                                  body: 'Your payment was verified successfully. Digital ticket generated!',
                                                  data: {'type': 'booking_confirmed', 'bookingId': createdBookingId},
                                                );
                                                if (outerContext.mounted) {
                                                  Navigator.push(
                                                    outerContext,
                                                    MaterialPageRoute(
                                                      builder: (_) => DigitalTicketScreen(
                                                        venue: widget.venue,
                                                        date: '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                                        package: isSolo ? 'Solo Entry' : 'Standard Table',
                                                        time: formattedTime,
                                                        table: isSolo ? 'Solo Entry' : 'Standard Table',
                                                        guests: isSolo ? '1' : '$guests',
                                                        totalPrice: '₹${totalPrice.toStringAsFixed(0)}',
                                                        ticketId: createdBookingId,
                                                        user: ApiService.cachedCurrentUser,
                                                        booking: {
                                                          'id': createdBookingId,
                                                          'bookingId': createdBookingId,
                                                          'venue': widget.venue,
                                                          'venueId': widget.venue['id'],
                                                          'isSolo': isSolo,
                                                          'goingMode': isSolo ? 'solo' : 'party_request',
                                                          'bookingType': isSolo ? 'solo' : 'venue_booking',
                                                          'category': isSolo ? 'solo' : 'venue_booking',
                                                          'totalAmount': totalPrice,
                                                          'paymentStatus': 'paid',
                                                          'paymentMethod': 'Lunara Wallet',
                                                          'status': 'CONFIRMED',
                                                          'tablePackage': isSolo ? 'Solo Entry' : 'Standard Table',
                                                          'numberOfGuests': isSolo ? 1 : guests,
                                                          'bookingDate': _selectedDate.toIso8601String(),
                                                          'startTime': formattedTime,
                                                          'user': ApiService.cachedCurrentUser,
                                                        },
                                                      ),
                                                    ),
                                                  );
                                                }
                                                return;
                                              }
                                            }
                                          }
                                        }
                                        if (outerContext.mounted) {
                                          Navigator.of(outerContext, rootNavigator: true).pop();
                                        }
                                      } catch (e) {
                                        debugPrint('Hybrid payment error: $e');
                                        if (outerContext.mounted) {
                                          Navigator.of(outerContext, rootNavigator: true).pop();
                                        }
                                      }
                                    });

                                    rzp.on(Razorpay.EVENT_PAYMENT_ERROR, (PaymentFailureResponse response) {
                                      try { rzp.clear(); } catch (_) {}
                                    });

                                    final user = ApiService.cachedCurrentUser;
                                    final rechargeOptions = {
                                      'key': rzpKey,
                                      'amount': (shortfallAmount * 100).toInt(),
                                      'name': 'Lunara Wallet Top-up',
                                      'order_id': rzpOrderId,
                                      'description': 'Recharge for Booking at ${widget.venue['name'] ?? 'Venue'}',
                                      'prefill': {
                                        'contact': user?.phone ?? '',
                                        'email': user?.email ?? '',
                                      },
                                      'theme': {'color': '#7B2CBF'},
                                    };

                                    rzp.open(rechargeOptions);
                                    return true;
                                  },
                                );
                              } finally {
                                if (modalCtx.mounted) {
                                  setModalState(() => isSubmittingBooking = false);
                                }
                              }
                            },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
