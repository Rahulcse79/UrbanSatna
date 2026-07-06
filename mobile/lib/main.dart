import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/auth/auth_controller.dart';
import 'core/config/app_config.dart';
import 'core/config/env.dart';
import 'core/config/server_url.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode.dart';
import 'core/widgets/gate_screens.dart';
import 'l10n/gen/app_localizations.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final tokens = await loadStoredTokens();
  runApp(
    ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        initialTokensProvider.overrideWithValue(tokens),
      ],
      child: const ServexaApp(),
    ),
  );
}

class ServexaApp extends ConsumerWidget {
  const ServexaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    // The look is admin-controlled: the server names one of the built-in
    // presets and every user's app re-skins on next config fetch.
    final preset = ref.watch(appConfigProvider).maybeWhen(
        data: (c) => c.themePreset, orElse: () => 'indigo');
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: AppTheme.light(preset),
      darkTheme: AppTheme.dark(preset),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) =>
          _AppGate(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// Runtime gates from the admin control plane: maintenance mode and
/// force-update. Admins bypass both (they need the app to turn them off).
class _AppGate extends ConsumerWidget {
  const _AppGate({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref
        .watch(appConfigProvider)
        .maybeWhen(data: (c) => c, orElse: () => null);
    final tokens = ref.watch(authControllerProvider);
    final isAdmin = tokens?.roles
            .any((r) => r == 'admin' || r == 'super_admin') ??
        false;
    if (config != null && !isAdmin) {
      // Version gate: min_build floor, or latest_build when the admin
      // has switched on "only latest version can run".
      if (config.effectiveMinBuild > Env.appBuild) {
        return const ForceUpdateScreen();
      }
      // Maintenance never blocks the login screen (tokens == null):
      // otherwise a logged-out admin could not sign in to turn it off.
      if (config.maintenanceMode && tokens != null) {
        return const MaintenanceScreen();
      }
    }
    return child;
  }
}
