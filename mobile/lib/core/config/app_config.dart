import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';
import 'server_url.dart';

class AppConfig {
  const AppConfig({
    required this.allowServerUrlChange,
    this.serverUrl,
    this.promoEnabled = true,
    this.promoTitle,
    this.promoSubtitle,
    this.maintenanceMode = false,
    this.minBuild = 0,
    this.latestBuild = 0,
    this.requireLatest = false,
    this.cityLabel,
    this.appDisplayName,
    this.tagline,
    this.themePreset = 'indigo',
    this.supportPhone,
    this.announcementEnabled = false,
    this.announcementText,
    this.bookingsPaused = false,
    this.bookingsPausedMessage,
    this.maxActiveBookings = 5,
    this.supportEmail,
    this.appVersionLabel,
    this.countryCodes = const ['+91'],
    this.termsUrl,
    this.privacyUrl,
    this.supportOnline = false,
  });

  final bool allowServerUrlChange;

  /// Admin-configured backend URL the whole fleet follows; null = unset.
  final String? serverUrl;
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

  // Branding & text (admin-editable, null = built-in default)
  final String? cityLabel;
  final String? appDisplayName;
  final String? tagline;
  final String themePreset;
  final String? supportPhone;
  final bool announcementEnabled;
  final String? announcementText;

  // Booking controls (enforced server-side; mirrored for UI)
  final bool bookingsPaused;
  final String? bookingsPausedMessage;
  final int maxActiveBookings;

  // Help, legal & registration
  final String? supportEmail;
  final String? appVersionLabel;
  final List<String> countryCodes;
  final String? termsUrl;
  final String? privacyUrl;

  /// Live-support indicator: green (true) / red (false).
  final bool supportOnline;

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
    // Admin server settings apply fleet-wide: persist them so the app
    // follows the admin URL from the next request on (and after restart).
    await ref.read(serverUrlProvider.notifier).applyAdminConfig(
          serverUrl: data['server_url'] as String?,
          allowChange: data['allow_server_url_change'] as bool? ?? true,
        );
    return AppConfig(
      allowServerUrlChange: data['allow_server_url_change'] as bool? ?? true,
      serverUrl: data['server_url'] as String?,
      promoEnabled: data['promo_enabled'] as bool? ?? true,
      promoTitle: data['promo_title'] as String?,
      promoSubtitle: data['promo_subtitle'] as String?,
      maintenanceMode: data['maintenance_mode'] as bool? ?? false,
      minBuild: data['min_build'] as int? ?? 0,
      latestBuild: data['latest_build'] as int? ?? 0,
      requireLatest: data['require_latest'] as bool? ?? false,
      cityLabel: data['city_label'] as String?,
      appDisplayName: data['app_display_name'] as String?,
      tagline: data['tagline'] as String?,
      themePreset: data['theme_preset'] as String? ?? 'indigo',
      supportPhone: data['support_phone'] as String?,
      announcementEnabled: data['announcement_enabled'] as bool? ?? false,
      announcementText: data['announcement_text'] as String?,
      bookingsPaused: data['bookings_paused'] as bool? ?? false,
      bookingsPausedMessage: data['bookings_paused_message'] as String?,
      maxActiveBookings: data['max_active_bookings'] as int? ?? 5,
      supportEmail: data['support_email'] as String?,
      appVersionLabel: data['app_version_label'] as String?,
      countryCodes: (data['country_codes'] as List<dynamic>?)
              ?.cast<String>()
              .toList() ??
          const ['+91'],
      termsUrl: data['terms_url'] as String?,
      privacyUrl: data['privacy_url'] as String?,
      supportOnline: data['support_online'] as bool? ?? false,
    );
  } catch (_) {
    return const AppConfig(allowServerUrlChange: true);
  }
});
