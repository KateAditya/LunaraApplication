class CommunityGuideline {
  final String id;
  final String title;
  final String content;
  final String category;
  final bool isActive;
  final int displayOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  CommunityGuideline({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.isActive,
    required this.displayOrder,
    this.createdAt,
    this.updatedAt,
  });

  factory CommunityGuideline.fromJson(Map<String, dynamic> json) {
    return CommunityGuideline(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      category: json['category'] ?? '',
      isActive: json['isActive'] ?? false,
      displayOrder: json['displayOrder'] ?? 0,
      createdAt: json['createdAt'] != null ? DateTime.tryParse(json['createdAt']) : null,
      updatedAt: json['updatedAt'] != null ? DateTime.tryParse(json['updatedAt']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'content': content,
      'category': category,
      'isActive': isActive,
      'displayOrder': displayOrder,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
