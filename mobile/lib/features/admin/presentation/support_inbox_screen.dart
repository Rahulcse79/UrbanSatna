import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/presentation/bookings_screen.dart' show formatTime;
import '../../support/data/support_repository.dart';

/// Admin support inbox: one row per customer conversation. The chatbot
/// button (bottom-left) shows whether the bot is answering — green when
/// the team is offline (bot active), red when humans are on shift —
/// and tapping it flips support_online.
class SupportInboxScreen extends ConsumerWidget {
  const SupportInboxScreen({super.key});

  Future<void> _toggleBot(
    BuildContext context,
    WidgetRef ref,
    bool supportOnline,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(dioProvider).patch<Map<String, dynamic>>(
          '/api/v1/app-config',
          data: {'support_online': !supportOnline});
      ref.invalidate(appConfigProvider);
      messenger.showSnackBar(SnackBar(
          // support goes online → bot goes idle, and vice versa
          content: Text(supportOnline ? l10n.botActive : l10n.botIdle)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final inbox = ref.watch(supportInboxProvider);
    final supportOnline = ref.watch(appConfigProvider).maybeWhen(
        data: (c) => c.supportOnline, orElse: () => false);
    final botActive = !supportOnline;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.supportInbox)),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      floatingActionButton: FloatingActionButton(
        tooltip: botActive ? l10n.botActive : l10n.botIdle,
        onPressed: () => _toggleBot(context, ref, supportOnline),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.smart_toy_outlined, size: 28),
            Positioned(
              right: -3,
              top: -3,
              child: Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: botActive ? Colors.green : Colors.red,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.surface,
                      width: 2),
                ),
              ),
            ),
          ],
        ),
      ),
      body: inbox.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (threads) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(supportInboxProvider),
          child: threads.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 120),
                  Center(child: Text(l10n.noTickets)),
                ])
              : ListView.builder(
                  itemCount: threads.length,
                  itemBuilder: (context, i) {
                    final thread = threads[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: thread.awaitingReply
                            ? Colors.orange.shade100
                            : Colors.green.shade50,
                        child: Icon(
                          thread.awaitingReply
                              ? Icons.mark_chat_unread
                              : Icons.chat_bubble_outline,
                          size: 20,
                          color: thread.awaitingReply
                              ? Colors.orange.shade800
                              : Colors.green.shade700,
                        ),
                      ),
                      title: Text(thread.fullName ?? thread.phone),
                      subtitle: Text(thread.lastBody,
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(formatTime(thread.lastAt),
                              style:
                                  Theme.of(context).textTheme.bodySmall),
                          if (thread.awaitingReply)
                            Text(l10n.awaitingReply,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange.shade800,
                                    fontWeight: FontWeight.w600)),
                        ],
                      ),
                      onTap: () => context.push(
                          '/admin/support/${thread.userId}?title=${Uri.encodeComponent(thread.fullName ?? thread.phone)}'),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
