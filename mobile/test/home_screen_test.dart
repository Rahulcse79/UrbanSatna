import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:urbansatna/features/home/data/health_repository.dart';
import 'package:urbansatna/features/home/domain/health_status.dart';
import 'package:urbansatna/features/home/presentation/home_screen.dart';
import 'package:urbansatna/l10n/gen/app_localizations.dart';

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
  testWidgets('shows backend status when health check succeeds',
      (tester) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          healthCheckProvider.overrideWith(
            (ref) async => const HealthStatus(
              status: 'ok',
              database: 'up',
              redis: 'up',
              version: '0.1.0',
            ),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backend: ok'), findsOneWidget);
    expect(find.text('Database: up'), findsOneWidget);
    expect(find.text('Redis: up'), findsOneWidget);
  });

  testWidgets('shows retry when the backend is unreachable', (tester) async {
    await tester.pumpWidget(
      _app(
        overrides: [
          healthCheckProvider.overrideWith(
            (ref) async => throw Exception('connection refused'),
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
  });
}
