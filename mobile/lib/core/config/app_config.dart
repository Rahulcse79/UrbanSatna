import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';

class AppConfig {
  const AppConfig({
    required this.allowServerUrlChange,
    this.promoEnabled = true,
    this.promoTitle,
    this.promoSubtitle,
    this.maintenanceMode = false,
    this.minBuild = 0,
    this.latestBuild = 0,
    this.requireLatest = false,
  });

  final bool allowServerUrlChange;
  final bool promoEnabled;
  final String? promoTitle;
  final String? promoSubtitle;
  final bool maintenanceMode;

  /// Hard floor: builds below this are always blocked.
  final int minBuild;

  /// Newest released build; with [requireLatest] on, older builds are
  /// blocked until updated.
  final int latestBuild;
  final bool requireLatest;

  /// The build a device must have to pass the version gate.
  int get effectiveMinBuild =>
      requireLatest && latestBuild > minBuild ? latestBuild : minBuild;
}

/// Remote, admin-controlled app configuration.
///
/// Fail-open: when the server is unreachable (or old) every gate stays
/// off and the user MUST still be able to change the server URL —
/// otherwise a wrong URL would lock them out permanently.
final appConfigProvider = FutureProvider.autoDispose<AppConfig>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final res = await dio.get<Map<String, dynamic>>('/api/v1/app-config');
    final data = unwrapEnvelope(res) as Map<String, dynamic>;
    return AppConfig(
      allowServerUrlChange: data['allow_server_url_change'] as bool? ?? true,
      promoEnabled: data['promo_enabled'] as bool? ?? true,
      promoTitle: data['promo_title'] as String?,
      promoSubtitle: data['promo_subtitle'] as String?,
      maintenanceMode: data['maintenance_mode'] as bool? ?? false,
      minBuild: data['min_build'] as int? ?? 0,
      latestBuild: data['latest_build'] as int? ?? 0,
      requireLatest: data['require_latest'] as bool? ?? false,
    );
  } catch (_) {
    return const AppConfig(allowServerUrlChange: true);
  }
});
