import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.body,
    required this.fromSupport,
    required this.fromBot,
    required this.createdAt,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) =>
      SupportMessage(
        id: json['id'] as String,
        body: json['body'] as String,
        fromSupport: json['from_support'] as bool? ?? false,
        fromBot: json['from_bot'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      );

  final String id;
  final String body;
  final bool fromSupport;

  /// Chatbot replies render with the bot identity (avatar + name).
  final bool fromBot;
  final DateTime createdAt;
}

class SupportThread {
  const SupportThread({
    required this.userId,
    required this.phone,
    required this.lastBody,
    required this.lastAt,
    required this.awaitingReply,
    this.fullName,
  });

  factory SupportThread.fromJson(Map<String, dynamic> json) => SupportThread(
        userId: json['user_id'] as String,
        phone: json['phone'] as String,
        lastBody: json['last_body'] as String,
        lastAt: DateTime.parse(json['last_at'] as String).toLocal(),
        awaitingReply: json['awaiting_reply'] as bool? ?? false,
        fullName: json['full_name'] as String?,
      );

  final String userId;
  final String phone;
  final String lastBody;
  final DateTime lastAt;
  final bool awaitingReply;
  final String? fullName;
}

final supportRepositoryProvider = Provider<SupportRepository>((ref) {
  return SupportRepository(ref.watch(dioProvider));
});

/// My own thread; for admins, pass the customer's userId instead.
final supportThreadProvider = FutureProvider.autoDispose
    .family<List<SupportMessage>, String?>((ref, userId) {
  return ref.watch(supportRepositoryProvider).thread(userId);
});

final supportInboxProvider =
    FutureProvider.autoDispose<List<SupportThread>>((ref) {
  return ref.watch(supportRepositoryProvider).inbox();
});

class SupportRepository {
  const SupportRepository(this._dio);

  final Dio _dio;

  Future<List<SupportMessage>> thread(String? userId) async {
    final path = userId == null
        ? '/api/v1/support/messages'
        : '/api/v1/admin/support/$userId/messages';
    final res = await _dio.get<Map<String, dynamic>>(path);
    return (unwrapEnvelope(res) as List<dynamic>)
        .map((m) => SupportMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<void> send(String? userId, String body) {
    final path = userId == null
        ? '/api/v1/support/messages'
        : '/api/v1/admin/support/$userId/messages';
    return _dio.post(path, data: {'body': body});
  }

  Future<List<SupportThread>> inbox() async {
    final res = await _dio
        .get<Map<String, dynamic>>('/api/v1/admin/support/threads');
    return (unwrapEnvelope(res) as List<dynamic>)
        .map((t) => SupportThread.fromJson(t as Map<String, dynamic>))
        .toList();
  }
}
