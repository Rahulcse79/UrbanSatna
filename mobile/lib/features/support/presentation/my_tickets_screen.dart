import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/presentation/bookings_screen.dart' show formatTime;
import '../data/tickets_repository.dart';

/// Customer's raised issues with their resolution status.
class MyTicketsScreen extends ConsumerWidget {
  const MyTicketsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final tickets = ref.watch(myTicketsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.myTickets)),
      body: tickets.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(myTicketsProvider),
          child: items.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 120),
                  Icon(Icons.support_agent,
                      size: 56, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Center(child: Text(l10n.noTickets)),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) => TicketCard(
                    ticket: items[i],
                    // Reopen only while 'resolved' — a closed ticket is
                    // the admin's final word.
                    trailing: items[i].resolved
                        ? OutlinedButton.icon(
                            icon: const Icon(Icons.refresh, size: 18),
                            label: Text(l10n.reopenTicket),
                            onPressed: () async {
                              final messenger =
                                  ScaffoldMessenger.of(context);
                              try {
                                await ref
                                    .read(ticketsRepositoryProvider)
                                    .reopen(items[i].id);
                                ref.invalidate(myTicketsProvider);
                              } catch (e) {
                                messenger.showSnackBar(SnackBar(
                                    content: Text(apiErrorMessage(e))));
                              }
                            },
                          )
                        : null,
                  ),
                ),
        ),
      ),
    );
  }
}

class TicketCard extends StatelessWidget {
  const TicketCard({super.key, required this.ticket, this.trailing});

  final Ticket ticket;
  final Widget? trailing;

  ({Color color, String label}) _status(AppLocalizations l10n) {
    if (ticket.open) return (color: Colors.orange.shade700, label: l10n.openLabel);
    if (ticket.closed) return (color: Colors.blueGrey, label: l10n.closedLabel);
    return (color: Colors.green.shade600, label: l10n.resolvedLabel);
  }

  ({Color color, IconData icon, String label})? _priority(
      AppLocalizations l10n) {
    switch (ticket.priority) {
      case TicketPriority.urgent:
        return (
          color: Colors.red.shade600,
          icon: Icons.priority_high,
          label: l10n.priorityUrgent
        );
      case TicketPriority.waiting:
        return (
          color: Colors.amber.shade800,
          icon: Icons.schedule,
          label: l10n.priorityWaiting
        );
      case TicketPriority.none:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final status = _status(l10n);
    final priority = _priority(l10n);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        // Accent stripe: urgent → priority colour, else the status colour.
        border: Border(
          left: BorderSide(
              color: priority?.color ?? status.color, width: 4),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(ticket.subject,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 8),
                _Badge(color: status.color, label: status.label),
              ],
            ),
            if (priority != null) ...[
              const SizedBox(height: 6),
              _Pill(
                  color: priority.color,
                  icon: priority.icon,
                  label: priority.label),
            ],
            if (ticket.fullName != null || ticket.phone != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.person_outline,
                      size: 15, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                        '${ticket.fullName ?? ''} ${ticket.phone ?? ''}'.trim(),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(ticket.message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.schedule,
                    size: 14, color: scheme.outline),
                const SizedBox(width: 4),
                Text(formatTime(ticket.createdAt),
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.outline)),
                if (ticket.bookingId != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.receipt_long_outlined,
                      size: 14, color: scheme.outline),
                  const SizedBox(width: 4),
                  Text('#${ticket.bookingId!.substring(0, 8)}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: scheme.outline)),
                ],
              ],
            ),
            // A reopened ticket is open again — its old resolution is
            // history, not the current answer.
            if (ticket.resolution != null && !ticket.open) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: Colors.green.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${l10n.resolutionLabel}: ${ticket.resolution}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerRight, child: trailing!),
            ],
          ],
        ),
      ),
    );
  }
}

/// Solid status badge (pill with white text).
class _Badge extends StatelessWidget {
  const _Badge({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 11.5,
              fontWeight: FontWeight.w700)),
    );
  }
}

/// Tinted pill with a leading icon (priority indicator).
class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.icon, required this.label});

  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
