import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'env.dart';

/// Overridden with the real instance in main() (and in tests).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

/// Backend base URL the whole app uses.
///
/// Resolution order (PRODUCT — admin controls the fleet's server):
/// 1. Admin-configured URL from app-config, when set. It always wins
///    while "allow users to change server URL" is off; when the flag is
///    on, a user-saved URL overrides it.
/// 2. The user-saved value from Settings.
/// 3. The build-time default from --dart-define.
final serverUrlProvider =
    NotifierProvider<ServerUrlNotifier, String>(ServerUrlNotifier.new);

class ServerUrlNotifier extends Notifier<String> {
  static const _prefsKey = 'server_url';
  static const _adminUrlKey = 'admin_server_url';
  static const _adminAllowKey = 'admin_allow_url_change';

  @override
  String build() => _resolve(ref.watch(sharedPreferencesProvider));

  String _resolve(SharedPreferences prefs) {
    final adminUrl = prefs.getString(_adminUrlKey);
    final allowChange = prefs.getBool(_adminAllowKey) ?? true;
    final userUrl = prefs.getString(_prefsKey);
    if (adminUrl != null && adminUrl.isNotEmpty) {
      if (!allowChange) return adminUrl;
      return (userUrl == null || userUrl.isEmpty) ? adminUrl : userUrl;
    }
    return (userUrl == null || userUrl.isEmpty) ? Env.apiBaseUrl : userUrl;
  }

  static String _normalize(String url) =>
      url.trim().replaceAll(RegExp(r'/+$'), '');

  /// Persists [url] as the user's own choice and switches immediately.
  Future<void> set(String url) async {
    await ref
        .read(sharedPreferencesProvider)
        .setString(_prefsKey, _normalize(url));
    state = _resolve(ref.read(sharedPreferencesProvider));
  }

  /// Clears the user's saved value (falls back to admin URL or default).
  Future<void> reset() async {
    await ref.read(sharedPreferencesProvider).remove(_prefsKey);
    state = _resolve(ref.read(sharedPreferencesProvider));
  }

  /// Mirrors the admin-controlled server settings from app-config so the
  /// whole fleet follows them, surviving restarts. No-op when nothing
  /// changed — that keeps the config-fetch → URL-switch → re-fetch cycle
  /// from looping.
  Future<void> applyAdminConfig({
    required String? serverUrl,
    required bool allowChange,
  }) async {
    final prefs = ref.read(sharedPreferencesProvider);
    final normalized = _normalize(serverUrl ?? '');
    final storedUrl = prefs.getString(_adminUrlKey) ?? '';
    final storedAllow = prefs.getBool(_adminAllowKey) ?? true;
    if (storedUrl == normalized && storedAllow == allowChange) return;
    if (normalized.isEmpty) {
      await prefs.remove(_adminUrlKey);
    } else {
      await prefs.setString(_adminUrlKey, normalized);
    }
    await prefs.setBool(_adminAllowKey, allowChange);
    state = _resolve(prefs);
  }
}
