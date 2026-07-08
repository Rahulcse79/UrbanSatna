import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../domain/models.dart';

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository(ref.watch(dioProvider));
});

final categoriesProvider = FutureProvider.autoDispose<List<Category>>((ref) {
  return ref.watch(catalogRepositoryProvider).categories();
});

final servicesProvider = FutureProvider.autoDispose
    .family<List<Service>, String>((ref, categoryId) {
  return ref.watch(catalogRepositoryProvider).services(categoryId);
});

class CatalogRepository {
  const CatalogRepository(this._dio);

  final Dio _dio;

  Future<List<Category>> categories() async {
    final res = await _dio.get<Map<String, dynamic>>('/api/v1/categories');
    final data = unwrapEnvelope(res) as List<dynamic>;
    return data
        .map((c) => Category.fromJson(c as Map<String, dynamic>))
        .toList();
  }

  Future<List<Service>> services(String categoryId) async {
    final res = await _dio
        .get<Map<String, dynamic>>('/api/v1/categories/$categoryId/services');
    final data = unwrapEnvelope(res) as List<dynamic>;
    return data
        .map((s) => Service.fromJson(s as Map<String, dynamic>))
        .toList();
  }
}
