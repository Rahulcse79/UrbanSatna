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

  Future<void> _patch(
    BuildContext context,
    WidgetRef ref,
    Map<String, dynamic> data,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref
          .read(dioProvider)
          .patch<Map<String, dynamic>>('/api/v1/app-config', data: data);
      ref.invalidate(appConfigProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

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
          ListTile(
            leading: const Icon(Icons.category),
            title: Text(l10n.manageCatalog),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/admin/catalog'),
          ),
          const Divider(),
          config.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => ListTile(title: Text(apiErrorMessage(e))),
            data: (c) => Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.dns),
                  title: Text(l10n.allowServerUrlToggle),
                  subtitle: Text(l10n.allowServerUrlToggleHint),
                  value: c.allowServerUrlChange,
                  onChanged: (v) =>
                      _patch(context, ref, {'allow_server_url_change': v}),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.engineering),
                  title: Text(l10n.maintenanceToggle),
                  subtitle: Text(l10n.maintenanceToggleHint),
                  value: c.maintenanceMode,
                  onChanged: (v) =>
                      _patch(context, ref, {'maintenance_mode': v}),
                ),
                ListTile(
                  leading: const Icon(Icons.campaign),
                  title: Text(l10n.promoBannerTitle),
                  subtitle: Text(
                    c.promoEnabled
                        ? (c.promoTitle ?? l10n.promoTitle)
                        : l10n.promoEnabledLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editPromo(context, ref, c),
                ),
                ListTile(
                  leading: const Icon(Icons.system_update),
                  title: Text(l10n.minBuildLabel),
                  subtitle: Text('${c.minBuild}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editBuildNumber(
                      context, ref, l10n.minBuildLabel, 'min_build', c.minBuild),
                ),
                ListTile(
                  leading: const Icon(Icons.new_releases),
                  title: Text(l10n.latestBuildLabel),
                  subtitle: Text('${c.latestBuild}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editBuildNumber(context, ref,
                      l10n.latestBuildLabel, 'latest_build', c.latestBuild),
                ),
                SwitchListTile(
                  secondary: const Icon(Icons.lock_clock),
                  title: Text(l10n.requireLatestToggle),
                  subtitle: Text(l10n.requireLatestHint),
                  value: c.requireLatest,
                  onChanged: (v) =>
                      _patch(context, ref, {'require_latest': v}),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editPromo(
    BuildContext context,
    WidgetRef ref,
    AppConfig config,
  ) async {
    final l10n = AppLocalizations.of(context);
    final title = TextEditingController(text: config.promoTitle ?? '');
    final subtitle = TextEditingController(text: config.promoSubtitle ?? '');
    var enabled = config.promoEnabled;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.promoBannerTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                decoration: InputDecoration(
                  labelText: l10n.promoTitleLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subtitle,
                decoration: InputDecoration(
                  labelText: l10n.promoSubtitleLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.promoEnabledLabel),
                value: enabled,
                onChanged: (v) => setState(() => enabled = v),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !context.mounted) return;
    await _patch(context, ref, {
      'promo_enabled': enabled,
      if (title.text.trim().isNotEmpty) 'promo_title': title.text.trim(),
      if (subtitle.text.trim().isNotEmpty)
        'promo_subtitle': subtitle.text.trim(),
    });
  }

  Future<void> _editBuildNumber(
    BuildContext context,
    WidgetRef ref,
    String title,
    String key,
    int current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final controller = TextEditingController(text: '$current');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (saved != true || !context.mounted) return;
    final value = int.tryParse(controller.text.trim());
    if (value == null || value < 0) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.invalidNumber)));
      return;
    }
    await _patch(context, ref, {key: value});
  }
}
