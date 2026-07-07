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

final adminLogsProvider =
    FutureProvider.autoDispose.family<List<AuditEntry>, String>((ref, q) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get<Map<String, dynamic>>(
      '/api/v1/admin/audit?q=${Uri.encodeComponent(q)}');
  return (unwrapEnvelope(res) as List<dynamic>)
      .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
      .toList();
});

IconData _actionIcon(String action) {
  if (action.contains('created') || action.contains('registered')) {
    return Icons.add_circle_outline;
  }
  if (action.contains('blocked') || action.contains('rejected')) {
    return Icons.block;
  }
  if (action.contains('approved') || action.contains('resolved')) {
    return Icons.check_circle_outline;
  }
  if (action.contains('cancelled') || action.contains('closed')) {
    return Icons.cancel_outlined;
  }
  return Icons.history;
}

/// Latest 100 audit entries — the platform's flight recorder.
class AdminLogsScreen extends ConsumerStatefulWidget {
  const AdminLogsScreen({super.key});

  @override
  ConsumerState<AdminLogsScreen> createState() => _AdminLogsScreenState();
}

class _AdminLogsScreenState extends ConsumerState<AdminLogsScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final logs = ref.watch(adminLogsProvider(_query));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.logsAdmin)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              onSubmitted: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: l10n.searchLogs,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: logs.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (items) => RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(adminLogsProvider(_query)),
                child: ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final entry = items[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(_actionIcon(entry.action), size: 20),
                      title: Text(entry.action,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: Text(
                          '${entry.entityType} · ${entry.actorType}'
                          '${entry.actorPhone != null ? ' · ${entry.actorPhone}' : ''}'),
                      trailing: Text(formatTime(entry.createdAt),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outline)),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
