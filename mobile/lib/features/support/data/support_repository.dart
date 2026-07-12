import 'dart:typed_data';

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
    this.attachmentMime,
  });

  factory SupportMessage.fromJson(Map<String, dynamic> json) =>
      SupportMessage(
        id: json['id'] as String,
        body: json['body'] as String,
        fromSupport: json['from_support'] as bool? ?? false,
        fromBot: json['from_bot'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        attachmentMime: json['attachment_mime'] as String?,
      );

  final String id;
  final String body;
  final bool fromSupport;

  /// Chatbot replies render with the bot identity (avatar + name).
  final bool fromBot;
  final DateTime createdAt;

  /// When set the message carries an image/video; fetch bytes from
  /// SupportRepository.attachment.
  final String? attachmentMime;

  bool get isImage => attachmentMime?.startsWith('image/') ?? false;
  bool get isVideo => attachmentMime?.startsWith('video/') ?? false;
  bool get hasAttachment => attachmentMime != null;
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

/// One page of the admin inbox.
typedef InboxPage = ({List<SupportThread> items, int total, int page});

/// Admin inbox keyed by page — server paginates 10/page.
final supportInboxProvider =
    FutureProvider.autoDispose.family<InboxPage, int>((ref, page) {
  return ref.watch(supportRepositoryProvider).inbox(page);
});

/// Attachment bytes cached per (userId, messageId). Messages are
/// immutable so the fetch is one-shot; the chat list polls, this doesn't.
final supportAttachmentProvider =
    FutureProvider.family<Uint8List?, (String?, String)>((ref, key) {
  final (userId, messageId) = key;
  return ref.read(supportRepositoryProvider).attachment(userId, messageId);
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

  /// Upload an image/video attachment. Passing `onProgress` shows a
  /// progress bar in the UI; the backend enforces the 10 MB limit again.
  Future<void> sendAttachment(
    String? userId,
    Uint8List bytes,
    String mime, {
    void Function(int sent, int total)? onProgress,
  }) {
    final path = userId == null
        ? '/api/v1/support/messages/attachment'
        : '/api/v1/admin/support/$userId/messages/attachment';
    return _dio.post(
      path,
      data: Stream.fromIterable([bytes]),
      options: Options(
        contentType: mime,
        headers: {Headers.contentLengthHeader: bytes.length},
        sendTimeout: const Duration(minutes: 2),
      ),
      onSendProgress: onProgress,
    );
  }

  /// Fetch bytes for one attachment on the given thread (null = my
  /// thread, matches the send/thread endpoints).
  Future<Uint8List?> attachment(String? userId, String messageId) async {
    final path = userId == null
        ? '/api/v1/support/messages/$messageId/attachment'
        : '/api/v1/admin/support/$userId/messages/$messageId/attachment';
    try {
      final res = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      return data == null ? null : Uint8List.fromList(data);
    } on DioException {
      return null;
    }
  }

  Future<InboxPage> inbox(int page) async {
    final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/admin/support/threads?page=$page');
    final data = unwrapEnvelope(res) as Map<String, dynamic>;
    return (
      items: (data['items'] as List<dynamic>)
          .map((t) => SupportThread.fromJson(t as Map<String, dynamic>))
          .toList(),
      total: data['total'] as int,
      page: data['page'] as int,
    );
  }
}
