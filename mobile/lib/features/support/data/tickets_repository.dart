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

  /// SLA-style priority for the support queue, derived honestly from how
  /// long an open ticket has been waiting (there's no priority field yet).
  /// Only open tickets carry a priority.
  TicketPriority get priority {
    if (!open) return TicketPriority.none;
    final waited = DateTime.now().difference(createdAt);
    if (waited >= const Duration(hours: 48)) return TicketPriority.urgent;
    if (waited >= const Duration(hours: 24)) return TicketPriority.waiting;
    return TicketPriority.none;
  }
}

enum TicketPriority { none, waiting, urgent }

final ticketsRepositoryProvider = Provider<TicketsRepository>((ref) {
  return TicketsRepository(ref.watch(dioProvider));
});

/// One page of the admin queue.
typedef TicketsPage = ({List<Ticket> items, int total, int page});

/// My tickets keyed by page — server paginates 10/page.
final myTicketsProvider =
    FutureProvider.autoDispose.family<TicketsPage, int>((ref, page) {
  return ref.watch(ticketsRepositoryProvider).mine(page);
});

/// Admin queue keyed by (status, page) — server paginates 10/page.
final adminTicketsProvider = FutureProvider.autoDispose
    .family<TicketsPage, (String, int)>((ref, key) {
  final (status, page) = key;
  return ref.watch(ticketsRepositoryProvider).adminQueue(status, page);
});

class TicketsRepository {
  const TicketsRepository(this._dio);

  final Dio _dio;

  TicketsPage _page(Response<Map<String, dynamic>> res) {
    final data = unwrapEnvelope(res) as Map<String, dynamic>;
    return (
      items: (data['items'] as List<dynamic>)
          .map((t) => Ticket.fromJson(t as Map<String, dynamic>))
          .toList(),
      total: data['total'] as int,
      page: data['page'] as int,
    );
  }

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

  Future<TicketsPage> mine(int page) async => _page(await _dio
      .get<Map<String, dynamic>>('/api/v1/tickets/mine?page=$page'));

  Future<TicketsPage> adminQueue(String status, int page) async =>
      _page(await _dio.get<Map<String, dynamic>>(
          '/api/v1/admin/tickets?status=$status&page=$page'));

  Future<void> resolve(String id, String resolution) =>
      _dio.post('/api/v1/admin/tickets/$id/resolve',
          data: {'resolution': resolution});

  Future<void> reopen(String id) =>
      _dio.post('/api/v1/tickets/$id/reopen');

  Future<void> close(String id) =>
      _dio.post('/api/v1/admin/tickets/$id/close');
}
