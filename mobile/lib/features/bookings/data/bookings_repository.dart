import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/booking.dart';

final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  return BookingsRepository(ref.watch(dioProvider));
});

typedef BookingsPage = ({List<Booking> items, int total});

/// One page (10) of the customer's bookings; a new API call fires only
/// when the (scope, page) key changes — never the whole history at once.
final myBookingsProvider = FutureProvider.autoDispose
    .family<BookingsPage, ({String scope, int page})>((ref, key) {
  return ref.watch(bookingsRepositoryProvider).mine(key.scope, page: key.page);
});

final availableJobsProvider = FutureProvider.autoDispose<List<Booking>>((ref) {
  return ref.watch(bookingsRepositoryProvider).availableJobs();
});

final myJobsProvider = FutureProvider.autoDispose<List<Booking>>((ref) {
  return ref.watch(bookingsRepositoryProvider).myJobs();
});

final earningsProvider = FutureProvider.autoDispose<Earnings>((ref) {
  return ref.watch(bookingsRepositoryProvider).earnings();
});

final workerHistoryProvider = FutureProvider.autoDispose<List<Booking>>((ref) {
  return ref.watch(bookingsRepositoryProvider).workerHistory();
});

/// Offers the signed-in user can still use (one use per user, forever).
final availableCouponsProvider = FutureProvider.autoDispose<
    List<({String code, String label})>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res =
      await dio.get<Map<String, dynamic>>('/api/v1/coupons/available');
  return (unwrapEnvelope(res) as List<dynamic>).map((c) {
    final coupon = c as Map<String, dynamic>;
    final label = coupon['percent_off'] != null
        ? '${coupon['percent_off']}% off'
        : '₹${((coupon['flat_off_paise'] as int? ?? 0) / 100).toStringAsFixed(0)} off';
    return (code: coupon['code'] as String, label: label);
  }).toList();
});

class BookingsRepository {
  const BookingsRepository(this._dio);

  final Dio _dio;

  List<Booking> _list(Response<Map<String, dynamic>> res) {
    final data = unwrapEnvelope(res) as List<dynamic>;
    return data
        .map((b) => Booking.fromJson(b as Map<String, dynamic>))
        .toList();
  }

  Future<Booking> create({
    required String serviceId,
    required String address,
    String? note,
    double? lat,
    double? lng,
    String? couponCode,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/bookings',
      data: {
        'service_id': serviceId,
        'address': address,
        if (note != null && note.isNotEmpty) 'note': note,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (couponCode != null && couponCode.isNotEmpty)
          'coupon_code': couponCode,
      },
    );
    return Booking.fromJson(unwrapEnvelope(res) as Map<String, dynamic>);
  }

  /// Live coupon quote for the booking sheet; throws on invalid/used.
  Future<({int discountPaise, int finalPaise})> couponCheck(
      String code, String serviceId) async {
    final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/coupons/check?code=${Uri.encodeComponent(code)}&service_id=$serviceId');
    final data = unwrapEnvelope(res) as Map<String, dynamic>;
    return (
      discountPaise: data['discount_paise'] as int,
      finalPaise: data['final_paise'] as int,
    );
  }

  Future<List<Booking>> workerHistory() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/jobs/history');
    return _list(res);
  }

  Future<BookingsPage> mine(String scope, {int page = 1}) async {
    final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/bookings/mine?scope=$scope&page=$page');
    final items = _list(res);
    final meta = res.data?['meta'] as Map<String, dynamic>?;
    return (items: items, total: (meta?['total'] as int?) ?? items.length);
  }

  Future<List<Booking>> availableJobs() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/jobs/available');
    return _list(res);
  }

  Future<List<Booking>> myJobs() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/jobs/mine');
    return _list(res);
  }

  Future<Earnings> earnings() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/jobs/earnings');
    return Earnings.fromJson(unwrapEnvelope(res) as Map<String, dynamic>);
  }

  Future<void> accept(String id) => _dio.post('/api/v1/bookings/$id/accept');

  Future<void> advance(String id, String action, {String? otp}) =>
      _dio.patch('/api/v1/bookings/$id/status', data: {
        'action': action,
        if (otp != null && otp.isNotEmpty) 'otp': otp,
      });

  Future<void> cancel(String id, {String? reason}) =>
      _dio.post('/api/v1/bookings/$id/cancel', data: {
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });

  Future<void> rate(String id, int rating, String? review) =>
      _dio.post('/api/v1/bookings/$id/rate', data: {
        'rating': rating,
        if (review != null && review.isNotEmpty) 'review': review,
      });
}
