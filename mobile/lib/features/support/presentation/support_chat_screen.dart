import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/bot_avatar.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/support_repository.dart';

/// Mirror of `MAX_ATTACHMENT_BYTES` in the backend's support handler:
/// PNG/JPG images or short MP4 videos, ≤ 10 MB. Client-side validation
/// keeps the user off the wire when the file is obviously too big; the
/// server enforces the same limit for direct-API callers.
const int _maxAttachmentBytes = 10 * 1024 * 1024;

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
  // 0.0..1.0 while an attachment upload is in flight; null otherwise.
  double? _uploadProgress;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) {
      // Don't invalidate mid-upload — the poll would race the FutureProvider
      // that owns onSendProgress and the progress bar would flicker.
      if (mounted && _uploadProgress == null) {
        ref.invalidate(supportThreadProvider(widget.userId));
      }
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

  /// Kicks off the attach flow: pick photo/video → validate size+type →
  /// preview + confirm → upload with progress. Any early step out simply
  /// returns; the upload path always clears state, success or error.
  Future<void> _attach() async {
    if (_sending) return;
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
            maxDuration: const Duration(seconds: 30),
          );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    // Extension-based type check mirrors the backend's magic-byte gate.
    final name = picked.name.toLowerCase();
    final mime = name.endsWith('.png')
        ? 'image/png'
        : (name.endsWith('.jpg') || name.endsWith('.jpeg'))
            ? 'image/jpeg'
            : name.endsWith('.mp4')
                ? 'video/mp4'
                : null;
    if (mime == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.mediaTypeError)));
      return;
    }
    if (bytes.length > _maxAttachmentBytes) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.mediaSizeError)));
      return;
    }
    if (!mounted) return;

    // Preview + confirm before spending bandwidth on the upload.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _AttachmentPreviewDialog(
        bytes: bytes,
        mime: mime,
        fileName: picked.name,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _sending = true;
      _uploadProgress = 0;
    });
    try {
      await ref.read(supportRepositoryProvider).sendAttachment(
            widget.userId,
            bytes,
            mime,
            onProgress: (sent, total) {
              if (!mounted || total <= 0) return;
              setState(() => _uploadProgress = sent / total);
            },
          );
      ref.invalidate(supportThreadProvider(widget.userId));
      if (widget.userId != null) ref.invalidate(supportInboxProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _uploadProgress = null;
        });
      }
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
                    final bubble = _MessageBubble(
                      message: message,
                      mine: mine,
                      isBot: isBot,
                      userId: widget.userId,
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
          if (_uploadProgress != null)
            _UploadIndicator(progress: _uploadProgress!)
          else if (_sending)
            const LinearProgressIndicator(minHeight: 2),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 8),
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

/// A determinate progress bar with an "Uploading N%" label. Falls back to
/// an indeterminate look right at 0% before Dio reports the first chunk.
class _UploadIndicator extends StatelessWidget {
  const _UploadIndicator({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final percent = (progress.clamp(0.0, 1.0) * 100).round();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${l10n.uploadingLabel} $percent%',
              style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress.clamp(0.0, 1.0) : null,
              minHeight: 4,
            ),
          ),
        ],
      ),
    );
  }
}

/// The chat bubble; the attachment message renders the image inline or a
/// video placeholder, while a text-only message keeps the previous look.
class _MessageBubble extends ConsumerWidget {
  const _MessageBubble({
    required this.message,
    required this.mine,
    required this.isBot,
    required this.userId,
  });

  final SupportMessage message;
  final bool mine;
  final bool isBot;
  // The `userId` scope this bubble was opened in — null for a customer
  // (my own thread), a customer id when an admin is viewing.
  final String? userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final onBubble = isBot
        ? scheme.onTertiaryContainer
        : mine
            ? scheme.onPrimary
            : scheme.onSurface;

    Widget? attachment;
    if (message.isImage) {
      final bytes = ref
          .watch(supportAttachmentProvider((userId, message.id)))
          .maybeWhen(data: (b) => b, orElse: () => null);
      attachment = bytes == null
          ? const SizedBox(
              width: 200,
              height: 140,
              child: Center(child: CircularProgressIndicator()),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(
                bytes,
                width: 220,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              ),
            );
    } else if (message.isVideo) {
      attachment = Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: onBubble.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.videocam, size: 18, color: onBubble),
            const SizedBox(width: 6),
            Text(l10n.videoLabel, style: TextStyle(color: onBubble)),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75),
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
                    color: onBubble.withValues(alpha: 0.7)),
              ),
            ),
          if (attachment != null) attachment,
          if (attachment != null && message.body.isNotEmpty)
            const SizedBox(height: 6),
          if (message.body.isNotEmpty)
            Text(message.body, style: TextStyle(color: onBubble)),
        ],
      ),
    );
  }
}

/// Full-screen preview of the pending attachment with Cancel / Send.
class _AttachmentPreviewDialog extends StatelessWidget {
  const _AttachmentPreviewDialog({
    required this.bytes,
    required this.mime,
    required this.fileName,
  });

  final Uint8List bytes;
  final String mime;
  final String fileName;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isImage = mime.startsWith('image/');
    // Human-readable size to reassure the user before we spend uplink on it.
    final kb = bytes.length / 1024;
    final sizeLabel =
        kb >= 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '${kb.round()} KB';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.previewAttachment,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            if (isImage)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(bytes, fit: BoxFit.contain),
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 28),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Icon(Icons.videocam,
                        size: 48, color: scheme.primary),
                    const SizedBox(height: 8),
                    Text(l10n.videoLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            const SizedBox(height: 10),
            Text(
              '$fileName · $sizeLabel',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.send, size: 18),
                  label: Text(l10n.attachPhoto),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
