import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:servexa/features/catalog/data/catalog_repository.dart';
import 'package:servexa/features/catalog/domain/models.dart';
import 'package:servexa/features/home/presentation/home_screen.dart';
import 'package:servexa/l10n/gen/app_localizations.dart';

Widget _app({required List<Override> overrides}) {
  return ProviderScope(
    overrides: overrides,
    child: const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: HomeScreen(),
    ),
  );
}

void main() {
  testWidgets('shows the service category grid', (tester) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          categoriesProvider.overrideWith(
            (ref) async => const [
              Category(id: '1', name: 'Electrician', icon: 'electrician'),
              Category(id: '2', name: 'Plumber', icon: 'plumber'),
            ],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Explore Services'), findsOneWidget);
    expect(find.text('Electrician'), findsOneWidget);
    expect(find.text('Plumber'), findsOneWidget);
  });

  testWidgets('shows retry when the catalog is unreachable', (tester) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          categoriesProvider.overrideWith(
            (ref) async => throw Exception('connection refused'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Set server URL'), findsOneWidget);
  });
}
