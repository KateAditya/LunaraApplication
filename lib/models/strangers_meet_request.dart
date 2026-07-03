class StrangersMeetRequest {
  final String id;
  final String subject;
  final String tagline;
  final DateTime eventDateTime;
  final int numberOfPersons;
  final String status;
  final double? paymentAmount;
  final String paymentStatus;
  final String? adminNotes;
  final String? ticketId;
  final DateTime? createdAt;
  final String? mobileNumber;
  final String? alternateMobileNumber;

  final Map<String, dynamic>? user;
  final Map<String, dynamic>? venue;

  StrangersMeetRequest({
    required this.id,
    required this.subject,
    required this.tagline,
    required this.eventDateTime,
    required this.numberOfPersons,
    required this.status,
    this.paymentAmount,
    required this.paymentStatus,
    this.adminNotes,
    this.ticketId,
    this.createdAt,
    this.mobileNumber,
    this.alternateMobileNumber,
    this.user,
    this.venue,
  });

  factory StrangersMeetRequest.fromJson(Map<String, dynamic> json) {
    return StrangersMeetRequest(
      id: json['id'] ?? '',
      subject: json['subject'] ?? '',
      tagline: json['tagline'] ?? '',
      eventDateTime: DateTime.parse(json['eventDateTime'] ?? DateTime.now().toIso8601String()),
      numberOfPersons: json['numberOfPersons'] ?? 21,
      status: json['status'] ?? 'pending',
      paymentAmount: json['paymentAmount'] != null 
          ? (json['paymentAmount'] is String 
              ? double.tryParse(json['paymentAmount']) 
              : (json['paymentAmount'] as num).toDouble()) 
          : null,
      paymentStatus: json['paymentStatus'] ?? 'unpaid',
      adminNotes: json['adminNotes'],
      ticketId: json['ticketId'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      mobileNumber: json['mobileNumber'],
      alternateMobileNumber: json['alternateMobileNumber'],
      user: json['user'],
      venue: json['venue'],
    );
  }
}
