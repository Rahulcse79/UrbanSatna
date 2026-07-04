import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../network/api_client.dart';

class AppConfig {
  const AppConfig({required this.allowServerUrlChange});

  final bool allowServerUrlChange;
}

/// Remote, admin-controlled app configuration.
///
/// Fail-open: when the server is unreachable (or old) the user MUST still
/// be able to change the server URL — otherwise a wrong URL would lock
/// them out permanently. The backend default is also `true`.
final appConfigProvider = FutureProvider.autoDispose<AppConfig>((ref) async {
  final dio = ref.watch(dioProvider);
  try {
    final res = await dio.get<Map<String, dynamic>>('/api/v1/app-config');
    final data = unwrapEnvelope(res) as Map<String, dynamic>;
    return AppConfig(
      allowServerUrlChange:
          data['allow_server_url_change'] as bool? ?? true,
    );
  } catch (_) {
    return const AppConfig(allowServerUrlChange: true);
  }
});
