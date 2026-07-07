import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/data/bookings_repository.dart';
import '../../bookings/domain/booking.dart';
import '../../bookings/presentation/bookings_screen.dart'
    show callNumber, statusChip;

/// Worker view: earnings, available jobs to accept, and assigned jobs
/// to advance (mockup "Available Jobs" screen).
class JobsScreen extends ConsumerWidget {
  const JobsScreen({super.key});

  void _refresh(WidgetRef ref) {
    ref.invalidate(availableJobsProvider);
    ref.invalidate(myJobsProvider);
    ref.invalidate(earningsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final available = ref.watch(availableJobsProvider);
    final mine = ref.watch(myJobsProvider);
    final earnings = ref.watch(earningsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navJobs)),
      body: RefreshIndicator(
        onRefresh: () async => _refresh(ref),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            earnings.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              // Wallet-style gradient card — the worker's money at a glance.
              data: (e) {
                final primary = Theme.of(context).colorScheme.primary;
                return InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => context.push('/earnings'),
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          primary,
                          Color.lerp(primary, Colors.black, 0.35) ?? primary,
                        ],
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _Stat(label: l10n.todayLabel, value: e.todayLabel),
                        _Stat(
                            label: l10n.earningsTitle, value: e.totalLabel),
                        _Stat(
                            label: l10n.completedJobs,
                            value: '${e.completedJobs}'),
                        const Icon(Icons.chevron_right,
                            color: Colors.white70),
                      ],
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(l10n.myJobs,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            mine.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(apiErrorMessage(e)),
              data: (jobs) => jobs.isEmpty
                  ? Text(l10n.noJobs)
                  : Column(
                      children: [
                        for (final job in jobs)
                          _JobCard(
                            job: job,
                            onAction: () => _refresh(ref),
                            assigned: true,
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: 16),
            Text(l10n.availableJobs,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            available.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text(apiErrorMessage(e)),
              data: (jobs) => jobs.isEmpty
                  ? Text(l10n.noJobs)
                  : Column(
                      children: [
                        for (final job in jobs)
                          _JobCard(
                            job: job,
                            onAction: () => _refresh(ref),
                            assigned: false,
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

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800, color: Colors.white)),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.white70)),
      ],
    );
  }
}

class _JobCard extends ConsumerWidget {
  const _JobCard({
    required this.job,
    required this.onAction,
    required this.assigned,
  });

  final Booking job;
  final VoidCallback onAction;
  final bool assigned;

  String _actionLabel(AppLocalizations l10n, String action) =>
      switch (action) {
        'en_route' => l10n.actionEnRoute,
        'arrived' => l10n.actionArrived,
        'start' => l10n.actionStart,
        'complete' => l10n.actionComplete,
        _ => action,
      };

  /// `start` needs the customer's 4-digit arrival OTP (trust handshake).
  Future<String?> _askOtp(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.enterOtpTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 24, letterSpacing: 8),
          decoration: InputDecoration(
            helperText: l10n.enterOtpHint,
            filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
            counterText: '',
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(l10n.actionStart),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(bookingsRepositoryProvider);
    final action = job.nextWorkerAction;

    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${job.serviceName} (${job.categoryName})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (assigned) statusChip(context, l10n, job.status),
              ],
            ),
            Text(job.address, style: Theme.of(context).textTheme.bodySmall),
            if (assigned)
              Row(
                children: [
                  if (job.customerPhone != null)
                    TextButton.icon(
                      icon: const Icon(Icons.call, size: 18),
                      label: Text(l10n.callLabel),
                      onPressed: () => callNumber(job.customerPhone!),
                    ),
                  TextButton.icon(
                    icon: const Icon(Icons.directions, size: 18),
                    label: Text(l10n.navigateLabel),
                    // GPS pin (when shared) beats the typed address.
                    onPressed: () => launchUrl(
                      Uri.parse(job.lat != null && job.lng != null
                          ? 'https://www.google.com/maps/dir/?api=1&destination=${job.lat},${job.lng}'
                          : 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(job.address)}'),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.chat_bubble_outline, size: 18),
                    label: Text(l10n.chatTitle),
                    onPressed: () => context.push(
                        '/chat/${job.id}?title=${Uri.encodeComponent(job.customerName ?? job.serviceName)}'),
                  ),
                ],
              ),
            if (job.note != null && job.note!.isNotEmpty)
              Text('“${job.note}”',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontStyle: FontStyle.italic)),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(job.priceLabel,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                if (!assigned)
                  FilledButton(
                    onPressed: () async {
                      try {
                        await repo.accept(job.id);
                        onAction();
                      } catch (e) {
                        messenger.showSnackBar(
                            SnackBar(content: Text(apiErrorMessage(e))));
                        onAction();
                      }
                    },
                    child: Text(l10n.accept),
                  )
                else if (action != null)
                  FilledButton(
                    onPressed: () async {
                      String? otp;
                      if (action == 'start') {
                        otp = await _askOtp(context);
                        if (otp == null || otp.length != 4) return;
                      }
                      try {
                        await repo.advance(job.id, action, otp: otp);
                        onAction();
                      } catch (e) {
                        messenger.showSnackBar(
                            SnackBar(content: Text(apiErrorMessage(e))));
                      }
                    },
                    child: Text(_actionLabel(l10n, action)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
