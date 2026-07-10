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

  // Settlement info
  final String settlementStatus;
  final String? bankDetails;
  final String? settlementTransactionId;
  final double? settlementAmount;
  final DateTime? settlementDate;
  final String? settlementMethod;

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
    required this.settlementStatus,
    this.bankDetails,
    this.settlementTransactionId,
    this.settlementAmount,
    this.settlementDate,
    this.settlementMethod,
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
      user: json['user'],
      venue: json['venue'],
      joiners: json['joiners'],
    );
  }
}
