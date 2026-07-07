import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../profile/presentation/profile_screen.dart' show meProvider;
import '../data/chat_repository.dart';

const _maxAttachmentBytes = 15 * 1024 * 1024;

/// Booking chat: customer ↔ assigned worker. Polls every 5 s (v1;
/// WebSockets later). Attachments: PNG/JPG/MP4 up to 15 MB.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.bookingId, required this.title});

  final String bookingId;
  final String title;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  Timer? _poll;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) ref.invalidate(chatMessagesProvider(widget.bookingId));
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _sendText() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = true);
    try {
      await ref.read(chatRepositoryProvider).sendText(widget.bookingId, body);
      _input.clear();
      ref.invalidate(chatMessagesProvider(widget.bookingId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _attach() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo),
              title: Text(l10n.attachPhoto),
              onTap: () => Navigator.of(sheetContext).pop('photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: Text(l10n.attachVideo),
              onTap: () => Navigator.of(sheetContext).pop('video'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;

    final picker = ImagePicker();
    final XFile? picked = choice == 'photo'
        ? await picker.pickImage(source: ImageSource.gallery, imageQuality: 85)
        : await picker.pickVideo(
            source: ImageSource.gallery,
            maxDuration: const Duration(seconds: 30));
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    final name = picked.name.toLowerCase();
    final mime = name.endsWith('.png')
        ? 'image/png'
        : (name.endsWith('.jpg') || name.endsWith('.jpeg'))
            ? 'image/jpeg'
            : name.endsWith('.mp4')
                ? 'video/mp4'
                : null;
    if (mime == null || bytes.length > _maxAttachmentBytes) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.mediaTooLarge)));
      return;
    }
    setState(() => _sending = true);
    try {
      await ref
          .read(chatRepositoryProvider)
          .sendAttachment(widget.bookingId, bytes, mime);
      ref.invalidate(chatMessagesProvider(widget.bookingId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final messages = ref.watch(chatMessagesProvider(widget.bookingId));
    final myId = ref.watch(meProvider).maybeWhen(
        data: (me) => me['id'] as String?, orElse: () => null);

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: messages.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (items) => ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                itemBuilder: (context, i) {
                  final message = items[items.length - 1 - i];
                  return _Bubble(
                    message: message,
                    mine: message.senderId == myId,
                  );
                },
              ),
            ),
          ),
          if (_sending) const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.attach_file),
                    tooltip: l10n.attachPhoto,
                    onPressed: _sending ? null : _attach,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendText(),
                      decoration: InputDecoration(
                        hintText: l10n.typeMessage,
                        filled: true,
                        fillColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: _sending ? null : _sendText,
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

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    Widget content;
    if (message.isImage) {
      final bytes = ref
          .watch(chatAttachmentProvider((message.bookingId, message.id)))
          .maybeWhen(data: (b) => b, orElse: () => null);
      content = bytes == null
          ? const SizedBox(
              width: 160,
              height: 120,
              child: Center(child: CircularProgressIndicator()),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(bytes,
                  width: 200, fit: BoxFit.cover, gaplessPlayback: true),
            );
    } else if (message.isVideo) {
      content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam,
              size: 18, color: mine ? scheme.onPrimary : scheme.onSurface),
          const SizedBox(width: 6),
          Text(
            l10n.videoLabel,
            style:
                TextStyle(color: mine ? scheme.onPrimary : scheme.onSurface),
          ),
        ],
      );
    } else {
      content = Text(
        message.body ?? '',
        style: TextStyle(color: mine ? scheme.onPrimary : scheme.onSurface),
      );
    }
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: mine ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(mine ? 14 : 2),
            bottomRight: Radius.circular(mine ? 2 : 14),
          ),
        ),
        child: content,
      ),
    );
  }
}
