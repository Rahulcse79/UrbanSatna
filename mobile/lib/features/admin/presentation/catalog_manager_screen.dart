import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../catalog/data/catalog_repository.dart';
import '../../home/presentation/home_screen.dart' show categoryIcon;
import 'catalog_services_screen.dart';

class AdminCategory {
  const AdminCategory({
    required this.id,
    required this.name,
    required this.isActive,
    required this.serviceCount,
    this.icon,
  });

  factory AdminCategory.fromJson(Map<String, dynamic> json) => AdminCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        isActive: json['is_active'] as bool? ?? true,
        serviceCount: json['service_count'] as int? ?? 0,
        icon: json['icon'] as String?,
      );

  final String id;
  final String name;
  final bool isActive;
  final int serviceCount;
  final String? icon;
}

typedef CategoriesPage = ({List<AdminCategory> items, int total, int page});

final adminCategoriesProvider =
    FutureProvider.autoDispose.family<CategoriesPage, int>((ref, page) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get<Map<String, dynamic>>(
      '/api/v1/admin/catalog/categories?page=$page');
  final data = unwrapEnvelope(res) as Map<String, dynamic>;
  return (
    items: (data['items'] as List<dynamic>)
        .map((c) => AdminCategory.fromJson(c as Map<String, dynamic>))
        .toList(),
    total: data['total'] as int,
    page: data['page'] as int,
  );
});

/// Admin: the catalog is pure data — add or switch off categories and
/// services from the phone, live for every user (CLAUDE.md rule 2).
/// Categories paginate 10/page; tap one to manage its services.
class CatalogManagerScreen extends ConsumerStatefulWidget {
  const CatalogManagerScreen({super.key});

  @override
  ConsumerState<CatalogManagerScreen> createState() =>
      _CatalogManagerScreenState();
}

class _CatalogManagerScreenState extends ConsumerState<CatalogManagerScreen> {
  int _page = 1;

  void _refresh() {
    ref.invalidate(adminCategoriesProvider);
    ref.invalidate(categoriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(adminCategoriesProvider(_page));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageCatalog)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l10n.addCategory),
        onPressed: _addCategory,
      ),
      body: Column(
        children: [
          Expanded(
            child: categories.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (page) => RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  itemCount: page.items.length,
                  itemBuilder: (context, i) => _CategoryCard(
                    category: page.items[i],
                    onChanged: _refresh,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: categories.maybeWhen(
              data: (page) => CatalogPager(
                page: _page,
                total: page.total,
                onPrev: () => setState(() => _page--),
                onNext: () => setState(() => _page++),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _addCategory() async {
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
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: icon,
              decoration: InputDecoration(
                labelText: l10n.iconKeyLabel,
                helperText: 'electrician · plumber · ac · cleaning …',
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
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
      _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}

/// A category as a card: coloured icon, name, service count + status,
/// active toggle; the body opens the category's services.
class _CategoryCard extends ConsumerWidget {
  const _CategoryCard({required this.category, required this.onChanged});

  final AdminCategory category;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = category.isActive ? scheme.primary : scheme.outline;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CatalogServicesScreen(
              categoryId: category.id,
              categoryName: category.name,
            ),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(categoryIcon(category.icon), color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      category.name,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: category.isActive
                            ? null
                            : TextDecoration.lineThrough,
                        color: category.isActive
                            ? null
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Text(
                          l10n.servicesCountLabel(category.serviceCount),
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        Text('  ·  ',
                            style: text.bodySmall
                                ?.copyWith(color: scheme.outline)),
                        Text(
                          category.isActive
                              ? l10n.activeLabel
                              : l10n.inactiveLabel,
                          style: text.bodySmall?.copyWith(
                            color: category.isActive
                                ? Colors.green.shade600
                                : scheme.outline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Switch(
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
                    messenger.showSnackBar(
                        SnackBar(content: Text(apiErrorMessage(e))));
                  }
                },
              ),
              Icon(Icons.chevron_right, color: scheme.outline),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shared Prev / "page / lastPage" / Next control (10 rows per page).
class CatalogPager extends StatelessWidget {
  const CatalogPager({
    super.key,
    required this.page,
    required this.total,
    required this.onPrev,
    required this.onNext,
  });

  final int page;
  final int total;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lastPage = (total / 10).ceil().clamp(1, 99999);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.chevron_left, size: 18),
            label: Text(l10n.prevLabel),
            onPressed: page > 1 ? onPrev : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('$page / $lastPage',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.chevron_right, size: 18),
            label: Text(l10n.nextLabel),
            onPressed: page < lastPage ? onNext : null,
          ),
        ],
      ),
    );
  }
}
