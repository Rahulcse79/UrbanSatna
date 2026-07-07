import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';

class SearchService {
  const SearchService({
    required this.id,
    required this.categoryId,
    required this.categoryName,
    required this.name,
    required this.pricePaise,
    required this.durationMin,
    this.description,
  });

  factory SearchService.fromJson(Map<String, dynamic> json) => SearchService(
        id: json['id'] as String,
        categoryId: json['category_id'] as String,
        categoryName: json['category_name'] as String,
        name: json['name'] as String,
        pricePaise: json['base_price_paise'] as int,
        durationMin: json['duration_min'] as int,
        description: json['description'] as String?,
      );

  final String id;
  final String categoryId;
  final String categoryName;
  final String name;
  final int pricePaise;
  final int durationMin;
  final String? description;

  String get priceLabel => '₹${(pricePaise / 100).toStringAsFixed(0)}';
}

typedef SearchArgs = ({String q, int? maxPricePaise});

final serviceSearchProvider = FutureProvider.autoDispose
    .family<List<SearchService>, SearchArgs>((ref, args) async {
  final dio = ref.watch(dioProvider);
  final maxPrice = args.maxPricePaise != null
      ? '&max_price_paise=${args.maxPricePaise}'
      : '';
  final res = await dio.get<Map<String, dynamic>>(
      '/api/v1/services/search?q=${Uri.encodeComponent(args.q)}$maxPrice');
  return (unwrapEnvelope(res) as List<dynamic>)
      .map((s) => SearchService.fromJson(s as Map<String, dynamic>))
      .toList();
});

const _priceCaps = <int?>[null, 20000, 50000, 100000];

/// Advanced search across every service — name, description, category,
/// with quick price-cap chips. Tap a result to book from its category.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, required this.initialQuery});

  final String initialQuery;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _query =
      TextEditingController(text: widget.initialQuery);
  late String _submitted = widget.initialQuery;
  int? _maxPrice;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final results = ref
        .watch(serviceSearchProvider((q: _submitted, maxPricePaise: _maxPrice)));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.searchResults)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: _query,
              autofocus: widget.initialQuery.isEmpty,
              onSubmitted: (v) => setState(() => _submitted = v.trim()),
              decoration: InputDecoration(
                hintText: l10n.searchAllServices,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24)),
              ),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [
                for (final cap in _priceCaps)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cap == null
                          ? l10n.anyPrice
                          : '≤ ₹${cap ~/ 100}'),
                      selected: _maxPrice == cap,
                      onSelected: (_) => setState(() => _maxPrice = cap),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: results.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (items) => items.isEmpty
                  ? Center(child: Text(l10n.noResults))
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final service = items[i];
                        return Card(
                          elevation: 0,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            title: Text(service.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(
                              '${service.categoryName}'
                              '${service.description != null ? ' · ${service.description}' : ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(service.priceLabel,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w700)),
                                Text('${service.durationMin} min',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall),
                              ],
                            ),
                            onTap: () => context.push(
                                '/category/${service.categoryId}?name=${Uri.encodeComponent(service.categoryName)}'),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
