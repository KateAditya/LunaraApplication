class StrangersMeetRequest {
  final String id;
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
  final DateTime? createdAt;
  final String? mobileNumber;
  final String? alternateMobileNumber;

  // v2: Structured bank/UPI details provided at creation
  final String? bankName;
  final String? accountNumber;
  final String? accountHolderName;
  final String? ifscCode;
  final String? upiId;

  // Admin-calculated platform charge per seat (= paymentAmount / numberOfPersons)
  final double? platformChargePerSeat;

  // Settlement info
  final String settlementStatus;
  final String? bankDetails; // legacy
  final String? settlementTransactionId;
  final double? settlementAmount;
  final DateTime? settlementDate;
  final String? settlementMethod;

  // Dynamic computed values from server
  final int joinedCount;
  final int paymentCount;
  final int remainingCount;

  final Map<String, dynamic>? user;
  final Map<String, dynamic>? venue;
  final List<dynamic>? joiners;

  StrangersMeetRequest({
    required this.id,
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
    this.createdAt,
    this.mobileNumber,
    this.alternateMobileNumber,
    this.bankName,
    this.accountNumber,
    this.accountHolderName,
    this.ifscCode,
    this.upiId,
    this.platformChargePerSeat,
    required this.settlementStatus,
    this.bankDetails,
    this.settlementTransactionId,
    this.settlementAmount,
    this.settlementDate,
    this.settlementMethod,
    this.joinedCount = 0,
    this.paymentCount = 0,
    this.remainingCount = 0,
    this.user,
    this.venue,
    this.joiners,
  });

  factory StrangersMeetRequest.fromJson(Map<dynamic, dynamic> json) {
    final eventDateRaw = json['eventDateTime'] ?? json['event_date_time'];
    final numPersonsRaw = json['numberOfPersons'] ?? json['number_of_persons'];
    final chargesPerHeadRaw =
        json['chargesPerHead'] ?? json['charges_per_head'];
    final slotsFilledRaw = json['slotsFilled'] ?? json['slots_filled'];
    final paymentAmountRaw = json['paymentAmount'] ?? json['payment_amount'];
    final paymentStatusRaw = json['paymentStatus'] ?? json['payment_status'];
    final platformChargeRaw =
        json['platformChargePerSeat'] ?? json['platform_charge_per_seat'];

    return StrangersMeetRequest(
      id: json['id'] ?? '',
      subject: json['subject'] ?? '',
      tagline: json['tagline'] ?? '',
      eventDateTime: DateTime.parse(
        eventDateRaw ?? DateTime.now().toIso8601String(),
      ),
      numberOfPersons: numPersonsRaw ?? 21,
      chargesPerHead: chargesPerHeadRaw != null
          ? (chargesPerHeadRaw is String
                ? (double.tryParse(chargesPerHeadRaw) ?? 0.0)
                : (chargesPerHeadRaw as num).toDouble())
          : 0.0,
      slotsFilled: slotsFilledRaw ?? 0,
      status: json['status'] ?? 'pending',
      paymentAmount: paymentAmountRaw != null
          ? (paymentAmountRaw is String
                ? double.tryParse(paymentAmountRaw)
                : (paymentAmountRaw as num).toDouble())
          : null,
      paymentStatus: paymentStatusRaw ?? 'unpaid',
      adminNotes: json['adminNotes'] ?? json['admin_notes'],
      ticketId: json['ticketId'] ?? json['ticket_id'],
      createdAt: (json['createdAt'] ?? json['created_at']) != null
          ? DateTime.parse(json['createdAt'] ?? json['created_at'])
          : null,
      mobileNumber: json['mobileNumber'] ?? json['mobile_number'],
      alternateMobileNumber:
          json['alternateMobileNumber'] ?? json['alternate_mobile_number'],
      bankName: json['bankName'] ?? json['bank_name'],
      accountNumber: json['accountNumber'] ?? json['account_number'],
      accountHolderName:
          json['accountHolderName'] ?? json['account_holder_name'],
      ifscCode: json['ifscCode'] ?? json['ifsc_code'],
      upiId: json['upiId'] ?? json['upi_id'],
      platformChargePerSeat: platformChargeRaw != null
          ? (platformChargeRaw is String
                ? double.tryParse(platformChargeRaw)
                : (platformChargeRaw as num).toDouble())
          : null,
      settlementStatus:
          json['settlementStatus'] ?? json['settlement_status'] ?? 'none',
      bankDetails: json['bankDetails'] ?? json['bank_details'],
      settlementTransactionId:
          json['settlementTransactionId'] ?? json['settlement_transaction_id'],
      settlementAmount:
          json['settlementAmount'] ?? json['settlement_amount'] != null
          ? ((json['settlementAmount'] ?? json['settlement_amount']) is String
                ? double.tryParse(
                    json['settlementAmount'] ?? json['settlement_amount'],
                  )
                : ((json['settlementAmount'] ?? json['settlement_amount'])
                          as num)
                      .toDouble())
          : null,
      settlementDate:
          (json['settlementDate'] ?? json['settlement_date']) != null
          ? DateTime.parse(json['settlementDate'] ?? json['settlement_date'])
          : null,
      settlementMethod: json['settlementMethod'] ?? json['settlement_method'],
      joinedCount: json['joinedCount'] ?? json['joined_count'] ?? 0,
      paymentCount: json['paymentCount'] ?? json['payment_count'] ?? 0,
      remainingCount: json['remainingCount'] ?? json['remaining_count'] ?? 0,
      user: json['user'],
      venue: json['venue'],
      joiners: json['joiners'],
    );
  }

  /// Whether the host provided bank details (either structured or legacy UPI)
  bool get hasBankDetails =>
      (bankName != null && bankName!.isNotEmpty) ||
      (upiId != null && upiId!.isNotEmpty) ||
      (bankDetails != null && bankDetails!.isNotEmpty);

  /// Returns a display-friendly string of the bank/UPI info
  String get bankDetailsSummary {
    if (upiId != null && upiId!.isNotEmpty) return 'UPI: $upiId';
    if (bankName != null && bankName!.isNotEmpty) {
      return '$bankName · ${accountNumber ?? ''} · IFSC: ${ifscCode ?? ''}';
    }
    return bankDetails ?? 'No bank details provided';
  }
}
