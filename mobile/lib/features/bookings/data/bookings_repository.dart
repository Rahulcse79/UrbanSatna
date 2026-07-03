import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/booking.dart';

final bookingsRepositoryProvider = Provider<BookingsRepository>((ref) {
  return BookingsRepository(ref.watch(dioProvider));
});

final myBookingsProvider =
    FutureProvider.autoDispose.family<List<Booking>, String>((ref, scope) {
  return ref.watch(bookingsRepositoryProvider).mine(scope);
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
  }) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/bookings',
      data: {
        'service_id': serviceId,
        'address': address,
        if (note != null && note.isNotEmpty) 'note': note,
      },
    );
    return Booking.fromJson(unwrapEnvelope(res) as Map<String, dynamic>);
  }

  Future<List<Booking>> mine(String scope) async {
    final res = await _dio
        .get<Map<String, dynamic>>('/api/v1/bookings/mine?scope=$scope');
    return _list(res);
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

  Future<void> advance(String id, String action) =>
      _dio.patch('/api/v1/bookings/$id/status', data: {'action': action});

  Future<void> cancel(String id) => _dio.post('/api/v1/bookings/$id/cancel');

  Future<void> rate(String id, int rating, String? review) =>
      _dio.post('/api/v1/bookings/$id/rate', data: {
        'rating': rating,
        if (review != null && review.isNotEmpty) 'review': review,
      });
}
