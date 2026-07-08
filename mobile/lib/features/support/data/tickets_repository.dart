import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class Ticket {
  const Ticket({
    required this.id,
    required this.subject,
    required this.message,
    required this.status,
    required this.createdAt,
    this.phone,
    this.fullName,
    this.bookingId,
    this.resolution,
  });

  factory Ticket.fromJson(Map<String, dynamic> json) => Ticket(
        id: json['id'] as String,
        subject: json['subject'] as String,
        message: json['message'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        phone: json['phone'] as String?,
        fullName: json['full_name'] as String?,
        bookingId: json['booking_id'] as String?,
        resolution: json['resolution'] as String?,
      );

  final String id;
  final String subject;
  final String message;
  final String status;
  final DateTime createdAt;
  final String? phone;
  final String? fullName;
  final String? bookingId;
  final String? resolution;

  bool get open => status == 'open';
  bool get resolved => status == 'resolved';
  bool get closed => status == 'closed';
}

final ticketsRepositoryProvider = Provider<TicketsRepository>((ref) {
  return TicketsRepository(ref.watch(dioProvider));
});

final myTicketsProvider = FutureProvider.autoDispose<List<Ticket>>((ref) {
  return ref.watch(ticketsRepositoryProvider).mine();
});

final adminTicketsProvider =
    FutureProvider.autoDispose.family<List<Ticket>, String>((ref, status) {
  return ref.watch(ticketsRepositoryProvider).adminQueue(status);
});

class TicketsRepository {
  const TicketsRepository(this._dio);

  final Dio _dio;

  List<Ticket> _list(Response<Map<String, dynamic>> res) =>
      (unwrapEnvelope(res) as List<dynamic>)
          .map((t) => Ticket.fromJson(t as Map<String, dynamic>))
          .toList();

  Future<Ticket> create({
    required String subject,
    required String message,
    String? bookingId,
  }) async {
    final res = await _dio.post<Map<String, dynamic>>('/api/v1/tickets', data: {
      'subject': subject,
      'message': message,
      if (bookingId != null) 'booking_id': bookingId,
    });
    return Ticket.fromJson(unwrapEnvelope(res) as Map<String, dynamic>);
  }

  Future<List<Ticket>> mine() async =>
      _list(await _dio.get<Map<String, dynamic>>('/api/v1/tickets/mine'));

  /// Admin queue returns a paginated object `{items, total, page,
  /// per_page}`, not a bare list — parse `items` (fixes tickets being
  /// invisible in the admin account).
  Future<List<Ticket>> adminQueue(String status, {int page = 1}) async {
    final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/admin/tickets?status=$status&page=$page');
    final data = unwrapEnvelope(res) as Map<String, dynamic>;
    return (data['items'] as List<dynamic>)
        .map((t) => Ticket.fromJson(t as Map<String, dynamic>))
        .toList();
  }

  Future<void> resolve(String id, String resolution) =>
      _dio.post('/api/v1/admin/tickets/$id/resolve',
          data: {'resolution': resolution});

  Future<void> reopen(String id) =>
      _dio.post('/api/v1/tickets/$id/reopen');

  Future<void> close(String id) =>
      _dio.post('/api/v1/admin/tickets/$id/close');
}
