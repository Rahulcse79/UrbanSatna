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
    this.arrivalOtp,
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
        arrivalOtp: json['arrival_otp'] as String?,
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

  /// Present only in customer responses; workers never receive it.
  final String? arrivalOtp;

  String get priceLabel => '₹${(pricePaise / 100).toStringAsFixed(0)}';
  bool get cancellable => status == 'pending' || status == 'accepted';
  bool get ratable => status == 'completed' && rating == null;

  /// Show the arrival OTP once a worker is assigned, until work starts.
  bool get showArrivalOtp =>
      arrivalOtp != null &&
      const {'accepted', 'en_route', 'arrived'}.contains(status);

  /// 0 = not started, 1..5 = Accepted → On the way → Arrived → Working → Done.
  int get progressStep => switch (status) {
        'accepted' => 1,
        'en_route' => 2,
        'arrived' => 3,
        'in_progress' => 4,
        'completed' => 5,
        _ => 0,
      };

  /// Worker's next action in the state machine, or null when none.
  String? get nextWorkerAction => switch (status) {
        'accepted' => 'en_route',
        'en_route' => 'arrived',
        'arrived' => 'start',
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
