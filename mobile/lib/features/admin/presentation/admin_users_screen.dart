import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/presentation/bookings_screen.dart' show formatTime;

class ManagedUser {
  const ManagedUser({
    required this.id,
    required this.phone,
    required this.isBlocked,
    required this.roles,
    required this.createdAt,
    this.fullName,
    this.city,
    this.blockReason,
  });

  factory ManagedUser.fromJson(Map<String, dynamic> json) => ManagedUser(
        id: json['id'] as String,
        phone: json['phone'] as String,
        isBlocked: json['is_blocked'] as bool? ?? false,
        roles: (json['roles'] as List<dynamic>? ?? []).cast<String>(),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        fullName: json['full_name'] as String?,
        city: json['city'] as String?,
        blockReason: json['block_reason'] as String?,
      );

  final String id;
  final String phone;
  final bool isBlocked;
  final List<String> roles;
  final DateTime createdAt;
  final String? fullName;
  final String? city;
  final String? blockReason;
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
              border: const OutlineInputBorder(),
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
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(user.fullName ?? user.phone,
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('${l10n.phoneLabel}: ${user.phone}'),
            if (user.city != null) Text('${l10n.cityFieldLabel}: ${user.city}'),
            Text('${l10n.navProfile}: ${user.roles.join(', ')}'),
            Text('${l10n.statusPending.split(' ').first}: '
                '${user.isBlocked ? l10n.blockedLabel : l10n.active}'),
            if (user.blockReason != null)
              Text('${l10n.blockReasonLabel}: ${user.blockReason}'),
            Text(formatTime(user.createdAt),
                style: Theme.of(sheetContext).textTheme.bodySmall),
          ],
        ),
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
                      leading: CircleAvatar(
                        backgroundColor: user.isBlocked
                            ? Colors.red.shade100
                            : Colors.green.shade50,
                        child: Icon(
                          user.isBlocked ? Icons.block : Icons.person,
                          color: user.isBlocked
                              ? Colors.red.shade700
                              : Colors.green.shade700,
                          size: 20,
                        ),
                      ),
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
