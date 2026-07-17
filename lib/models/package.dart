class Package {
  final String id;
  final String name;
  final String description;
  final double price;

  Package({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
  });

  factory Package.fromJson(Map<dynamic, dynamic> json) {
    return Package(
      id: json['id']?.toString() ?? '',
      name: json['label'] ?? json['packageName'] ?? json['name'] ?? '',
      description: json['description'] ?? '',
      price: double.tryParse(json['price']?.toString() ?? '0.0') ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'packageName': name,
      'description': description,
      'price': price,
    };
  }
}
