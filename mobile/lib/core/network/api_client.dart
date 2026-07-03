import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../config/server_url.dart';

final dioProvider = Provider<Dio>((ref) {
  // Rebuilds when the user changes the server URL in Settings.
  final dio = Dio(
    BaseOptions(
      baseUrl: ref.watch(serverUrlProvider),
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
      headers: {'accept': 'application/json'},
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final tokens = ref.read(authControllerProvider);
        if (tokens != null) {
          options.headers['authorization'] = 'Bearer ${tokens.access}';
        }
        handler.next(options);
      },
      onError: (err, handler) async {
        final isAuthCall = err.requestOptions.path.contains('/auth/');
        final alreadyRetried = err.requestOptions.extra['retried'] == true;
        if (err.response?.statusCode == 401 && !isAuthCall && !alreadyRetried) {
          final refreshed =
              await ref.read(authControllerProvider.notifier).tryRefresh();
          if (refreshed) {
            final tokens = ref.read(authControllerProvider);
            final opts = err.requestOptions
              ..extra['retried'] = true
              ..headers['authorization'] = 'Bearer ${tokens?.access}';
            try {
              return handler.resolve(await dio.fetch(opts));
            } on DioException catch (e) {
              return handler.next(e);
            }
          }
        }
        handler.next(err);
      },
    ),
  );
  return dio;
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
dynamic unwrapEnvelope(Response<Map<String, dynamic>> response) {
  final body = response.data;
  if (body == null) {
    throw const ApiException('EMPTY_RESPONSE', 'Empty response body');
  }
  if (body['success'] == true) {
    return body['data'];
  }
  final error = body['error'] as Map<String, dynamic>?;
  throw ApiException(
    (error?['code'] as String?) ?? 'UNKNOWN_ERROR',
    (error?['message'] as String?) ?? 'Unknown error',
  );
}

/// Extracts the envelope error message from a Dio failure (4xx/5xx),
/// falling back to a generic network message.
String apiErrorMessage(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map<String, dynamic>) {
      final message = (data['error'] as Map<String, dynamic>?)?['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return 'Network error — check the server connection';
  }
  if (error is ApiException) return error.message;
  return 'Something went wrong';
}
