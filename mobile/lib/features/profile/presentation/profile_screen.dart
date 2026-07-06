import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../worker/data/worker_repository.dart';

final meProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get<Map<String, dynamic>>('/api/v1/me');
  return unwrapEnvelope(res) as Map<String, dynamic>;
});

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final me = ref.watch(meProvider);
    final tokens = ref.watch(authControllerProvider);
    final isWorker = tokens?.isWorker ?? false;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navProfile)),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (data) {
          final roles =
              (data['roles'] as List<dynamic>? ?? []).cast<String>();
          final isAdmin =
              roles.contains('admin') || roles.contains('super_admin');
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const CircleAvatar(
                radius: 40,
                child: Icon(Icons.person, size: 48),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  (data['full_name'] as String?) ?? (data['phone'] as String),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              Center(
                child: Text(data['phone'] as String,
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              const SizedBox(height: 8),
              Center(
                child: Wrap(
                  spacing: 8,
                  children: [
                    for (final role in roles)
                      Chip(
                        label: Text(role),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.edit),
                title: Text(l10n.editName),
                onTap: () => _editName(context, ref,
                    current: data['full_name'] as String? ?? ''),
              ),
              if (!isWorker) const _WorkerApplicationTile(),
              if (isAdmin)
                ListTile(
                  leading: const Icon(Icons.how_to_reg),
                  title: Text(l10n.workerApprovals),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/admin/approvals'),
                ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: Text(l10n.settingsTitle),
                onTap: () => context.push('/settings'),
              ),
              ListTile(
                leading: Icon(Icons.logout,
                    color: Theme.of(context).colorScheme.error),
                title: Text(l10n.logout,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
                onTap: () =>
                    ref.read(authControllerProvider.notifier).logout(),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _editName(BuildContext context, WidgetRef ref,
      {required String current}) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: current);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.editName),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: l10n.nameLabel,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (saved != true) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.patch<Map<String, dynamic>>('/api/v1/me',
          data: {'full_name': controller.text.trim()});
      ref.invalidate(meProvider);
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}

/// Worker onboarding tile with the verification lifecycle:
/// never applied → apply · pending → under review · rejected → re-apply ·
/// approved → activate (token refresh picks up the role).
class _WorkerApplicationTile extends ConsumerWidget {
  const _WorkerApplicationTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final application = ref.watch(myWorkerApplicationProvider);
    return application.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => ListTile(
        leading: const Icon(Icons.engineering),
        title: Text(l10n.becomeWorker),
        subtitle: Text(l10n.becomeWorkerHint),
        onTap: () => _apply(context, ref),
      ),
      data: (app) {
        if (app == null) {
          return ListTile(
            leading: const Icon(Icons.engineering),
            title: Text(l10n.becomeWorker),
            subtitle: Text(l10n.becomeWorkerHint),
            onTap: () => _apply(context, ref),
          );
        }
        if (app.pending) {
          return ListTile(
            leading: const Icon(Icons.hourglass_top),
            title: Text(l10n.applicationPending),
            subtitle: Text(l10n.applicationPendingHint),
            onTap: () => ref.invalidate(myWorkerApplicationProvider),
          );
        }
        if (app.rejected) {
          return ListTile(
            leading: Icon(Icons.block,
                color: Theme.of(context).colorScheme.error),
            title: Text(l10n.applicationRejected),
            subtitle: app.note?.isNotEmpty ?? false ? Text(app.note!) : null,
            onTap: () => _apply(context, ref),
          );
        }
        // Approved but the token doesn't carry the worker role yet.
        return ListTile(
          leading: const Icon(Icons.verified, color: Colors.green),
          title: Text(l10n.activateWorker),
          subtitle: Text(l10n.activateWorkerHint),
          onTap: () async {
            await ref.read(authControllerProvider.notifier).tryRefresh();
            ref.invalidate(meProvider);
          },
        );
      },
    );
  }

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final skills = TextEditingController();
    final experience = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.applyWorkerTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: skills,
              decoration: InputDecoration(
                labelText: l10n.skillsLabel,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: experience,
              decoration: InputDecoration(
                labelText: l10n.experienceLabel,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.submit),
          ),
        ],
      ),
    );
    if (submitted != true) return;
    try {
      await ref.read(workerRepositoryProvider).apply(
            skills: skills.text.trim(),
            experience: experience.text.trim(),
          );
      ref.invalidate(myWorkerApplicationProvider);
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.applicationSubmitted)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}
