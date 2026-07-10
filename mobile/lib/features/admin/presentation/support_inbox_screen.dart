import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/page_bar.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/presentation/bookings_screen.dart' show formatTime;
import '../../support/data/support_repository.dart';

/// Admin support inbox: one card per customer conversation, 10 per page.
class SupportInboxScreen extends ConsumerStatefulWidget {
  const SupportInboxScreen({super.key});

  @override
  ConsumerState<SupportInboxScreen> createState() =>
      _SupportInboxScreenState();
}

class _SupportInboxScreenState extends ConsumerState<SupportInboxScreen> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final inbox = ref.watch(supportInboxProvider(_page));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportInbox)),
      body: Column(
        children: [
          Expanded(
            child: inbox.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (page) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(supportInboxProvider),
                child: page.items.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 120),
                        Icon(Icons.forum_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        Center(child: Text(l10n.noTickets)),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: page.items.length,
                        itemBuilder: (context, i) =>
                            _ThreadCard(thread: page.items[i]),
                      ),
              ),
            ),
          ),
          SafeArea(
            child: inbox.maybeWhen(
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

/// A conversation as a card: initial avatar, name + phone, last message
/// preview, time, and an "awaiting reply" accent when the customer spoke
/// last.
class _ThreadCard extends StatelessWidget {
  const _ThreadCard({required this.thread});

  final SupportThread thread;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final name = thread.fullName?.trim().isNotEmpty == true
        ? thread.fullName!.trim()
        : thread.phone;
    final awaiting = thread.awaitingReply;
    final accent = awaiting ? Colors.orange.shade700 : Colors.green.shade600;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(
            '/admin/support/${thread.userId}?title=${Uri.encodeComponent(name)}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: accent.withValues(alpha: 0.16),
                child: Text(
                  name.characters.first.toUpperCase(),
                  style: TextStyle(
                      color: accent,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: text.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        Text(formatTime(thread.lastAt),
                            style: text.labelSmall
                                ?.copyWith(color: scheme.outline)),
                      ],
                    ),
                    if (thread.fullName?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 1),
                      Text(thread.phone,
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant)),
                    ],
                    const SizedBox(height: 4),
                    Text(thread.lastBody,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                    if (awaiting) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.mark_chat_unread,
                                size: 13, color: accent),
                            const SizedBox(width: 4),
                            Text(l10n.awaitingReply,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: accent)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
