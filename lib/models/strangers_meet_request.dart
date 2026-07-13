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

  factory StrangersMeetRequest.fromJson(Map<String, dynamic> json) {
    return StrangersMeetRequest(
      id: json['id'] ?? '',
      subject: json['subject'] ?? '',
      tagline: json['tagline'] ?? '',
      eventDateTime: DateTime.parse(
        json['eventDateTime'] ?? DateTime.now().toIso8601String(),
      ),
      numberOfPersons: json['numberOfPersons'] ?? 21,
      chargesPerHead: json['chargesPerHead'] != null
          ? (json['chargesPerHead'] is String
              ? (double.tryParse(json['chargesPerHead']) ?? 0.0)
              : (json['chargesPerHead'] as num).toDouble())
          : 0.0,
      slotsFilled: json['slotsFilled'] ?? 0,
      status: json['status'] ?? 'pending',
      paymentAmount: json['paymentAmount'] != null
          ? (json['paymentAmount'] is String
              ? double.tryParse(json['paymentAmount'])
              : (json['paymentAmount'] as num).toDouble())
          : null,
      paymentStatus: json['paymentStatus'] ?? 'unpaid',
      adminNotes: json['adminNotes'],
      ticketId: json['ticketId'],
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : null,
      mobileNumber: json['mobileNumber'],
      alternateMobileNumber: json['alternateMobileNumber'],
      bankName: json['bankName'],
      accountNumber: json['accountNumber'],
      accountHolderName: json['accountHolderName'],
      ifscCode: json['ifscCode'],
      upiId: json['upiId'],
      platformChargePerSeat: json['platformChargePerSeat'] != null
          ? (json['platformChargePerSeat'] is String
              ? double.tryParse(json['platformChargePerSeat'])
              : (json['platformChargePerSeat'] as num).toDouble())
          : null,
      settlementStatus: json['settlementStatus'] ?? 'none',
      bankDetails: json['bankDetails'],
      settlementTransactionId: json['settlementTransactionId'],
      settlementAmount: json['settlementAmount'] != null
          ? (json['settlementAmount'] is String
              ? double.tryParse(json['settlementAmount'])
              : (json['settlementAmount'] as num).toDouble())
          : null,
      settlementDate: json['settlementDate'] != null
          ? DateTime.parse(json['settlementDate'])
          : null,
      settlementMethod: json['settlementMethod'],
      joinedCount: json['joinedCount'] ?? 0,
      paymentCount: json['paymentCount'] ?? 0,
      remainingCount: json['remainingCount'] ?? 0,
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
