import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_theme.dart';
import '../../../l10n/gen/app_localizations.dart';

final adminStatsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get<Map<String, dynamic>>('/api/v1/admin/stats');
  return unwrapEnvelope(res) as Map<String, dynamic>;
});

/// Admin hub: live dashboard numbers + runtime controls that apply to
/// every user instantly (PRODUCT.md §6.5 — the control plane).
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
          Consumer(builder: (context, ref, _) {
            final stats = ref.watch(adminStatsProvider).maybeWhen(
                data: (s) => s, orElse: () => null);
            if (stats == null) return const SizedBox.shrink();
            String rupees(dynamic paise) =>
                '₹${(((paise as int?) ?? 0) / 100).toStringAsFixed(0)}';
            // Each metric gets its own color for at-a-glance scanning.
            final tiles = <(String, String, IconData, MaterialColor)>[
              ('${stats['bookings_today'] ?? 0}', l10n.statBookingsToday,
                  Icons.receipt_long, Colors.indigo),
              (rupees(stats['revenue_today_paise']), l10n.statRevenueToday,
                  Icons.currency_rupee, Colors.green),
              ('${stats['active_bookings'] ?? 0}', l10n.statActive,
                  Icons.pending_actions, Colors.blue),
              ('${stats['open_tickets'] ?? 0}', l10n.statOpenTickets,
                  Icons.confirmation_number, Colors.orange),
              ('${stats['pending_applications'] ?? 0}', l10n.statPendingKyc,
                  Icons.how_to_reg, Colors.purple),
              ('${stats['total_users'] ?? 0}', l10n.statUsers, Icons.group,
                  Colors.teal),
            ];
            final dark = Theme.of(context).brightness == Brightness.dark;
            final scheme = Theme.of(context).colorScheme;
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.0,
                children: [
                  for (final (value, label, icon, color) in tiles)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: dark
                            ? color.shade900.withValues(alpha: 0.32)
                            : color.shade50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: color.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon,
                              size: 20,
                              color: dark
                                  ? color.shade200
                                  : color.shade700),
                          const Spacer(),
                          Text(value,
                              style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: dark
                                      ? color.shade100
                                      : color.shade900)),
                          Text(label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                      color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                ],
              ),
            );
          }),
          ListTile(
            leading: const Icon(Icons.how_to_reg),
            title: Text(l10n.workerApprovals),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/admin/approvals'),
          ),
          ListTile(
            leading: const Icon(Icons.group),
            title: Text(l10n.usersAdmin),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/admin/users'),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: Text(l10n.logsAdmin),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/admin/logs'),
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
            leading: const Icon(Icons.forum),
            title: Text(l10n.supportInbox),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/admin/support'),
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
                SwitchListTile(
                  secondary: const Icon(Icons.support_agent),
                  title: Text(l10n.supportOnlineToggle),
                  value: c.supportOnline,
                  onChanged: (v) =>
                      _patch(context, ref, {'support_online': v}),
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
                  leading: const Icon(Icons.policy),
                  title: Text(l10n.userPolicyTitle),
                  subtitle: Text(
                    c.userPolicyText ?? c.acceptanceText ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _editPolicy(context, ref, c),
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
                      filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
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
                  filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
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
                  filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxActive,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.maxActiveLabel,
                  filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
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

  /// User Policy & acceptance line: fully admin-written, shown at
  /// registration (empty policy falls back to the terms URL).
  Future<void> _editPolicy(
    BuildContext context,
    WidgetRef ref,
    AppConfig c,
  ) async {
    final l10n = AppLocalizations.of(context);
    final policy = TextEditingController(text: c.userPolicyText ?? '');
    final acceptance = TextEditingController(text: c.acceptanceText ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.userPolicyTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: policy,
                minLines: 5,
                maxLines: 12,
                decoration: InputDecoration(
                  labelText: l10n.policyTextLabel,
                  alignLabelWithHint: true,
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: acceptance,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.acceptanceTextLabel,
                  filled: true,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none),
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
      'user_policy_text': policy.text.trim(),
      'acceptance_text': acceptance.text.trim(),
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
                  filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: subtitle,
                decoration: InputDecoration(
                  labelText: l10n.promoSubtitleLabel,
                  filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
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
