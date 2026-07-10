import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/presentation/bookings_screen.dart' show formatTime;
import '../../worker/data/worker_repository.dart';

class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.phone,
    required this.isBlocked,
    required this.hasAvatar,
    required this.hasKycDoc,
    required this.hasKycSelfie,
    required this.roles,
    required this.createdAt,
    this.fullName,
    this.email,
    this.city,
    this.address,
    this.state,
    this.pincode,
    this.blockReason,
    this.applicationId,
    this.applicationStatus,
  });

  factory ManagedUser.fromJson(Map<String, dynamic> json) => ManagedUser(
        id: json['id'] as String,
        phone: json['phone'] as String,
        isBlocked: json['is_blocked'] as bool? ?? false,
        hasAvatar: json['has_avatar'] as bool? ?? false,
        hasKycDoc: json['has_kyc_doc'] as bool? ?? false,
        hasKycSelfie: json['has_kyc_selfie'] as bool? ?? false,
        roles: (json['roles'] as List<dynamic>? ?? []).cast<String>(),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        fullName: json['full_name'] as String?,
        email: json['email'] as String?,
        city: json['city'] as String?,
        address: json['address'] as String?,
        state: json['state'] as String?,
        pincode: json['pincode'] as String?,
        blockReason: json['block_reason'] as String?,
        applicationId: json['application_id'] as String?,
        applicationStatus: json['application_status'] as String?,
      );

  final String id;
  final String phone;
  final bool isBlocked;
  final bool hasAvatar;
  final bool hasKycDoc;
  final bool hasKycSelfie;
  final List<String> roles;
  final DateTime createdAt;
  final String? fullName;
  final String? email;
  final String? city;
  final String? address;
  final String? state;
  final String? pincode;
  final String? blockReason;

  /// Latest worker application — KYC documents hang off it.
  final String? applicationId;
  final String? applicationStatus;
}

typedef UsersPage = ({List<ManagedUser> items, int total, int page});

final adminUsersProvider = FutureProvider.autoDispose
    .family<UsersPage, (int, String)>((ref, key) async {
  final (page, q) = key;
  final dio = ref.watch(dioProvider);
  final res = await dio.get<Map<String, dynamic>>(
      '/api/v1/admin/users?page=$page&q=${Uri.encodeComponent(q)}');
  final data = unwrapEnvelope(res) as Map<String, dynamic>;
  return (
    items: (data['items'] as List<dynamic>)
        .map((u) => ManagedUser.fromJson(u as Map<String, dynamic>))
        .toList(),
    total: data['total'] as int,
    page: data['page'] as int,
  );
});

/// User management: search, 10/page, block/unblock with reason.
/// Blocked users cannot log in or refresh — sessions die on block.
class AdminUsersScreen extends ConsumerStatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  ConsumerState<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends ConsumerState<AdminUsersScreen> {
  int _page = 1;
  String _query = '';

  Future<void> _toggleBlock(ManagedUser user) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    String? reason;
    if (!user.isBlocked) {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${l10n.blockUser}: ${user.phone}'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: l10n.blockReasonLabel,
              filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.blockUser),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      reason = controller.text.trim();
    }
    try {
      final dio = ref.read(dioProvider);
      if (user.isBlocked) {
        await dio.post<Map<String, dynamic>>(
            '/api/v1/admin/users/${user.id}/unblock');
      } else {
        await dio.post<Map<String, dynamic>>(
          '/api/v1/admin/users/${user.id}/block',
          data: {if (reason != null && reason.isNotEmpty) 'reason': reason},
        );
      }
      ref.invalidate(adminUsersProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  void _showDetail(ManagedUser user) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => _UserDetailDialog(
        user: user,
        onToggleBlock: () {
          Navigator.of(dialogContext).pop();
          _toggleBlock(user);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final usersPage = ref.watch(adminUsersProvider((_page, _query)));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.usersAdmin)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              onSubmitted: (v) => setState(() {
                _query = v.trim();
                _page = 1;
              }),
              decoration: InputDecoration(
                hintText: l10n.searchUsers,
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
          Expanded(
            child: usersPage.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (page) => ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: page.items.length,
                itemBuilder: (context, i) {
                  final user = page.items[i];
                  return Card(
                    elevation: 0,
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      onTap: () => _showDetail(user),
                      leading: _UserAvatar(user: user, size: 40),
                      title: Text(user.fullName ?? user.phone),
                      subtitle: Text(
                        [
                          user.phone,
                          user.roles.join('/'),
                          if (user.isBlocked)
                            '${l10n.blockedLabel}: ${user.blockReason ?? ''}',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: TextButton(
                        onPressed: () => _toggleBlock(user),
                        child: Text(
                          user.isBlocked
                              ? l10n.unblockUser
                              : l10n.blockUser,
                          style: TextStyle(
                              color: user.isBlocked
                                  ? Colors.green.shade700
                                  : Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          SafeArea(
            child: usersPage.maybeWhen(
              data: (page) {
                final lastPage = (page.total / 10).ceil().clamp(1, 9999);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.chevron_left, size: 18),
                        label: Text(l10n.prevLabel),
                        onPressed: _page > 1
                            ? () => setState(() => _page--)
                            : null,
                      ),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
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

/// One avatar fetch per user per session — the bytes ride an authorized
/// dio call, which Image.network can't do.
final _avatarCache = <String, Future<Uint8List?>>{};

class _UserAvatar extends ConsumerWidget {
  const _UserAvatar({required this.user, required this.size});

  final ManagedUser user;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fallback = CircleAvatar(
      radius: size / 2,
      backgroundColor:
          user.isBlocked ? Colors.red.shade100 : Colors.green.shade50,
      child: Icon(
        user.isBlocked ? Icons.block : Icons.person,
        color: user.isBlocked ? Colors.red.shade700 : Colors.green.shade700,
        size: size * 0.5,
      ),
    );
    if (!user.hasAvatar) return fallback;
    final dio = ref.watch(dioProvider);
    final future = _avatarCache.putIfAbsent(user.id, () async {
      try {
        final res = await dio.get<List<int>>(
          '/api/v1/admin/users/${user.id}/avatar',
          options: Options(responseType: ResponseType.bytes),
        );
        final data = res.data;
        return data == null ? null : Uint8List.fromList(data);
      } on DioException {
        return null;
      }
    });
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        if (bytes == null) return fallback;
        return CircleAvatar(
            radius: size / 2, backgroundImage: MemoryImage(bytes));
      },
    );
  }
}

/// Centered user card: photo header, role/status pills, contact rows,
/// KYC documents and block/unblock — replaces the old bottom sheet.
class _UserDetailDialog extends ConsumerWidget {
  const _UserDetailDialog({required this.user, required this.onToggleBlock});

  final ManagedUser user;
  final VoidCallback onToggleBlock;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final email = user.email ?? '';
    final location = [user.address, user.city, user.state, user.pincode]
        .whereType<String>()
        .where((s) => s.trim().isNotEmpty)
        .join(', ');
    final blockReason = (user.blockReason ?? '').trim();
    final hasDocuments = user.hasKycDoc || user.hasKycSelfie;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 18),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [scheme.primaryContainer, scheme.tertiaryContainer],
                  ),
                ),
                child: Column(
                  children: [
                    _UserAvatar(user: user, size: 76),
                    const SizedBox(height: 12),
                    Text(
                      user.fullName ?? user.phone,
                      textAlign: TextAlign.center,
                      style: text.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimaryContainer),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      user.phone,
                      style: text.bodyMedium?.copyWith(
                          color: scheme.onPrimaryContainer
                              .withValues(alpha: 0.75)),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final role in user.roles)
                          _Pill(
                            label: role,
                            background: scheme.surface.withValues(alpha: 0.55),
                            foreground: scheme.onSurface,
                          ),
                        _Pill(
                          label:
                              user.isBlocked ? l10n.blockedLabel : l10n.active,
                          background: user.isBlocked
                              ? scheme.errorContainer
                              : Colors.green.shade100,
                          foreground: user.isBlocked
                              ? scheme.onErrorContainer
                              : Colors.green.shade900,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                child: Column(
                  children: [
                    if (email.isNotEmpty)
                      _InfoRow(icon: Icons.alternate_email, value: email),
                    if (location.isNotEmpty)
                      _InfoRow(
                          icon: Icons.location_on_outlined, value: location),
                    _InfoRow(
                        icon: Icons.event_outlined,
                        value: formatTime(user.createdAt)),
                    if (user.isBlocked && blockReason.isNotEmpty)
                      _InfoRow(
                        icon: Icons.block,
                        value: '${l10n.blockReasonLabel}: $blockReason',
                        color: scheme.error,
                      ),
                  ],
                ),
              ),
              if (user.applicationId != null)
                Container(
                  margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.badge_outlined, color: scheme.primary),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(l10n.documentsTitle,
                                style: text.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700)),
                            Text(
                              hasDocuments
                                  ? (user.applicationStatus ?? '')
                                  : l10n.notUploadedLabel,
                              style: text.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      FilledButton.tonal(
                        onPressed: hasDocuments
                            ? () => showDialog<void>(
                                  context: context,
                                  builder: (_) => _DocumentsDialog(user: user),
                                )
                            : null,
                        child: Text(l10n.viewDocuments),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(
                          MaterialLocalizations.of(context).closeButtonLabel),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: user.isBlocked
                          ? null
                          : FilledButton.styleFrom(
                              backgroundColor: scheme.error,
                              foregroundColor: scheme.onError),
                      onPressed: onToggleBlock,
                      child: Text(user.isBlocked
                          ? l10n.unblockUser
                          : l10n.blockUser),
                    ),
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

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.w700, color: foreground)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.value, this.color});

  final IconData icon;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color ?? scheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(value,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: color)),
          ),
        ],
      ),
    );
  }
}

/// KYC previews for the user's latest application; tap a photo to zoom.
class _DocumentsDialog extends ConsumerWidget {
  const _DocumentsDialog({required this.user});

  final ManagedUser user;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final repo = ref.watch(workerRepositoryProvider);
    final applicationId = user.applicationId!;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.documentsTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 14),
              if (user.hasKycDoc)
                _DocPreview(
                  label: l10n.kycDocLabel,
                  future: repo.kycImage(applicationId, 'doc'),
                ),
              if (user.hasKycSelfie)
                _DocPreview(
                  label: l10n.kycSelfieLabel,
                  future: repo.kycImage(applicationId, 'selfie'),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                      MaterialLocalizations.of(context).closeButtonLabel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocPreview extends StatelessWidget {
  const _DocPreview({required this.label, required this.future});

  final String label;
  final Future<Uint8List?> future;

  void _zoom(BuildContext context, Uint8List bytes) {
    showDialog<void>(
      context: context,
      builder: (zoomContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(child: Image.memory(bytes)),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.of(zoomContext).pop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: Theme.of(context)
                .textTheme
                .labelLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: FutureBuilder<Uint8List?>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return Container(
                  height: 160,
                  color: scheme.surfaceContainerHighest,
                  child: const Center(child: CircularProgressIndicator()),
                );
              }
              final bytes = snapshot.data;
              if (bytes == null) {
                return Container(
                  height: 100,
                  color: scheme.surfaceContainerHighest,
                  child: Center(child: Text(l10n.notUploadedLabel)),
                );
              }
              return GestureDetector(
                onTap: () => _zoom(context, bytes),
                child: Image.memory(bytes,
                    width: double.infinity, height: 200, fit: BoxFit.cover),
              );
            },
          ),
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}
