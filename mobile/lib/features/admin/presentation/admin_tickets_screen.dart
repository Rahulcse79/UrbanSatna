import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/page_bar.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../support/data/tickets_repository.dart';
import '../../support/presentation/my_tickets_screen.dart' show TicketCard;

/// Admin support queue: every customer issue, resolve with a note.
class AdminTicketsScreen extends ConsumerStatefulWidget {
  const AdminTicketsScreen({super.key});

  @override
  ConsumerState<AdminTicketsScreen> createState() =>
      _AdminTicketsScreenState();
}

class _AdminTicketsScreenState extends ConsumerState<AdminTicketsScreen> {
  String _status = 'open';
  int _page = 1;

  Future<void> _resolve(Ticket ticket) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final note = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.resolveTicket),
        content: TextField(
          controller: note,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: l10n.resolutionLabel,
            filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.resolveTicket),
          ),
        ],
      ),
    );
    if (confirmed != true || note.text.trim().isEmpty) return;
    try {
      await ref
          .read(ticketsRepositoryProvider)
          .resolve(ticket.id, note.text.trim());
      ref.invalidate(adminTicketsProvider);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tickets = ref.watch(adminTicketsProvider((_status, _page)));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.ticketsAdmin)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'open', label: Text(l10n.openLabel)),
                ButtonSegment(
                    value: 'resolved', label: Text(l10n.resolvedLabel)),
              ],
              selected: {_status},
              // Switching queue starts from the first page.
              onSelectionChanged: (selection) => setState(() {
                _status = selection.first;
                _page = 1;
              }),
            ),
          ),
          Expanded(
            child: tickets.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (page) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(adminTicketsProvider),
                child: page.items.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 100),
                        Icon(Icons.inbox_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        Center(child: Text(l10n.noTickets)),
                      ])
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        itemCount: page.items.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, i) => TicketCard(
                          ticket: page.items[i],
                          trailing: page.items[i].closed
                              ? null
                              : Wrap(
                                  spacing: 8,
                                  children: [
                                    OutlinedButton(
                                      onPressed: () async {
                                        final messenger =
                                            ScaffoldMessenger.of(context);
                                        try {
                                          await ref
                                              .read(
                                                  ticketsRepositoryProvider)
                                              .close(page.items[i].id);
                                          ref.invalidate(
                                              adminTicketsProvider);
                                        } catch (e) {
                                          messenger.showSnackBar(SnackBar(
                                              content: Text(
                                                  apiErrorMessage(e))));
                                        }
                                      },
                                      child: Text(l10n.closeTicket),
                                    ),
                                    if (page.items[i].open)
                                      FilledButton(
                                        onPressed: () =>
                                            _resolve(page.items[i]),
                                        child: Text(l10n.resolveTicket),
                                      ),
                                  ],
                                ),
                        ),
                      ),
              ),
            ),
          ),
          SafeArea(
            child: tickets.maybeWhen(
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
