import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
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
          ListTile(
            leading: const Icon(Icons.confirmation_number),
            title: Text(l10n.ticketsAdmin),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/admin/tickets'),
          ),
          ListTile(
            leading: const Icon(Icons.local_offer),
            title: Text(l10n.couponsAdmin),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/admin/coupons'),
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
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.palette),
                  title: Text(l10n.themeLookTitle),
                  subtitle: Text(presetByKey(c.themePreset).label),
                  trailing: CircleAvatar(
                    radius: 12,
                    backgroundColor: presetByKey(c.themePreset).seed,
                  ),
                  onTap: () => _pickTheme(context, ref, c.themePreset),
                ),
                ListTile(
                  leading: const Icon(Icons.badge),
                  title: Text(l10n.brandingTitle),
                  subtitle: Text(
                    [
                      c.appDisplayName,
                      c.cityLabel,
                      c.supportPhone,
                    ].whereType<String>().join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editBranding(context, ref, c),
                ),
                ListTile(
                  leading: const Icon(Icons.campaign_outlined),
                  title: Text(l10n.announcementTitle),
                  subtitle: Text(
                    c.announcementEnabled
                        ? (c.announcementText ?? '')
                        : l10n.promoEnabledLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editAnnouncement(context, ref, c),
                ),
                ListTile(
                  leading: const Icon(Icons.event_busy),
                  title: Text(l10n.bookingControlsTitle),
                  subtitle: Text(
                    '${c.bookingsPaused ? l10n.pauseBookingsLabel : ''} '
                            '· ${l10n.maxActiveLabel}: ${c.maxActiveBookings}'
                        .trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editBookingControls(context, ref, c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 9 built-in looks; the choice re-skins every user's app.
  Future<void> _pickTheme(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) async {
    final l10n = AppLocalizations.of(context);
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.themeLookTitle),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final preset in themePresets)
              InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () => Navigator.of(dialogContext).pop(preset.key),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: preset.seed,
                      child: preset.key == current
                          ? const Icon(Icons.check, color: Colors.white)
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text(preset.label,
                        style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !context.mounted) return;
    await _patch(context, ref, {'theme_preset': picked});
  }

  Future<void> _editBranding(
    BuildContext context,
    WidgetRef ref,
    AppConfig c,
  ) async {
    final l10n = AppLocalizations.of(context);
    final name = TextEditingController(text: c.appDisplayName ?? '');
    final city = TextEditingController(text: c.cityLabel ?? '');
    final tagline = TextEditingController(text: c.tagline ?? '');
    final support = TextEditingController(text: c.supportPhone ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.brandingTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (controller, label) in [
                (name, l10n.displayNameLabel),
                (city, l10n.cityLabelLabel),
                (tagline, l10n.taglineLabel),
                (support, l10n.supportPhoneLabel),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextField(
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: label,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
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
    if (saved != true || !context.mounted) return;
    await _patch(context, ref, {
      'app_display_name': name.text.trim(),
      'city_label': city.text.trim(),
      'tagline': tagline.text.trim(),
      'support_phone': support.text.trim(),
    });
  }

  Future<void> _editAnnouncement(
    BuildContext context,
    WidgetRef ref,
    AppConfig c,
  ) async {
    final l10n = AppLocalizations.of(context);
    final text = TextEditingController(text: c.announcementText ?? '');
    var enabled = c.announcementEnabled;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.announcementTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: text,
                maxLines: 2,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: l10n.announcementTitle,
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
      'announcement_enabled': enabled,
      'announcement_text': text.text.trim(),
    });
  }

  Future<void> _editBookingControls(
    BuildContext context,
    WidgetRef ref,
    AppConfig c,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final message = TextEditingController(text: c.bookingsPausedMessage ?? '');
    final maxActive = TextEditingController(text: '${c.maxActiveBookings}');
    var paused = c.bookingsPaused;
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.bookingControlsTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.pauseBookingsLabel),
                value: paused,
                onChanged: (v) => setState(() => paused = v),
              ),
              TextField(
                controller: message,
                decoration: InputDecoration(
                  labelText: l10n.pausedMessageLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxActive,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.maxActiveLabel,
                  border: const OutlineInputBorder(),
                ),
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
    final max = int.tryParse(maxActive.text.trim());
    if (max == null || max < 1 || max > 100) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.invalidNumber)));
      return;
    }
    await _patch(context, ref, {
      'bookings_paused': paused,
      'bookings_paused_message': message.text.trim(),
      'max_active_bookings': max,
    });
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
