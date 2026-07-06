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
  });

  final bool allowServerUrlChange;
  final bool promoEnabled;
  final String? promoTitle;
  final String? promoSubtitle;
  final bool maintenanceMode;
  final int minBuild;
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
    );
  } catch (_) {
    return const AppConfig(allowServerUrlChange: true);
  }
});
