import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/server_url.dart';

/// Tokens + roles held in memory while logged in; persisted in secure
/// storage across restarts.
class AuthTokens {
  const AuthTokens({
    required this.access,
    required this.refresh,
    required this.roles,
  });

  final String access;
  final String refresh;
  final List<String> roles;

  bool get isWorker => roles.contains('worker');
}

const _storage = FlutterSecureStorage();

Future<AuthTokens?> loadStoredTokens() async {
  final access = await _storage.read(key: 'access_token');
  final refresh = await _storage.read(key: 'refresh_token');
  final roles = await _storage.read(key: 'roles');
  if (access == null || refresh == null) return null;
  return AuthTokens(
    access: access,
    refresh: refresh,
    roles: (roles ?? '').split(',').where((r) => r.isNotEmpty).toList(),
  );
}

/// Overridden in main() with the tokens read from secure storage.
final initialTokensProvider = Provider<AuthTokens?>((ref) => null);

final authControllerProvider =
    NotifierProvider<AuthController, AuthTokens?>(AuthController.new);

class AuthController extends Notifier<AuthTokens?> {
  Future<bool>? _refreshing;

  @override
  AuthTokens? build() => ref.watch(initialTokensProvider);

  /// Bare client for auth endpoints only — no interceptors, so a 401
  /// during refresh can never recurse.
  Dio get _dio => Dio(BaseOptions(
        baseUrl: ref.read(serverUrlProvider),
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 10),
      ));

  /// Returns the dev OTP when the backend runs with DEV_RETURN_OTP=true.
  Future<String?> requestOtp(String phone) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/otp/request',
      data: {'phone': phone},
    );
    return (res.data?['data'] as Map<String, dynamic>?)?['dev_otp'] as String?;
  }

  Future<void> verifyOtp(String phone, String otp) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '/api/v1/auth/otp/verify',
      data: {'phone': phone, 'otp': otp, 'device_name': 'mobile'},
    );
    await _store(res.data?['data'] as Map<String, dynamic>);
  }

  /// Single-flight refresh; concurrent 401s share one attempt.
  Future<bool> tryRefresh() {
    return _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);
  }

  Future<bool> _doRefresh() async {
    final current = state;
    if (current == null) return false;
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refresh_token': current.refresh},
      );
      await _store(res.data?['data'] as Map<String, dynamic>);
      return true;
    } on DioException {
      await logout(callApi: false);
      return false;
    }
  }

  Future<void> logout({bool callApi = true}) async {
    final current = state;
    if (callApi && current != null) {
      try {
        await _dio.post<void>(
          '/api/v1/auth/logout',
          options: Options(
            headers: {'authorization': 'Bearer ${current.access}'},
          ),
        );
      } on DioException {
        // Best-effort: local logout must succeed even offline.
      }
    }
    await _storage.deleteAll();
    state = null;
  }

  Future<void> _store(Map<String, dynamic>? data) async {
    if (data == null) return;
    final roles =
        (data['roles'] as List<dynamic>? ?? []).cast<String>().toList();
    final tokens = AuthTokens(
      access: data['access_token'] as String,
      refresh: data['refresh_token'] as String,
      roles: roles,
    );
    await _storage.write(key: 'access_token', value: tokens.access);
    await _storage.write(key: 'refresh_token', value: tokens.refresh);
    await _storage.write(key: 'roles', value: roles.join(','));
    state = tokens;
  }
}
