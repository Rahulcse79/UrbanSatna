import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../home/presentation/home_screen.dart' show categoryIcon;

class AdminCategory {
  const AdminCategory({
    required this.id,
    required this.name,
    required this.isActive,
    this.icon,
  });

  factory AdminCategory.fromJson(Map<String, dynamic> json) => AdminCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        isActive: json['is_active'] as bool? ?? true,
        icon: json['icon'] as String?,
      );

  final String id;
  final String name;
  final bool isActive;
  final String? icon;
}

class AdminService {
  const AdminService({
    required this.id,
    required this.name,
    required this.pricePaise,
    required this.durationMin,
    required this.isActive,
  });

  factory AdminService.fromJson(Map<String, dynamic> json) => AdminService(
        id: json['id'] as String,
        name: json['name'] as String,
        pricePaise: json['base_price_paise'] as int,
        durationMin: json['duration_min'] as int,
        isActive: json['is_active'] as bool? ?? true,
      );

  final String id;
  final String name;
  final int pricePaise;
  final int durationMin;
  final bool isActive;

  String get priceLabel => '₹${(pricePaise / 100).toStringAsFixed(0)}';
}

final adminCategoriesProvider =
    FutureProvider.autoDispose<List<AdminCategory>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res =
      await dio.get<Map<String, dynamic>>('/api/v1/admin/catalog/categories');
  final data = unwrapEnvelope(res) as List<dynamic>;
  return data
      .map((c) => AdminCategory.fromJson(c as Map<String, dynamic>))
      .toList();
});

final adminServicesProvider = FutureProvider.autoDispose
    .family<List<AdminService>, String>((ref, categoryId) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get<Map<String, dynamic>>(
      '/api/v1/admin/catalog/categories/$categoryId/services');
  final data = unwrapEnvelope(res) as List<dynamic>;
  return data
      .map((s) => AdminService.fromJson(s as Map<String, dynamic>))
      .toList();
});

/// Admin: the catalog is pure data — add or switch off categories and
/// services from the phone, live for every user (CLAUDE.md rule 2).
class CatalogManagerScreen extends ConsumerWidget {
  const CatalogManagerScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(adminCategoriesProvider);
    ref.invalidate(categoriesProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(adminCategoriesProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageCatalog)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l10n.addCategory),
        onPressed: () => _addCategory(context, ref),
      ),
      body: categories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (items) => RefreshIndicator(
          onRefresh: () async => _refresh(ref),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 88),
            children: [
              for (final category in items)
                _CategoryTile(category: category, onChanged: () => _refresh(ref)),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _addCategory(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = TextEditingController();
    final icon = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.addCategory),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: InputDecoration(
                labelText: l10n.categoryNameLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: icon,
              decoration: InputDecoration(
                labelText: l10n.iconKeyLabel,
                helperText: 'electrician · plumber · ac · cleaning …',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (submitted != true || name.text.trim().isEmpty) return;
    try {
      await ref.read(dioProvider).post<Map<String, dynamic>>(
        '/api/v1/categories',
        data: {
          'name': name.text.trim(),
          if (icon.text.trim().isNotEmpty) 'icon': icon.text.trim(),
        },
      );
      _refresh(ref);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}

class _CategoryTile extends ConsumerWidget {
  const _CategoryTile({required this.category, required this.onChanged});

  final AdminCategory category;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final services = ref.watch(adminServicesProvider(category.id));
    return ExpansionTile(
      leading: Icon(categoryIcon(category.icon)),
      title: Text(
        category.name,
        style: TextStyle(
          decoration: category.isActive ? null : TextDecoration.lineThrough,
        ),
      ),
      trailing: Switch(
        value: category.isActive,
        onChanged: (v) async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await ref.read(dioProvider).patch<Map<String, dynamic>>(
              '/api/v1/categories/${category.id}',
              data: {'is_active': v},
            );
            onChanged();
          } catch (e) {
            messenger
                .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
          }
        },
      ),
      children: [
        services.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => ListTile(title: Text(apiErrorMessage(e))),
          data: (items) => Column(
            children: [
              for (final service in items)
                ListTile(
                  dense: true,
                  title: Text(
                    service.name,
                    style: TextStyle(
                      decoration:
                          service.isActive ? null : TextDecoration.lineThrough,
                    ),
                  ),
                  subtitle: Text(
                      '${service.priceLabel} · ${service.durationMin} min'),
                  trailing: Switch(
                    value: service.isActive,
                    onChanged: (v) async {
                      final messenger = ScaffoldMessenger.of(context);
                      try {
                        await ref.read(dioProvider).patch<Map<String, dynamic>>(
                          '/api/v1/services/${service.id}',
                          data: {'is_active': v},
                        );
                        ref.invalidate(adminServicesProvider(category.id));
                      } catch (e) {
                        messenger.showSnackBar(
                            SnackBar(content: Text(apiErrorMessage(e))));
                      }
                    },
                  ),
                ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.add),
                title: Text(l10n.addService),
                onTap: () => _addService(context, ref),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addService(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = TextEditingController();
    final price = TextEditingController();
    final duration = TextEditingController(text: '60');
    final description = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.addService),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: InputDecoration(
                  labelText: l10n.serviceNameLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.priceRupeesLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: duration,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.durationMinLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: description,
                decoration: InputDecoration(
                  labelText: l10n.descriptionLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (submitted != true || name.text.trim().isEmpty) return;
    final rupees = double.tryParse(price.text.trim());
    final minutes = int.tryParse(duration.text.trim()) ?? 60;
    if (rupees == null || rupees <= 0) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.invalidNumber)));
      return;
    }
    try {
      await ref.read(dioProvider).post<Map<String, dynamic>>(
        '/api/v1/services',
        data: {
          'category_id': category.id,
          'name': name.text.trim(),
          'base_price_paise': (rupees * 100).round(),
          'duration_min': minutes,
          if (description.text.trim().isNotEmpty)
            'description': description.text.trim(),
        },
      );
      ref.invalidate(adminServicesProvider(category.id));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}
