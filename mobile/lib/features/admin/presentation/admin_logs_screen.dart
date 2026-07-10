import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/presentation/bookings_screen.dart' show formatTime;

class AuditEntry {
  const AuditEntry({
    required this.action,
    required this.entityType,
    required this.actorType,
    required this.createdAt,
    this.actorPhone,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        action: json['action'] as String,
        entityType: json['entity_type'] as String,
        actorType: json['actor_type'] as String,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        actorPhone: json['actor_phone'] as String?,
      );

  final String action;
  final String entityType;
  final String actorType;
  final DateTime createdAt;
  final String? actorPhone;
}

typedef LogsPage = ({List<AuditEntry> items, int total, int page});

final adminLogsProvider = FutureProvider.autoDispose
    .family<LogsPage, (int, String)>((ref, key) async {
  final (page, q) = key;
  final dio = ref.watch(dioProvider);
  final res = await dio.get<Map<String, dynamic>>(
      '/api/v1/admin/audit?page=$page&q=${Uri.encodeComponent(q)}');
  final data = unwrapEnvelope(res) as Map<String, dynamic>;
  return (
    items: (data['items'] as List<dynamic>)
        .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    total: data['total'] as int,
    page: data['page'] as int,
  );
});

/// Icon + accent colour for a log line, grouped by the kind of action so
/// the eye can scan a page at a glance.
({IconData icon, Color color}) _logStyle(String action, ColorScheme scheme) {
  if (action.contains('created') || action.contains('registered')) {
    return (icon: Icons.add_circle_outline, color: Colors.green.shade600);
  }
  if (action.contains('blocked') || action.contains('rejected')) {
    return (icon: Icons.block, color: scheme.error);
  }
  if (action.contains('approved') || action.contains('resolved')) {
    return (icon: Icons.check_circle_outline, color: Colors.teal.shade600);
  }
  if (action.contains('cancelled') || action.contains('closed')) {
    return (icon: Icons.cancel_outlined, color: Colors.orange.shade700);
  }
  if (action.contains('login')) {
    return (icon: Icons.login, color: Colors.blue.shade600);
  }
  if (action.contains('logout')) {
    return (icon: Icons.logout, color: scheme.outline);
  }
  if (action.contains('updated') || action.contains('settings')) {
    return (icon: Icons.tune, color: Colors.indigo.shade400);
  }
  return (icon: Icons.history, color: scheme.primary);
}

/// Audit trail — the platform's flight recorder, 10 per page.
class AdminLogsScreen extends ConsumerStatefulWidget {
  const AdminLogsScreen({super.key});

  @override
  ConsumerState<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends ConsumerState<AdminLogsScreen> {
  int _page = 1;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final logs = ref.watch(adminLogsProvider((_page, _query)));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.logsAdmin)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              onSubmitted: (v) => setState(() {
                _query = v.trim();
                _page = 1;
              }),
              decoration: InputDecoration(
                hintText: l10n.searchLogs,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          Expanded(
            child: logs.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (page) {
                if (page.items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.history_toggle_off,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        Text(l10n.searchLogs,
                            style: Theme.of(context).textTheme.bodyMedium),
                      ],
                    ),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () async =>
                      ref.invalidate(adminLogsProvider((_page, _query))),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    itemCount: page.items.length,
                    itemBuilder: (context, i) =>
                        _LogCard(entry: page.items[i]),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: logs.maybeWhen(
              data: (page) {
                final lastPage = (page.total / 10).ceil().clamp(1, 99999);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.chevron_left, size: 18),
                        label: Text(l10n.prevLabel),
                        onPressed:
                            _page > 1 ? () => setState(() => _page--) : null,
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text('$_page / $lastPage',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600)),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.chevron_right, size: 18),
                        label: Text(l10n.nextLabel),
                        onPressed: _page < lastPage
                            ? () => setState(() => _page++)
                            : null,
                      ),
                    ],
                  ),
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),
          ),
        ],
      ),
    );
  }
}

/// A single log line as a card: coloured category chip, the action in a
/// mono-ish weight, the entity/actor breadcrumbs, and a right-aligned time.
class _LogCard extends StatelessWidget {
  const _LogCard({required this.entry});

  final AuditEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final style = _logStyle(entry.action, scheme);
    final crumbs = [
      entry.entityType,
      entry.actorType,
      if (entry.actorPhone != null) entry.actorPhone!,
    ].join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: style.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(style.icon, size: 20, color: style.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.action,
                    style: text.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(crumbs,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(formatTime(entry.createdAt),
              style: text.labelSmall?.copyWith(color: scheme.outline)),
        ],
      ),
    );
  }
}
