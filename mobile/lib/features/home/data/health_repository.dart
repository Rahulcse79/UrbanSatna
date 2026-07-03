import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/health_status.dart';

final healthRepositoryProvider = Provider<HealthRepository>((ref) {
  return HealthRepository(ref.watch(dioProvider));
});

final healthCheckProvider = FutureProvider.autoDispose<HealthStatus>((ref) {
  return ref.watch(healthRepositoryProvider).check();
});

class HealthRepository {
  const HealthRepository(this._dio);

  final Dio _dio;

  Future<HealthStatus> check() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/health',
      // 503 still carries a valid envelope with per-check detail.
      options: Options(validateStatus: (s) => s == 200 || s == 503),
    );
    return HealthStatus.fromJson(unwrapEnvelope(response));
  }
}
