import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servexa/core/config/app_config.dart';
import 'package:servexa/core/config/server_url.dart';
import 'package:servexa/features/settings/presentation/settings_screen.dart';
import 'package:servexa/l10n/gen/app_localizations.dart';

Future<SharedPreferences> _emptyPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget _app(SharedPreferences prefs, {bool allowChange = true}) {
  return ProviderScope(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      appConfigProvider.overrideWith(
        (ref) async => AppConfig(allowServerUrlChange: allowChange),
      ),
    ],
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: SettingsScreen(),
    ),
  );
}

void main() {
  testWidgets('saves a valid server URL locally (trailing slash trimmed)',
      (tester) async {
    final prefs = await _emptyPrefs();
    await tester.pumpWidget(_app(prefs));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextFormField),
      'http://192.168.1.50:8080/',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(prefs.getString('server_url'), 'http://192.168.1.50:8080');
    expect(find.text('Server URL saved'), findsOneWidget);
  });

  testWidgets('rejects an invalid URL and saves nothing', (tester) async {
    final prefs = await _emptyPrefs();
    await tester.pumpWidget(_app(prefs));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'not-a-url');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter a valid URL starting with http:// or https://'),
      findsOneWidget,
    );
    expect(prefs.getString('server_url'), isNull);
  });

  testWidgets('admin flag off locks the field and hides save',
      (tester) async {
    final prefs = await _emptyPrefs();
    await tester.pumpWidget(_app(prefs, allowChange: false));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.enabled, isFalse);
    expect(find.text('Save'), findsNothing);
    expect(find.text('Reset to default'), findsNothing);
    expect(
      find.text('Server URL is managed by the administrator'),
      findsOneWidget,
    );
  });
}
