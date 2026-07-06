import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../worker/data/worker_repository.dart';

/// Admin verification queue: approve or reject worker applications.
class WorkerApprovalsScreen extends ConsumerWidget {
  const WorkerApprovalsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final queue = ref.watch(pendingApplicationsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.workerApprovals)),
      body: queue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(pendingApplicationsProvider),
          child: items.isEmpty
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Icon(Icons.how_to_reg,
                        size: 56,
                        color: Theme.of(context).colorScheme.outline),
                    const SizedBox(height: 12),
                    Center(child: Text(l10n.noApplications)),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _ApplicationCard(application: items[i]),
                ),
        ),
      ),
    );
  }
}

class _ApplicationCard extends ConsumerWidget {
  const _ApplicationCard({required this.application});

  final WorkerApplication application;

  Future<void> _decide(
    BuildContext context,
    WidgetRef ref, {
    required bool approve,
  }) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    String? note;
    if (!approve) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(l10n.reject),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.decisionNoteLabel,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.reject),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      note = controller.text.trim();
    }
    try {
      await ref
          .read(workerRepositoryProvider)
          .decide(application.id, approve: approve, note: note);
      ref.invalidate(pendingApplicationsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  void _showKyc(BuildContext context, WidgetRef ref, String kind) {
    final repo = ref.read(workerRepositoryProvider);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        child: FutureBuilder<Uint8List?>(
          future: repo.kycImage(application.id, kind),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 200,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final bytes = snapshot.data;
            if (bytes == null) {
              return const SizedBox(
                height: 120,
                child: Center(child: Icon(Icons.broken_image, size: 48)),
              );
            }
            return ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.memory(bytes, fit: BoxFit.contain),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              application.fullName ?? application.phone,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(application.phone, style: theme.textTheme.bodySmall),
            if (application.skills?.isNotEmpty ?? false)
              Text('${l10n.skillsLabel}: ${application.skills}',
                  style: theme.textTheme.bodySmall),
            if (application.experience?.isNotEmpty ?? false)
              Text('${l10n.experienceLabel}: ${application.experience}',
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Row(
              children: [
                if (application.hasKycDoc)
                  TextButton.icon(
                    icon: const Icon(Icons.badge, size: 18),
                    label: Text(l10n.viewId),
                    onPressed: () => _showKyc(context, ref, 'doc'),
                  ),
                if (application.hasKycSelfie)
                  TextButton.icon(
                    icon: const Icon(Icons.face, size: 18),
                    label: Text(l10n.viewSelfie),
                    onPressed: () => _showKyc(context, ref, 'selfie'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => _decide(context, ref, approve: false),
                  child: Text(
                    l10n.reject,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _decide(context, ref, approve: true),
                  child: Text(l10n.approve),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
