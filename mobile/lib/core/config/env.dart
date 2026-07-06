/// Build-time environment. Pass values with --dart-define, e.g.
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8080
abstract final class Env {
  static const _defined = String.fromEnvironment('API_BASE_URL');

  /// Defaults to the production Render deployment so a plain build works
  /// anywhere; local dev overrides via --dart-define. Users can still
  /// change it at runtime in Settings (until the admin locks the flag).
  static const apiBaseUrl =
      _defined != '' ? _defined : 'https://urbansatna.onrender.com';
}
