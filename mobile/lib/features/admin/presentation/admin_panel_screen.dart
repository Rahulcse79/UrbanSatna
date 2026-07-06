import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';

/// Admin hub: runtime controls that apply to every user instantly
/// (PRODUCT.md §6.5 — the control plane grows here).
class AdminPanelScreen extends ConsumerWidget {
  const AdminPanelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final config = ref.watch(appConfigProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminPanel)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            leading: const Icon(Icons.how_to_reg),
            title: Text(l10n.workerApprovals),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/admin/approvals'),
          ),
          const Divider(),
          config.when(
            loading: () => const ListTile(
              leading: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (e, _) => ListTile(title: Text(apiErrorMessage(e))),
            data: (c) => SwitchListTile(
              secondary: const Icon(Icons.dns),
              title: Text(l10n.allowServerUrlToggle),
              subtitle: Text(l10n.allowServerUrlToggleHint),
              value: c.allowServerUrlChange,
              onChanged: (v) async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  await ref.read(dioProvider).patch<Map<String, dynamic>>(
                    '/api/v1/app-config',
                    data: {'allow_server_url_change': v},
                  );
                  ref.invalidate(appConfigProvider);
                } catch (e) {
                  messenger.showSnackBar(
                      SnackBar(content: Text(apiErrorMessage(e))));
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}
