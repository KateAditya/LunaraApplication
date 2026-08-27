class StrangersMeetRequest {
  final String id;
  final String? userId;
  final String subject;
  final String tagline;
  final DateTime eventDateTime;
  final int numberOfPersons;
  final double chargesPerHead;
  final int slotsFilled;
  final String status;
  final double? paymentAmount;
  final String paymentStatus;
  final String? adminNotes;
  final String? ticketId;
  final String? ticketUrl;
  final DateTime? createdAt;
  final String? mobileNumber;
  final String? alternateMobileNumber;

  // v2: Structured bank/UPI details provided at creation
  final String? bankName;
  final String? accountNumber;
  final String? accountHolderName;
  final String? ifscCode;
  final String? upiId;
  final String? upiNumber;

  // Admin-calculated platform charge per seat (= paymentAmount / numberOfPersons)
  final double? platformChargePerSeat;

  // Settlement info
  final String settlementStatus;
  final String? bankDetails; // legacy
  final String? settlementTransactionId;
  final double? settlementAmount;
  final DateTime? settlementDate;
  final String? settlementMethod;

  // Lifecycle fields
  final DateTime? startedAt;
  final String? startedBy;
  final double? durationHours;
  final DateTime? expectedEndAt;
  final DateTime? endedAt;
  final String? endedConfirmedBy;
  final DateTime? endedConfirmedAt;
  final DateTime? adminConfirmedEndedAt;
  final String? adminConfirmedBy;
  final bool settlementOverdue;

  // Dynamic computed values from server
  final int joinedCount;
  final int paymentCount;
  final int remainingCount;

  final Map<String, dynamic>? user;
  final Map<String, dynamic>? venue;
  final List<dynamic>? joiners;

  StrangersMeetRequest({
    required this.id,
    this.userId,
    required this.subject,
    required this.tagline,
    required this.eventDateTime,
    required this.numberOfPersons,
    required this.chargesPerHead,
    required this.slotsFilled,
    required this.status,
    this.paymentAmount,
    required this.paymentStatus,
    this.adminNotes,
    this.ticketId,
    this.ticketUrl,
    this.createdAt,
    this.mobileNumber,
    this.alternateMobileNumber,
    this.bankName,
    this.accountNumber,
    this.accountHolderName,
    this.ifscCode,
    this.upiId,
    this.upiNumber,
    this.platformChargePerSeat,
    required this.settlementStatus,
    this.bankDetails,
    this.settlementTransactionId,
    this.settlementAmount,
    this.settlementDate,
    this.settlementMethod,
    this.startedAt,
    this.startedBy,
    this.durationHours,
    this.expectedEndAt,
    this.endedAt,
    this.endedConfirmedBy,
    this.endedConfirmedAt,
    this.adminConfirmedEndedAt,
    this.adminConfirmedBy,
    this.settlementOverdue = false,
    this.joinedCount = 0,
    this.paymentCount = 0,
    this.remainingCount = 0,
    this.user,
    this.venue,
    this.joiners,
  });

  factory StrangersMeetRequest.fromJson(Map<dynamic, dynamic> json) {
    final eventDateRaw = json['eventDateTime'] ?? json['event_date_time'] ?? json['bookingDate'] ?? json['partyDate'] ?? json['eventStartAt'] ?? json['date'];
    final timeRaw = json['startTime'] ?? json['partyTime'] ?? json['time'];
    final numPersonsRaw = json['numberOfPersons'] ??
        json['number_of_persons'] ??
        json['totalSeats'] ??
        json['maxPersons'] ??
        json['seats'] ??
        json['maxSeats'] ??
        json['numberOfSeats'] ??
        json['numberOfGuests'] ??
        json['persons'] ??
        (json['plan'] is Map ? json['plan']['numberOfPersons'] ?? json['plan']['number_of_persons'] ?? json['plan']['maxPersons'] ?? json['plan']['totalSeats'] : null) ??
        (json['request'] is Map ? json['request']['numberOfPersons'] ?? json['request']['number_of_persons'] ?? json['request']['totalSeats'] : null) ??
        (json['data'] is Map ? json['data']['numberOfPersons'] ?? json['data']['totalSeats'] : null);
    final chargesPerHeadRaw = json['chargesPerHead'] ??
        json['charges_per_head'] ??
        json['hostChargesPerHead'] ??
        json['charges'] ??
        json['entryFee'] ??
        json['fee'] ??
        (json['plan'] is Map ? json['plan']['chargesPerHead'] ?? json['plan']['charges_per_head'] : null) ??
        (json['request'] is Map ? json['request']['chargesPerHead'] ?? json['request']['charges_per_head'] : null) ??
        (json['metadata'] is Map ? json['metadata']['chargesPerHead'] ?? json['metadata']['charges_per_head'] : null) ??
        (json['data'] is Map ? json['data']['chargesPerHead'] ?? json['data']['charges_per_head'] : null);
    final slotsFilledRaw = json['paymentCount'] ?? json['payment_count'] ?? json['slotsFilled'] ?? json['slots_filled'] ?? json['joinedCount'] ?? json['joined_count'];
    final paymentAmountRaw = json['paymentAmount'] ??
        json['payment_amount'] ??
        json['adminPaymentAmount'] ??
        json['admin_payment_amount'] ??
        json['amount'] ??
        json['totalAmount'] ??
        json['depositAmount'] ??
        (json['plan'] is Map ? json['plan']['paymentAmount'] ?? json['plan']['payment_amount'] ?? json['plan']['adminPaymentAmount'] : null) ??
        (json['request'] is Map ? json['request']['paymentAmount'] ?? json['request']['payment_amount'] ?? json['request']['adminPaymentAmount'] : null) ??
        (json['metadata'] is Map ? json['metadata']['paymentAmount'] ?? json['metadata']['payment_amount'] ?? json['metadata']['adminPaymentAmount'] : null) ??
        (json['data'] is Map ? json['data']['paymentAmount'] ?? json['data']['payment_amount'] ?? json['data']['adminPaymentAmount'] : null);
    final paymentStatusRaw = json['paymentStatus'] ?? json['payment_status'];
    final platformChargeRaw = json['platformChargePerSeat'] ?? json['platform_charge_per_seat'];

    DateTime parsedDate = DateTime.now();
    if (eventDateRaw != null) {
      if (eventDateRaw is DateTime) {
        parsedDate = eventDateRaw.toLocal();
      } else {
        parsedDate = DateTime.tryParse(eventDateRaw.toString())?.toLocal() ?? DateTime.now();
      }
    }
    if (timeRaw != null && timeRaw.toString().trim().isNotEmpty) {
      final cleanTime = timeRaw.toString().toUpperCase().trim();
      final isPm = cleanTime.contains('PM');
      final isAm = cleanTime.contains('AM');
      final timeOnly = cleanTime.replaceAll('AM', '').replaceAll('PM', '').trim();
      final parts = timeOnly.split(':');
      if (parts.isNotEmpty) {
        int? h = int.tryParse(parts[0].trim());
        int m = parts.length > 1 ? (int.tryParse(parts[1].trim()) ?? 0) : 0;
        if (h != null) {
          if (isPm && h < 12) h += 12;
          if (isAm && h == 12) h = 0;
          parsedDate = DateTime(parsedDate.year, parsedDate.month, parsedDate.day, h, m);
        }
      }
    } else if (parsedDate.hour == 5 && parsedDate.minute == 30 && eventDateRaw.toString().endsWith('Z')) {
      parsedDate = DateTime(parsedDate.year, parsedDate.month, parsedDate.day, 0, 0);
    }

    final int numPersons = int.tryParse(numPersonsRaw?.toString() ?? '') ?? 2;
    final double charges = chargesPerHeadRaw != null
        ? (chargesPerHeadRaw is num
            ? chargesPerHeadRaw.toDouble()
            : (double.tryParse(chargesPerHeadRaw.toString()) ?? 0.0))
        : 0.0;
    final double? payAmount = paymentAmountRaw != null
        ? (paymentAmountRaw is num
            ? paymentAmountRaw.toDouble()
            : double.tryParse(paymentAmountRaw.toString()))
        : null;

    final userMap = json['user'] is Map 
        ? Map<String, dynamic>.from(json['user']) 
        : (json['host'] is Map
            ? Map<String, dynamic>.from(json['host'])
            : (json['creator'] is Map
                ? Map<String, dynamic>.from(json['creator'])
                : (json['plan'] is Map && json['plan']['user'] is Map
                    ? Map<String, dynamic>.from(json['plan']['user'])
                    : (json['firstName'] != null || json['first_name'] != null
                        ? Map<String, dynamic>.from(json)
                        : null))));
    final venueMap = json['venue'] is Map ? Map<String, dynamic>.from(json['venue']) : null;

    return StrangersMeetRequest(
      id: (json['id'] ?? json['bookingId'] ?? '').toString(),
      userId: json['userId'] ?? json['user_id'] ?? userMap?['id']?.toString(),
      subject: (json['subject'] ?? json['tablePackage'] ?? 'Strangers Meetup').toString(),
      tagline: (json['tagline'] ?? '').toString(),
      eventDateTime: parsedDate,
      numberOfPersons: numPersons,
      chargesPerHead: charges,
      slotsFilled: int.tryParse(slotsFilledRaw?.toString() ?? '') ?? 0,
      status: (json['status'] ?? 'pending').toString(),
      paymentAmount: payAmount,
      paymentStatus: (paymentStatusRaw ?? 'unpaid').toString(),
      adminNotes: json['adminNotes']?.toString() ?? json['admin_notes']?.toString(),
      ticketId: json['ticketId']?.toString() ?? json['ticket_id']?.toString() ?? json['ticketCode']?.toString(),
      ticketUrl: json['ticketUrl']?.toString() ?? json['ticket_url']?.toString(),
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())?.toLocal()
          : (json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString())?.toLocal() : null),
      mobileNumber: json['mobileNumber']?.toString() ?? json['mobile_number']?.toString(),
      alternateMobileNumber: json['alternateMobileNumber']?.toString() ?? json['alternate_mobile_number']?.toString(),
      bankName: json['bankName']?.toString() ?? json['bank_name']?.toString(),
      accountNumber: json['accountNumber']?.toString() ?? json['account_number']?.toString(),
      accountHolderName: json['accountHolderName']?.toString() ?? json['account_holder_name']?.toString(),
      ifscCode: json['ifscCode']?.toString() ?? json['ifsc_code']?.toString(),
      upiId: json['upiId']?.toString() ?? json['upi_id']?.toString(),
      upiNumber: json['upiNumber']?.toString() ?? json['upi_number']?.toString(),
      platformChargePerSeat: platformChargeRaw != null
          ? (platformChargeRaw is num ? platformChargeRaw.toDouble() : double.tryParse(platformChargeRaw.toString()))
          : null,
      settlementStatus: (json['settlementStatus'] ?? json['settlement_status'] ?? 'none').toString(),
      bankDetails: json['bankDetails']?.toString() ?? json['bank_details']?.toString(),
      settlementTransactionId: json['settlementTransactionId']?.toString() ?? json['settlement_transaction_id']?.toString(),
      settlementAmount: json['settlementAmount'] != null ? double.tryParse(json['settlementAmount'].toString()) : null,
      settlementDate: json['settlementDate'] != null ? DateTime.tryParse(json['settlementDate'].toString())?.toLocal() : null,
      settlementMethod: json['settlementMethod']?.toString() ?? json['settlement_method']?.toString(),
      startedAt: json['startedAt'] != null ? DateTime.tryParse(json['startedAt'].toString())?.toLocal() : null,
      startedBy: json['startedBy']?.toString() ?? json['started_by']?.toString(),
      durationHours: json['durationHours'] != null ? double.tryParse(json['durationHours'].toString()) : null,
      expectedEndAt: json['expectedEndAt'] != null ? DateTime.tryParse(json['expectedEndAt'].toString())?.toLocal() : null,
      endedAt: json['endedAt'] != null ? DateTime.tryParse(json['endedAt'].toString())?.toLocal() : null,
      endedConfirmedBy: json['endedConfirmedBy']?.toString() ?? json['ended_confirmed_by']?.toString(),
      endedConfirmedAt: json['endedConfirmedAt'] != null ? DateTime.tryParse(json['endedConfirmedAt'].toString())?.toLocal() : null,
      adminConfirmedEndedAt: json['adminConfirmedEndedAt'] != null ? DateTime.tryParse(json['adminConfirmedEndedAt'].toString())?.toLocal() : null,
      adminConfirmedBy: json['adminConfirmedBy']?.toString() ?? json['admin_confirmed_by']?.toString(),
      settlementOverdue: json['settlementOverdue'] == true || json['settlement_overdue'] == true,
      joinedCount: int.tryParse(json['joinedCount']?.toString() ?? json['joined_count']?.toString() ?? '') ?? 0,
      paymentCount: int.tryParse(json['paymentCount']?.toString() ?? json['payment_count']?.toString() ?? '') ?? 0,
      remainingCount: int.tryParse(json['remainingCount']?.toString() ?? json['remaining_count']?.toString() ?? '') ?? 0,
      user: userMap,
      venue: venueMap,
      joiners: json['joiners'] is List ? json['joiners'] : null,
    );
  }

  /// Helper getters for lifecycle
  bool get isInProgress => status.toLowerCase() == 'in_progress';
  bool get isHostConfirmedEnded => status.toLowerCase() == 'host_confirmed_ended';
  bool get isAdminConfirmedEnded => status.toLowerCase() == 'admin_confirmed_ended';
  bool get isCompleted => status.toLowerCase() == 'completed';

  /// Remaining duration string (hh:mm:ss) until expectedEndAt
  String get remainingTimeFormatted {
    if (expectedEndAt == null) return '--:--';
    final diff = expectedEndAt!.difference(DateTime.now());
    if (diff.isNegative) return '00:00:00';
    final hours = diff.inHours.toString().padLeft(2, '0');
    final minutes = (diff.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (diff.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }

  /// Whether the host provided bank details (either structured or legacy UPI/UPI number)
  bool get hasBankDetails =>
      (bankName != null && bankName!.isNotEmpty) ||
      (upiId != null && upiId!.isNotEmpty) ||
      (upiNumber != null && upiNumber!.isNotEmpty) ||
      (bankDetails != null && bankDetails!.isNotEmpty);

  /// Returns a display-friendly string of the bank/UPI info
  String get bankDetailsSummary {
    if (upiId != null && upiId!.isNotEmpty) return 'UPI ID: $upiId';
    if (upiNumber != null && upiNumber!.isNotEmpty) return 'UPI No: $upiNumber';
    if (bankName != null && bankName!.isNotEmpty) {
      return '$bankName · ${accountNumber ?? ''} · IFSC: ${ifscCode ?? ''}';
    }
    return bankDetails ?? 'No bank details provided';
  }

  /// Returns the dynamically confirmed participant count (joined users)
  int get actualParticipantsCount {
    if (joinedCount > 0) return joinedCount;
    if (paymentCount > 0) return paymentCount;
    if (slotsFilled > 0) return slotsFilled;
    if (joiners != null && joiners!.isNotEmpty) {
      final valid = joiners!.where((j) {
        if (j is! Map) return false;
        final st = (j['status'] ?? '').toString().toLowerCase();
        final pst = (j['paymentStatus'] ?? '').toString().toLowerCase();
        return st == 'paid' || st == 'accepted' || pst == 'paid';
      }).length;
      if (valid > 0) return valid;
    }
    return 1; // Default to host (1 person)
  }
}
