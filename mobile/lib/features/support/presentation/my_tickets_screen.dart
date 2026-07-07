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
                  itemBuilder: (context, i) => TicketCard(ticket: items[i]),
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

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(ticket.subject,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                Chip(
                  label: Text(
                      ticket.open ? l10n.openLabel : l10n.resolvedLabel),
                  labelStyle:
                      const TextStyle(color: Colors.white, fontSize: 12),
                  backgroundColor:
                      ticket.open ? Colors.orange : Colors.green,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (ticket.fullName != null || ticket.phone != null)
              Text('${ticket.fullName ?? ''} ${ticket.phone ?? ''}'.trim(),
                  style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(ticket.message, style: theme.textTheme.bodyMedium),
            const SizedBox(height: 4),
            Text(formatTime(ticket.createdAt),
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.outline)),
            if (ticket.resolution != null) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${l10n.resolutionLabel}: ${ticket.resolution}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: trailing!),
            ],
          ],
        ),
      ),
    );
  }
}
