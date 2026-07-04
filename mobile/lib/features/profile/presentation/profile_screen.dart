import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/auth/auth_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';

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
        data: (data) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            CircleAvatar(
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
                  for (final role
                      in (data['roles'] as List<dynamic>? ?? []).cast<String>())
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
            if (!isWorker)
              ListTile(
                leading: const Icon(Icons.engineering),
                title: Text(l10n.becomeWorker),
                subtitle: Text(l10n.becomeWorkerHint),
                onTap: () => _becomeWorker(context, ref),
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
        ),
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

  Future<void> _becomeWorker(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dio = ref.read(dioProvider);
      await dio.post<Map<String, dynamic>>('/api/v1/me/become-worker');
      // Roles live in the token — refresh to activate the worker role.
      await ref.read(authControllerProvider.notifier).tryRefresh();
      ref.invalidate(meProvider);
      messenger.showSnackBar(SnackBar(content: Text(l10n.becomeWorkerDone)));
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}
