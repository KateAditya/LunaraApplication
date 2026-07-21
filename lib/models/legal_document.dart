class LegalDocument {
  final String id;
  final String title;
  final String type;
  final String content;
  final String version;
  final bool isActive;
  final DateTime? effectiveDate;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  LegalDocument({
    required this.id,
    required this.title,
    required this.type,
    required this.content,
    required this.version,
    required this.isActive,
    this.effectiveDate,
    this.createdAt,
    this.updatedAt,
  });

  factory LegalDocument.fromJson(Map<String, dynamic> json) {
    return LegalDocument(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      type: json['type'] ?? '',
      content: json['content'] ?? '',
      version: json['version']?.toString() ?? '',
      isActive: json['isActive'] ?? json['is_active'] ?? false,
      effectiveDate: json['effectiveDate'] != null 
          ? DateTime.tryParse(json['effectiveDate'].toString()) 
          : (json['effective_date'] != null ? DateTime.tryParse(json['effective_date'].toString()) : null),
      createdAt: json['createdAt'] != null 
          ? DateTime.tryParse(json['createdAt'].toString()) 
          : (json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null),
      updatedAt: json['updatedAt'] != null 
          ? DateTime.tryParse(json['updatedAt'].toString()) 
          : (json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'type': type,
      'content': content,
      'version': version,
      'isActive': isActive,
      'effectiveDate': effectiveDate?.toIso8601String(),
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
