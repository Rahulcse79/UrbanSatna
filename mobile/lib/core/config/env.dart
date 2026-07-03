/// Build-time environment. Pass values with --dart-define, e.g.
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8080
abstract final class Env {
  /// 10.0.2.2 is the Android-emulator alias for the host's localhost.
  static const apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );
}
