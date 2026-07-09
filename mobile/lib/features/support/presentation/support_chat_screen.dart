import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/bot_avatar.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/support_repository.dart';

/// Live support chat. Customers get their own thread; admins pass the
/// customer's [userId]. Green/red dot mirrors the admin's online flag.
class SupportChatScreen extends ConsumerStatefulWidget {
  const SupportChatScreen({super.key, this.userId, this.title});

  final String? userId;
  final String? title;

  @override
  ConsumerState<SupportChatScreen> createState() =>
      _SupportChatScreenState();
}

class _SupportChatScreenState extends ConsumerState<SupportChatScreen> {
  final _input = TextEditingController();
  Timer? _poll;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) ref.invalidate(supportThreadProvider(widget.userId));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final body = (preset ?? _input.text).trim();
    if (body.isEmpty || _sending) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await ref.read(supportRepositoryProvider).send(widget.userId, body);
      _input.clear();
      ref.invalidate(supportThreadProvider(widget.userId));
      if (widget.userId != null) ref.invalidate(supportInboxProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final messages = ref.watch(supportThreadProvider(widget.userId));
    final online = ref.watch(appConfigProvider).maybeWhen(
        data: (c) => c.supportOnline, orElse: () => false);
    // For a customer, staff messages are "theirs"; in the admin view the
    // customer's messages are on the other side.
    final isAdminView = widget.userId != null;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Flexible(
              child: Text(widget.title ?? l10n.liveChat,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 8),
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: online ? Colors.green : Colors.red,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              online ? l10n.onlineLabel : l10n.offlineLabel,
              style: TextStyle(
                  fontSize: 12,
                  color: online ? Colors.green : Colors.red,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (items) {
                if (items.isEmpty && !isAdminView) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.support_agent,
                              size: 56, color: scheme.outline),
                          const SizedBox(height: 12),
                          Text(l10n.quickHelpHint,
                              textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            alignment: WrapAlignment.center,
                            children: [
                              for (final quick in [
                                l10n.quickBooking,
                                l10n.quickPayment,
                                l10n.quickWorker,
                                l10n.quickOther,
                              ])
                                ActionChip(
                                  label: Text(quick),
                                  onPressed: () => _send(quick),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final message = items[items.length - 1 - i];
                    final mine = isAdminView
                        ? message.fromSupport
                        : !message.fromSupport;
                    final isBot = message.fromBot;
                    final bubble = Container(
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      constraints: BoxConstraints(
                          maxWidth:
                              MediaQuery.of(context).size.width * 0.75),
                      decoration: BoxDecoration(
                        color: isBot
                            ? scheme.tertiaryContainer
                            : mine
                                ? scheme.primary
                                : scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (isBot)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 2),
                              child: Text(
                                l10n.botName,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onTertiaryContainer
                                        .withValues(alpha: 0.7)),
                              ),
                            ),
                          Text(
                            message.body,
                            style: TextStyle(
                                color: isBot
                                    ? scheme.onTertiaryContainer
                                    : mine
                                        ? scheme.onPrimary
                                        : scheme.onSurface),
                          ),
                        ],
                      ),
                    );
                    if (!isBot) {
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: bubble,
                      );
                    }
                    // Bot replies carry the mascot next to the bubble.
                    return Align(
                      alignment: mine
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: mine
                            ? [
                                Flexible(child: bubble),
                                const SizedBox(width: 6),
                                const BotAvatar(size: 26),
                              ]
                            : [
                                const BotAvatar(size: 26),
                                const SizedBox(width: 6),
                                Flexible(child: bubble),
                              ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          if (_sending) const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: l10n.typeMessage,
                        filled: true,
                        fillColor: scheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _sending ? null : _send,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
