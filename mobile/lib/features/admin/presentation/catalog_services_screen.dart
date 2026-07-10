import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../catalog/data/catalog_repository.dart';
import 'catalog_manager_screen.dart' show CatalogPager;

class AdminService {
  const AdminService({
    required this.id,
    required this.name,
    required this.pricePaise,
    required this.durationMin,
    required this.isActive,
    this.description,
  });

  factory AdminService.fromJson(Map<String, dynamic> json) => AdminService(
        id: json['id'] as String,
        name: json['name'] as String,
        pricePaise: json['base_price_paise'] as int,
        durationMin: json['duration_min'] as int,
        isActive: json['is_active'] as bool? ?? true,
        description: json['description'] as String?,
      );

  final String id;
  final String name;
  final int pricePaise;
  final int durationMin;
  final bool isActive;
  final String? description;

  String get priceLabel => '₹${(pricePaise / 100).toStringAsFixed(0)}';
}

typedef ServicesPage = ({List<AdminService> items, int total, int page});

final adminServicesProvider = FutureProvider.autoDispose
    .family<ServicesPage, (String, int)>((ref, key) async {
  final (categoryId, page) = key;
  final dio = ref.watch(dioProvider);
  final res = await dio.get<Map<String, dynamic>>(
      '/api/v1/admin/catalog/categories/$categoryId/services?page=$page');
  final data = unwrapEnvelope(res) as Map<String, dynamic>;
  return (
    items: (data['items'] as List<dynamic>)
        .map((s) => AdminService.fromJson(s as Map<String, dynamic>))
        .toList(),
    total: data['total'] as int,
    page: data['page'] as int,
  );
});

/// Services of one category, paginated 10/page, with add + activate toggles.
class CatalogServicesScreen extends ConsumerStatefulWidget {
  const CatalogServicesScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  final String categoryId;
  final String categoryName;

  @override
  ConsumerState<CatalogServicesScreen> createState() =>
      _CatalogServicesScreenState();
}

class _CatalogServicesScreenState extends ConsumerState<CatalogServicesScreen> {
  int _page = 1;

  void _refresh() {
    ref.invalidate(adminServicesProvider);
    ref.invalidate(categoriesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final services =
        ref.watch(adminServicesProvider((widget.categoryId, _page)));

    return Scaffold(
      appBar: AppBar(title: Text(widget.categoryName)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l10n.addService),
        onPressed: _addService,
      ),
      body: Column(
        children: [
          Expanded(
            child: services.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (page) {
                if (page.items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.design_services_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(l10n.addService,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async => _refresh(),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                    itemCount: page.items.length,
                    itemBuilder: (context, i) => _ServiceCard(
                      service: page.items[i],
                      onChanged: _refresh,
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: services.maybeWhen(
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

  Future<void> _addService() async {
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
              _field(name, l10n.serviceNameLabel),
              const SizedBox(height: 12),
              _field(price, l10n.priceRupeesLabel, number: true),
              const SizedBox(height: 12),
              _field(duration, l10n.durationMinLabel, number: true),
              const SizedBox(height: 12),
              _field(description, l10n.descriptionLabel),
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
          'category_id': widget.categoryId,
          'name': name.text.trim(),
          'base_price_paise': (rupees * 100).round(),
          'duration_min': minutes,
          if (description.text.trim().isNotEmpty)
            'description': description.text.trim(),
        },
      );
      _refresh();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Widget _field(TextEditingController controller, String label,
      {bool number = false}) {
    return TextField(
      controller: controller,
      keyboardType: number ? TextInputType.number : null,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none),
      ),
    );
  }
}

/// A service as a card: name + optional description, price/duration chips,
/// status, and an activate toggle.
class _ServiceCard extends ConsumerWidget {
  const _ServiceCard({required this.service, required this.onChanged});

  final AdminService service;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final description = (service.description ?? '').trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  service.name,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: service.isActive
                        ? null
                        : TextDecoration.lineThrough,
                    color:
                        service.isActive ? null : scheme.onSurfaceVariant,
                  ),
                ),
              ),
              Switch(
                value: service.isActive,
                onChanged: (v) async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(dioProvider).patch<Map<String, dynamic>>(
                      '/api/v1/services/${service.id}',
                      data: {'is_active': v},
                    );
                    onChanged();
                  } catch (e) {
                    messenger.showSnackBar(
                        SnackBar(content: Text(apiErrorMessage(e))));
                  }
                },
              ),
            ],
          ),
          if (description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2, bottom: 4),
              child: Text(description,
                  style:
                      text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Chip(
                icon: Icons.currency_rupee,
                label: service.priceLabel,
                color: scheme.primary,
              ),
              _Chip(
                icon: Icons.schedule,
                label: '${service.durationMin} min',
                color: scheme.tertiary,
              ),
              _Chip(
                icon: service.isActive
                    ? Icons.check_circle_outline
                    : Icons.pause_circle_outline,
                label:
                    service.isActive ? l10n.activeLabel : l10n.inactiveLabel,
                color:
                    service.isActive ? Colors.green.shade600 : scheme.outline,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color)),
        ],
      ),
    );
  }
}
