import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.bookingId,
    required this.senderId,
    required this.createdAt,
    this.senderName,
    this.body,
    this.hasAttachment = false,
    this.attachmentMime,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        bookingId: json['booking_id'] as String,
        senderId: json['sender_id'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        senderName: json['sender_name'] as String?,
        body: json['body'] as String?,
        hasAttachment: json['has_attachment'] as bool? ?? false,
        attachmentMime: json['attachment_mime'] as String?,
      );

  final String id;
  final String bookingId;
  final String senderId;
  final DateTime createdAt;
  final String? senderName;
  final String? body;
  final bool hasAttachment;
  final String? attachmentMime;

  bool get isImage => attachmentMime?.startsWith('image/') ?? false;
  bool get isVideo => attachmentMime?.startsWith('video/') ?? false;
}

final chatRepositoryProvider = Provider<ChatRepository>((ref) {
  return ChatRepository(ref.watch(dioProvider));
});

final chatMessagesProvider = FutureProvider.autoDispose
    .family<List<ChatMessage>, String>((ref, bookingId) {
  return ref.watch(chatRepositoryProvider).list(bookingId);
});

/// Attachment bytes cached per message id — the chat list polls, but
/// attachments are immutable so they are fetched once.
final chatAttachmentProvider =
    FutureProvider.family<Uint8List?, (String, String)>((ref, key) {
  final (bookingId, messageId) = key;
  return ref.read(chatRepositoryProvider).attachment(bookingId, messageId);
});

class ChatRepository {
  const ChatRepository(this._dio);

  final Dio _dio;

  Future<List<ChatMessage>> list(String bookingId) async {
    final res = await _dio
        .get<Map<String, dynamic>>('/api/v1/bookings/$bookingId/messages');
    return (unwrapEnvelope(res) as List<dynamic>)
        .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
        .toList();
  }

  Future<void> sendText(String bookingId, String body) =>
      _dio.post('/api/v1/bookings/$bookingId/messages', data: {'body': body});

  Future<void> sendAttachment(
    String bookingId,
    Uint8List bytes,
    String mime,
  ) =>
      _dio.post(
        '/api/v1/bookings/$bookingId/messages/attachment',
        data: Stream.fromIterable([bytes]),
        options: Options(
          contentType: mime,
          headers: {Headers.contentLengthHeader: bytes.length},
          sendTimeout: const Duration(minutes: 2),
        ),
      );

  Future<Uint8List?> attachment(String bookingId, String messageId) async {
    try {
      final res = await _dio.get<List<int>>(
        '/api/v1/bookings/$bookingId/messages/$messageId/attachment',
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      return data == null ? null : Uint8List.fromList(data);
    } on DioException {
      return null;
    }
  }
}
