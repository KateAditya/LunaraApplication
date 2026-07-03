class HelpArticle {
  final String id;
  final String title;
  final String content;
  final String category;
  final bool isPublished;
  final int displayOrder;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  HelpArticle({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.isPublished,
    required this.displayOrder,
    this.createdAt,
    this.updatedAt,
  });

  factory HelpArticle.fromJson(Map<String, dynamic> json) {
    return HelpArticle(
      id: json['id']?.toString() ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      category: json['category'] ?? '',
      isPublished: json['isPublished'] ?? false,
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
      'isPublished': isPublished,
      'displayOrder': displayOrder,
      'createdAt': createdAt?.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
    };
  }
}
