import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import 'admin_panel_screen.dart' show adminStatsProvider;

/// The admin's home tab: live platform numbers plus quick actions into
/// every admin tool. Admins don't book services, so this replaces the
/// customer Home entirely.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final stats = ref.watch(adminStatsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminDashboard)),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminStatsProvider),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            stats.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(apiErrorMessage(e)),
              ),
              data: (s) => _StatsGrid(stats: s),
            ),
            const SizedBox(height: 18),
            Text(l10n.quickActions,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 2.6,
              children: [
                _ActionCard(
                  icon: Icons.how_to_reg,
                  label: l10n.workerApprovals,
                  color: Colors.purple,
                  route: '/admin/approvals',
                ),
                _ActionCard(
                  icon: Icons.group,
                  label: l10n.usersAdmin,
                  color: Colors.teal,
                  route: '/admin/users',
                ),
                _ActionCard(
                  icon: Icons.category,
                  label: l10n.manageCatalog,
                  color: Colors.indigo,
                  route: '/admin/catalog',
                ),
                _ActionCard(
                  icon: Icons.local_offer,
                  label: l10n.couponsAdmin,
                  color: Colors.pink,
                  route: '/admin/coupons',
                ),
                _ActionCard(
                  icon: Icons.confirmation_number,
                  label: l10n.ticketsAdmin,
                  color: Colors.orange,
                  route: '/admin/tickets',
                ),
                _ActionCard(
                  icon: Icons.forum,
                  label: l10n.supportInbox,
                  color: Colors.green,
                  route: '/admin/support',
                ),
                _ActionCard(
                  icon: Icons.history,
                  label: l10n.logsAdmin,
                  color: Colors.blueGrey,
                  route: '/admin/logs',
                ),
                _ActionCard(
                  icon: Icons.tune,
                  label: l10n.appSettingsTitle,
                  color: Colors.blue,
                  route: '/admin',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.admin_panel_settings,
                      size: 18, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(l10n.adminPanel,
                        style: text.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The six platform metrics, colour-coded for at-a-glance scanning.
class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats});

  final Map<String, dynamic> stats;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    String rupees(dynamic paise) =>
        '₹${(((paise as int?) ?? 0) / 100).toStringAsFixed(0)}';
    final tiles = <(String, String, IconData, MaterialColor)>[
      (
        '${stats['bookings_today'] ?? 0}',
        l10n.statBookingsToday,
        Icons.receipt_long,
        Colors.indigo
      ),
      (
        rupees(stats['revenue_today_paise']),
        l10n.statRevenueToday,
        Icons.currency_rupee,
        Colors.green
      ),
      (
        '${stats['active_bookings'] ?? 0}',
        l10n.statActive,
        Icons.pending_actions,
        Colors.blue
      ),
      (
        '${stats['open_tickets'] ?? 0}',
        l10n.statOpenTickets,
        Icons.confirmation_number,
        Colors.orange
      ),
      (
        '${stats['pending_applications'] ?? 0}',
        l10n.statPendingKyc,
        Icons.how_to_reg,
        Colors.purple
      ),
      (
        '${stats['total_users'] ?? 0}',
        l10n.statUsers,
        Icons.group,
        Colors.teal
      ),
    ];
    return GridView.count(
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
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon,
                    size: 20, color: dark ? color.shade200 : color.shade700),
                const Spacer(),
                Text(value,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                        color: dark ? color.shade100 : color.shade900)),
                Text(label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.route,
  });

  final IconData icon;
  final String label;
  final MaterialColor color;
  final String route;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push(route),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: dark
                      ? color.shade900.withValues(alpha: 0.4)
                      : color.shade50,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon,
                    size: 19, color: dark ? color.shade200 : color.shade700),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
