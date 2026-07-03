class Category {
  const Category({
    required this.id,
    required this.name,
    required this.icon,
  });

  factory Category.fromJson(Map<String, dynamic> json) => Category(
        id: json['id'] as String,
        name: json['name'] as String,
        icon: json['icon'] as String?,
      );

  final String id;
  final String name;
  final String? icon;
}

class Service {
  const Service({
    required this.id,
    required this.name,
    required this.description,
    required this.pricePaise,
    required this.durationMin,
  });

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'] as String,
        name: json['name'] as String,
        description: json['description'] as String?,
        pricePaise: json['base_price_paise'] as int,
        durationMin: json['duration_min'] as int,
      );

  final String id;
  final String name;
  final String? description;
  final int pricePaise;
  final int durationMin;

  String get priceLabel => '₹${(pricePaise / 100).toStringAsFixed(0)}';
}
