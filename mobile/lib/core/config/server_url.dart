import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'env.dart';

/// Overridden with the real instance in main() (and in tests).
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) =>
      throw UnimplementedError('sharedPreferencesProvider must be overridden'),
);

/// Backend base URL the whole app uses: the user-saved value if present,
/// otherwise the build-time default from --dart-define.
final serverUrlProvider =
    NotifierProvider<ServerUrlNotifier, String>(ServerUrlNotifier.new);

class ServerUrlNotifier extends Notifier<String> {
  static const _prefsKey = 'server_url';

  @override
  String build() {
    final saved = ref.watch(sharedPreferencesProvider).getString(_prefsKey);
    return (saved == null || saved.isEmpty) ? Env.apiBaseUrl : saved;
  }

  /// Persists [url] and switches the app to it immediately.
  Future<void> set(String url) async {
    final normalized = url.trim().replaceAll(RegExp(r'/+$'), '');
    await ref.read(sharedPreferencesProvider).setString(_prefsKey, normalized);
    state = normalized;
  }

  /// Clears the saved value and returns to the build-time default.
  Future<void> reset() async {
    await ref.read(sharedPreferencesProvider).remove(_prefsKey);
    state = Env.apiBaseUrl;
  }
}
