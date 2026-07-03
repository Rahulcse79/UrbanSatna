import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/gen/app_localizations.dart';
import '../data/health_repository.dart';
import '../domain/health_status.dart';

/// Phase 0 home: proves the app can reach the backend end-to-end.
/// Replaced by the category grid in Phase 2.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final health = ref.watch(healthCheckProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: Center(
        child: health.when(
          loading: () => const CircularProgressIndicator(),
          error: (_, __) => _Unreachable(
            onRetry: () => ref.invalidate(healthCheckProvider),
          ),
          data: (status) => _HealthReport(status: status),
        ),
      ),
    );
  }
}

class _HealthReport extends StatelessWidget {
  const _HealthReport({required this.status});

  final HealthStatus status;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          status.healthy ? Icons.check_circle : Icons.error,
          size: 56,
          color: status.healthy
              ? Colors.green
              : Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          l10n.statusOverall(status.status),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(l10n.statusDatabase(status.database)),
        Text(l10n.statusRedis(status.redis)),
        const SizedBox(height: 8),
        Text(
          'v${status.version}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.cloud_off,
          size: 56,
          color: Theme.of(context).colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(l10n.backendUnreachable),
        const SizedBox(height: 16),
        FilledButton(onPressed: onRetry, child: Text(l10n.retry)),
      ],
    );
  }
}
