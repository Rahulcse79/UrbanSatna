import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/data/bookings_repository.dart';
import '../../bookings/presentation/bookings_screen.dart'
    show statusColor, statusLabel;
import '../../catalog/data/catalog_repository.dart';
import '../../catalog/domain/models.dart';
import '../../profile/presentation/profile_screen.dart' show meProvider;
import '../../shell/current_tab.dart';

IconData categoryIcon(String? key) => switch (key) {
      'electrician' => Icons.electrical_services,
      'plumber' => Icons.plumbing,
      'ac' => Icons.ac_unit,
      'appliance' => Icons.kitchen,
      'cleaning' => Icons.cleaning_services,
      'carpenter' => Icons.carpenter,
      _ => Icons.home_repair_service,
    };

/// Tinted tile palette: each category gets its own soft color so the
/// grid feels alive (PRODUCT.md §6, "signature screens").
(Color, Color) categoryTint(BuildContext context, int index) {
  const swatches = <MaterialColor>[
    Colors.indigo,
    Colors.blue,
    Colors.cyan,
    Colors.orange,
    Colors.green,
    Colors.pink,
    Colors.purple,
    Colors.teal,
  ];
  final s = swatches[index % swatches.length];
  final dark = Theme.of(context).brightness == Brightness.dark;
  return dark
      ? (s.shade900.withValues(alpha: 0.35), s.shade200)
      : (s.shade50, s.shade700);
}

/// Live GPS city for the header chip: uses the platform geocoder (no
/// API key). Only runs when permission was already granted (the profile
/// gate asks for it); silently falls back to the admin city label.
final gpsCityProvider = FutureProvider.autoDispose<String?>((ref) async {
  try {
    final permission = await Geolocator.checkPermission();
    if (permission != LocationPermission.whileInUse &&
        permission != LocationPermission.always) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 8),
      ),
    );
    final placemarks =
        await placemarkFromCoordinates(position.latitude, position.longitude);
    if (placemarks.isEmpty) return null;
    final place = placemarks.first;
    final city = (place.locality?.isNotEmpty ?? false)
        ? place.locality
        : place.subAdministrativeArea;
    if (city == null || city.isEmpty) return null;
    final state = place.administrativeArea;
    return (state == null || state.isEmpty) ? city : '$city, $state';
  } catch (_) {
    return null;
  }
});

/// Customer home v2: location chip, greeting, search, promo banner,
/// tinted category grid, pinned active-booking bar.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            categories.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _Unreachable(
                onRetry: () => ref.invalidate(categoriesProvider),
                onSetServerUrl: () => context.push('/settings'),
              ),
              data: (items) {
                final q = _query.trim().toLowerCase();
                final filtered = q.isEmpty
                    ? items
                    : items
                        .where((c) => c.name.toLowerCase().contains(q))
                        .toList();
                return RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(categoriesProvider);
                    ref.invalidate(myBookingsProvider('active'));
                    // picks up admin changes (promo banner, flags) live
                    ref.invalidate(appConfigProvider);
                  },
                  child: CustomScrollView(
                    slivers: [
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
                        sliver: SliverToBoxAdapter(child: _header(context)),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                        sliver: SliverToBoxAdapter(child: _greeting(context)),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                        sliver: SliverToBoxAdapter(
                            child: _announcement(context)),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        sliver: SliverToBoxAdapter(child: _searchBar(context)),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        sliver:
                            SliverToBoxAdapter(child: _promoBanner(context)),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
                        sliver: SliverToBoxAdapter(
                          child: Text(
                            l10n.exploreServices,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                        sliver: SliverGrid.count(
                          crossAxisCount: 3,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.95,
                          children: [
                            for (var i = 0; i < filtered.length; i++)
                              _CategoryTile(
                                  category: filtered[i], tintIndex: i),
                          ],
                        ),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 88)),
                    ],
                  ),
                );
              },
            ),
            const Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: _ActiveBookingBar(),
            ),
          ],
        ),
      ),
    );
  }

  /// Greeting personalizes with the profile name when available.
  Widget _greeting(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final name = ref.watch(meProvider).maybeWhen(
        data: (me) => (me['full_name'] as String?)?.trim(),
        orElse: () => null);
    final first =
        (name?.isNotEmpty ?? false) ? name!.split(' ').first : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (first != null)
          Text(
            '${l10n.hiLabel} $first',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600),
          ),
        Text(
          l10n.greetingTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ],
    );
  }

  /// Admin announcement strip (e.g. holiday notice); hidden by default.
  Widget _announcement(BuildContext context) {
    final config = ref
        .watch(appConfigProvider)
        .maybeWhen(data: (c) => c, orElse: () => null);
    final text = config?.announcementText;
    if (config == null ||
        !config.announcementEnabled ||
        text == null ||
        text.isEmpty) {
      return const SizedBox.shrink();
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fg = dark ? Colors.amber.shade200 : Colors.amber.shade900;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: dark
            ? Colors.amber.shade900.withValues(alpha: 0.3)
            : Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.campaign, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: fg, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final cityLabel = ref.watch(appConfigProvider).maybeWhen(
        data: (c) => c.cityLabel, orElse: () => null);
    final gpsCity = ref
        .watch(gpsCityProvider)
        .maybeWhen(data: (c) => c, orElse: () => null);
    return Row(
      children: [
        Icon(Icons.place, size: 18, color: scheme.primary),
        const SizedBox(width: 4),
        Text(
          gpsCity ?? cityLabel ?? l10n.cityLabel,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: scheme.primary, fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.settings_outlined),
          tooltip: l10n.settingsTitle,
          onPressed: () => context.push('/settings'),
        ),
      ],
    );
  }

  Widget _searchBar(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return TextField(
      onChanged: (v) => setState(() => _query = v),
      // Enter = full search across every service (server-side).
      onSubmitted: (v) =>
          context.push('/search?q=${Uri.encodeComponent(v.trim())}'),
      decoration: InputDecoration(
        hintText: l10n.searchServices,
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: scheme.surfaceContainerHighest,
        contentPadding: const EdgeInsets.symmetric(vertical: 0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// Admin-controlled banner: text comes from app-config, with the
  /// built-in copy as fallback; hidden when the admin disables it.
  Widget _promoBanner(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final config = ref
        .watch(appConfigProvider)
        .maybeWhen(data: (c) => c, orElse: () => null);
    if (config != null && !config.promoEnabled) {
      return const SizedBox.shrink();
    }
    final title = config?.promoTitle ?? l10n.promoTitle;
    final subtitle = config?.promoSubtitle ?? l10n.promoSubtitle;
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [
            primary,
            Color.lerp(primary, Colors.black, 0.3) ?? primary,
          ],
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
          const Icon(Icons.verified_user, color: Colors.white70, size: 36),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.category, required this.tintIndex});

  final Category category;
  final int tintIndex;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = categoryTint(context, tintIndex);
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
          '/category/${category.id}?name=${Uri.encodeComponent(category.name)}',
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // White icon chip lifts the glyph off the tinted tile.
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface.withValues(
                      alpha: Theme.of(context).brightness == Brightness.dark
                          ? 0.18
                          : 0.7),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(categoryIcon(category.icon), size: 24, color: fg),
              ),
              const SizedBox(height: 8),
              Text(
                category.name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: fg, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Zomato-style pinned bar: the customer's current booking, always visible.
class _ActiveBookingBar extends ConsumerWidget {
  const _ActiveBookingBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final active = ref.watch(myBookingsProvider('active'));
    return active.maybeWhen(
      data: (items) {
        if (items.isEmpty) return const SizedBox.shrink();
        final b = items.first;
        return Material(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(16),
          elevation: 3,
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => ref.read(currentTabProvider.notifier).state = 1,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: statusColor(context, b.status),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          b.serviceName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: scheme.onInverseSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          statusLabel(l10n, b.status),
                          style: TextStyle(
                            fontSize: 12,
                            color:
                                scheme.onInverseSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    l10n.viewBooking,
                    style: const TextStyle(
                      color: Color(0xFFFBBF24),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.onRetry, required this.onSetServerUrl});

  final VoidCallback onRetry;
  final VoidCallback onSetServerUrl;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.cloud_off,
              size: 56, color: Theme.of(context).colorScheme.error),
          const SizedBox(height: 16),
          Text(l10n.backendUnreachable),
          const SizedBox(height: 16),
          FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onSetServerUrl,
            child: Text(l10n.setServerUrl),
          ),
        ],
      ),
    );
  }
}
