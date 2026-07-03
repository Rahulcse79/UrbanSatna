class Booking {
  const Booking({
    required this.id,
    required this.status,
    required this.serviceName,
    required this.categoryName,
    required this.address,
    required this.pricePaise,
    required this.createdAt,
    this.workerName,
    this.customerName,
    this.note,
    this.rating,
  });

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        status: json['status'] as String,
        serviceName: json['service_name'] as String,
        categoryName: json['category_name'] as String,
        address: json['address'] as String,
        pricePaise: json['price_paise'] as int,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        workerName: json['worker_name'] as String?,
        customerName: json['customer_name'] as String?,
        note: json['note'] as String?,
        rating: json['rating'] as int?,
      );

  final String id;
  final String status;
  final String serviceName;
  final String categoryName;
  final String address;
  final int pricePaise;
  final DateTime createdAt;
  final String? workerName;
  final String? customerName;
  final String? note;
  final int? rating;

  String get priceLabel => '₹${(pricePaise / 100).toStringAsFixed(0)}';
  bool get cancellable => status == 'pending' || status == 'accepted';
  bool get ratable => status == 'completed' && rating == null;

  /// Worker's next action in the state machine, or null when none.
  String? get nextWorkerAction => switch (status) {
        'accepted' => 'en_route',
        'en_route' => 'start',
        'in_progress' => 'complete',
        _ => null,
      };
}

class Earnings {
  const Earnings({
    required this.completedJobs,
    required this.totalPaise,
    this.avgRating,
  });

  factory Earnings.fromJson(Map<String, dynamic> json) => Earnings(
        completedJobs: json['completed_jobs'] as int,
        totalPaise: json['total_paise'] as int,
        avgRating: (json['avg_rating'] as num?)?.toDouble(),
      );

  final int completedJobs;
  final int totalPaise;
  final double? avgRating;

  String get totalLabel => '₹${(totalPaise / 100).toStringAsFixed(0)}';
}
