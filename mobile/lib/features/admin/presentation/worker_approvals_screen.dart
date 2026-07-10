import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/page_bar.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/presentation/bookings_screen.dart' show formatTime;
import '../../worker/data/worker_repository.dart';

/// Admin verification queue: approve or reject worker applications,
/// 10 per page, with the applicant's photo and documents in reach.
class WorkerApprovalsScreen extends ConsumerStatefulWidget {
  const WorkerApprovalsScreen({super.key});

  @override
  ConsumerState<WorkerApprovalsScreen> createState() =>
      _WorkerApprovalsScreenState();
}

class _WorkerApprovalsScreenState
    extends ConsumerState<WorkerApprovalsScreen> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final queue = ref.watch(pendingApplicationsProvider(_page));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.workerApprovals)),
      body: Column(
        children: [
          Expanded(
            child: queue.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (page) => RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(pendingApplicationsProvider),
                child: page.items.isEmpty
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
                        padding: const EdgeInsets.all(12),
                        itemCount: page.items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, i) =>
                            _ApplicationCard(application: page.items[i]),
                      ),
              ),
            ),
          ),
          SafeArea(
            child: queue.maybeWhen(
              data: (page) => PageBar(
                page: _page,
                total: page.total,
                onPrev: () => setState(() => _page--),
                onNext: () => setState(() => _page++),
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The applicant's profile photo with an initial-letter fallback.
class _ApplicantAvatar extends ConsumerWidget {
  const _ApplicantAvatar({
    required this.application,
    this.radius = 24,
  });

  final WorkerApplication application;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final name = application.fullName?.trim().isNotEmpty == true
        ? application.fullName!.trim()
        : application.phone;
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: scheme.primary.withValues(alpha: 0.14),
      child: Text(
        name.characters.first.toUpperCase(),
        style: TextStyle(
            color: scheme.primary,
            fontWeight: FontWeight.w800,
            fontSize: radius * 0.75),
      ),
    );
    final userId = application.userId;
    if (userId == null) return fallback;
    return FutureBuilder<Uint8List?>(
      future: ref.read(workerRepositoryProvider).userAvatar(userId),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return fallback;
        return CircleAvatar(
            radius: radius, backgroundImage: MemoryImage(bytes));
      },
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
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(l10n.reject),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.decisionNoteLabel,
              filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
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

  /// Centered profile dialog: photo, contact, registration details.
  void _viewProfile(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final scheme = Theme.of(dialogContext).colorScheme;
        final text = Theme.of(dialogContext).textTheme;
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 28, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ApplicantAvatar(application: application, radius: 44),
                const SizedBox(height: 12),
                Text(
                  application.fullName?.trim().isNotEmpty == true
                      ? application.fullName!.trim()
                      : application.phone,
                  textAlign: TextAlign.center,
                  style:
                      text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                Text(application.phone,
                    style: text.bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 16),
                _detailRow(dialogContext, Icons.schedule, l10n.pendingLabel,
                    formatTime(application.createdAt)),
                if (application.skills?.isNotEmpty ?? false)
                  _detailRow(dialogContext, Icons.handyman_outlined,
                      l10n.skillsLabel, application.skills!),
                if (application.experience?.isNotEmpty ?? false)
                  _detailRow(dialogContext, Icons.workspace_premium_outlined,
                      l10n.experienceLabel, application.experience!),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: Text(l10n.cancel),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailRow(
      BuildContext context, IconData icon, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Text('$label: ',
              style: text.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurfaceVariant)),
          Expanded(child: Text(value, style: text.bodySmall)),
        ],
      ),
    );
  }

  /// Both KYC photos in one dialog, loaded side by side.
  void _viewDocuments(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(workerRepositoryProvider);
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.viewDocuments,
                  style: Theme.of(dialogContext)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (application.hasKycDoc)
                _documentImage(repo, 'doc', l10n.viewId),
              if (application.hasKycSelfie)
                _documentImage(repo, 'selfie', l10n.viewSelfie),
              if (!application.hasKycDoc && !application.hasKycSelfie)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Icon(Icons.no_photography_outlined, size: 48),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.cancel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _documentImage(WorkerRepository repo, String kind, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          FutureBuilder<Uint8List?>(
            future: repo.kycImage(application.id, kind),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(
                  height: 140,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final bytes = snapshot.data;
              if (bytes == null) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: Icon(Icons.broken_image, size: 40)),
                );
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.memory(bytes,
                    fit: BoxFit.contain,
                    height: 220,
                    width: double.infinity),
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final hasDocuments = application.hasKycDoc || application.hasKycSelfie;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border(
            left: BorderSide(color: Colors.orange.shade700, width: 4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ApplicantAvatar(application: application),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        application.fullName?.trim().isNotEmpty == true
                            ? application.fullName!.trim()
                            : application.phone,
                        style: text.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(application.phone,
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                      const SizedBox(height: 2),
                      Text(formatTime(application.createdAt),
                          style: text.labelSmall
                              ?.copyWith(color: scheme.outline)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade700,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(l10n.pendingLabel,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            if (application.skills?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text('${l10n.skillsLabel}: ${application.skills}',
                  style: text.bodySmall),
            ],
            if (application.experience?.isNotEmpty ?? false) ...[
              const SizedBox(height: 2),
              Text('${l10n.experienceLabel}: ${application.experience}',
                  style: text.bodySmall),
            ],
            const SizedBox(height: 10),
            // Wrap, not Row: the actions overflow narrow cards otherwise.
            Wrap(
              spacing: 4,
              runSpacing: 4,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.person_search_outlined, size: 18),
                  label: Text(l10n.viewProfile),
                  onPressed: () => _viewProfile(context),
                ),
                if (hasDocuments)
                  TextButton.icon(
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: Text(l10n.viewDocuments),
                    onPressed: () => _viewDocuments(context, ref),
                  ),
                TextButton(
                  onPressed: () => _decide(context, ref, approve: false),
                  child: Text(
                    l10n.reject,
                    style: TextStyle(color: scheme.error),
                  ),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check, size: 18),
                  onPressed: () => _decide(context, ref, approve: true),
                  label: Text(l10n.approve),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
