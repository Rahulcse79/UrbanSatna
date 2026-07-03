import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:servexa/core/config/server_url.dart';
import 'package:servexa/features/settings/presentation/settings_screen.dart';
import 'package:servexa/l10n/gen/app_localizations.dart';

Future<SharedPreferences> _emptyPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget _app(SharedPreferences prefs) {
  return ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
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

  testWidgets('reset returns to the build-time default', (tester) async {
    SharedPreferences.setMockInitialValues(
        {'server_url': 'http://192.168.1.50:8080'});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_app(prefs));
    await tester.pumpAndSettle();

    expect(find.text('http://192.168.1.50:8080'), findsOneWidget);

    await tester.tap(find.text('Reset to default'));
    await tester.pumpAndSettle();

    expect(prefs.getString('server_url'), isNull);
    // Default from Env (no --dart-define in tests): emulator loopback.
    expect(find.text('http://10.0.2.2:8080'), findsOneWidget);
  });
}
