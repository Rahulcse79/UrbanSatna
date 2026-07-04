import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/bookings_repository.dart';
import '../domain/booking.dart';

String statusLabel(AppLocalizations l10n, String status) => switch (status) {
      'pending' => l10n.statusPending,
      'accepted' => l10n.statusAccepted,
      'en_route' => l10n.statusEnRoute,
      'in_progress' => l10n.statusInProgress,
      'completed' => l10n.statusCompleted,
      'cancelled' => l10n.statusCancelled,
      _ => status,
    };

Color statusColor(BuildContext context, String status) => switch (status) {
      'pending' => Colors.orange,
      'accepted' || 'en_route' => Colors.blue,
      'in_progress' => Colors.teal,
      'completed' => Colors.green,
      'cancelled' => Theme.of(context).colorScheme.error,
      _ => Theme.of(context).colorScheme.outline,
    };

/// Customer bookings: Active / Past tabs (mockup "My Bookings").
class BookingsScreen extends ConsumerWidget {
  const BookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.navBookings),
          bottom: TabBar(
            tabs: [Tab(text: l10n.active), Tab(text: l10n.past)],
          ),
        ),
        body: const TabBarView(
          children: [
            _BookingsList(scope: 'active'),
            _BookingsList(scope: 'past'),
          ],
        ),
      ),
    );
  }
}

class _BookingsList extends ConsumerWidget {
  const _BookingsList({required this.scope});

  final String scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final bookings = ref.watch(myBookingsProvider(scope));
    return bookings.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(apiErrorMessage(e))),
      data: (items) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(myBookingsProvider(scope)),
        child: items.isEmpty
            ? ListView(
                children: [
                  const SizedBox(height: 120),
                  Icon(Icons.receipt_long,
                      size: 56,
                      color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Center(child: Text(l10n.noBookings)),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, i) =>
                    _BookingCard(booking: items[i], scope: scope),
              ),
      ),
    );
  }
}

class _BookingCard extends ConsumerWidget {
  const _BookingCard({required this.booking, required this.scope});

  final Booking booking;
  final String scope;

  void _refresh(WidgetRef ref) {
    ref.invalidate(myBookingsProvider('active'));
    ref.invalidate(myBookingsProvider('past'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${booking.serviceName} (${booking.categoryName})',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Chip(
                  label: Text(statusLabel(l10n, booking.status)),
                  labelStyle: const TextStyle(color: Colors.white, fontSize: 12),
                  backgroundColor: statusColor(context, booking.status),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            if (booking.workerName != null)
              Text('${l10n.technician}: ${booking.workerName}'),
            Text(booking.address,
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Row(
              children: [
                Text(booking.priceLabel,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (booking.rating != null) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.star, size: 16, color: Colors.amber),
                  Text(' ${booking.rating}'),
                ],
                const Spacer(),
                if (booking.cancellable)
                  TextButton(
                    onPressed: () async {
                      try {
                        await ref
                            .read(bookingsRepositoryProvider)
                            .cancel(booking.id);
                        _refresh(ref);
                      } catch (e) {
                        messenger.showSnackBar(
                            SnackBar(content: Text(apiErrorMessage(e))));
                      }
                    },
                    child: Text(l10n.cancelBooking),
                  ),
                if (booking.ratable)
                  FilledButton(
                    onPressed: () => _openRatingDialog(context, ref),
                    child: Text(l10n.rateNow),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRatingDialog(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final review = TextEditingController();
    var stars = 5;

    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.yourRating),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 1; i <= 5; i++)
                    IconButton(
                      icon: Icon(
                        i <= stars ? Icons.star : Icons.star_border,
                        color: Colors.amber,
                        size: 32,
                      ),
                      onPressed: () => setState(() => stars = i),
                    ),
                ],
              ),
              TextField(
                controller: review,
                decoration: InputDecoration(
                  labelText: l10n.reviewLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.submit),
            ),
          ],
        ),
      ),
    );

    if (submitted != true) return;
    try {
      await ref
          .read(bookingsRepositoryProvider)
          .rate(booking.id, stars, review.text.trim());
      _refresh(ref);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}
