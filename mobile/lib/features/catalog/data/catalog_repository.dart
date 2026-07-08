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

/// One 10-row page of a category's services plus pagination info from
/// the envelope's `meta` (page/per_page/total).
class ServicesPage {
  const ServicesPage({
    required this.items,
    required this.total,
    required this.page,
    required this.perPage,
  });

  final List<Service> items;
  final int total;
  final int page;
  final int perPage;

  int get totalPages => total <= 0 ? 1 : (total + perPage - 1) ~/ perPage;
}

typedef ServicesArgs = ({String categoryId, int page});

final servicesProvider = FutureProvider.autoDispose
    .family<ServicesPage, ServicesArgs>((ref, args) {
  return ref
      .watch(catalogRepositoryProvider)
      .services(args.categoryId, page: args.page);
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

  Future<ServicesPage> services(String categoryId, {int page = 1}) async {
    final res = await _dio.get<Map<String, dynamic>>(
        '/api/v1/categories/$categoryId/services?page=$page');
    final items = (unwrapEnvelope(res) as List<dynamic>)
        .map((s) => Service.fromJson(s as Map<String, dynamic>))
        .toList();
    final meta = res.data?['meta'] as Map<String, dynamic>? ?? const {};
    return ServicesPage(
      items: items,
      total: meta['total'] as int? ?? items.length,
      page: meta['page'] as int? ?? page,
      perPage: meta['per_page'] as int? ?? 10,
    );
  }
}
