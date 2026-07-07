import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/data/bookings_repository.dart';
import '../../bookings/presentation/bookings_screen.dart' show formatTime;

/// Worker money dashboard: period totals + payment history.
class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final earnings = ref.watch(earningsProvider);
    final history = ref.watch(workerHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.earningsDashboard)),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(earningsProvider);
          ref.invalidate(workerHistoryProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            earnings.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(apiErrorMessage(e)),
              data: (e) => Column(
                children: [
                  Row(
                    children: [
                      _StatCard(label: l10n.todayLabel, value: e.todayLabel),
                      const SizedBox(width: 10),
                      _StatCard(label: l10n.weekLabel, value: e.weekLabel),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatCard(label: l10n.monthLabel, value: e.monthLabel),
                      const SizedBox(width: 10),
                      _StatCard(
                        label: l10n.totalEarningsLabel,
                        value: e.totalLabel,
                        highlight: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _StatCard(
                          label: l10n.completedJobs,
                          value: '${e.completedJobs}'),
                      const SizedBox(width: 10),
                      _StatCard(
                        label: l10n.avgRating,
                        value: e.avgRating?.toStringAsFixed(1) ?? '—',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(l10n.paymentHistory,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            history.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(apiErrorMessage(e)),
              data: (jobs) => jobs.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(child: Text(l10n.noPayments)),
                    )
                  : Column(
                      children: [
                        for (final job in jobs)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: Colors.green.shade50,
                              child: Icon(Icons.currency_rupee,
                                  color: Colors.green.shade700, size: 20),
                            ),
                            title: Text(job.serviceName),
                            subtitle: Text(job.completedAt != null
                                ? formatTime(job.completedAt!)
                                : ''),
                            trailing: Text(
                              '+${job.priceLabel}',
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: highlight ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}
