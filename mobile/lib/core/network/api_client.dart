import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/server_url.dart';

final dioProvider = Provider<Dio>((ref) {
  // Rebuilds (and re-runs anything that depends on it) when the user
  // changes the server URL in Settings.
  return Dio(
    BaseOptions(
      baseUrl: ref.watch(serverUrlProvider),
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'accept': 'application/json'},
    ),
  );
});

/// Error carrying the stable `error.code` from the API envelope.
/// UI switches on [code], never on [message] (CLAUDE.md §7).
class ApiException implements Exception {
  const ApiException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'ApiException($code): $message';
}

/// Unwraps the `{ success, data, error, meta }` envelope every endpoint
/// returns. Throws [ApiException] when `success` is false.
Map<String, dynamic> unwrapEnvelope(Response<Map<String, dynamic>> response) {
  final body = response.data;
  if (body == null) {
    throw const ApiException('EMPTY_RESPONSE', 'Empty response body');
  }
  if (body['success'] == true) {
    return (body['data'] as Map<String, dynamic>?) ?? const {};
  }
  final error = body['error'] as Map<String, dynamic>?;
  throw ApiException(
    (error?['code'] as String?) ?? 'UNKNOWN_ERROR',
    (error?['message'] as String?) ?? 'Unknown error',
  );
}
