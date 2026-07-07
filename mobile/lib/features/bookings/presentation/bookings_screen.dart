import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../data/bookings_repository.dart';
import '../domain/booking.dart';

/// Opens the phone dialer; used on both sides of a matched booking.
Future<void> callNumber(String phone) =>
    launchUrl(Uri(scheme: 'tel', path: phone));

/// Modern status pill: soft tinted background + bold colored label
/// (replaces the heavy solid Chip everywhere).
Widget statusChip(BuildContext context, AppLocalizations l10n, String status) {
  final color = statusColor(context, status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      statusLabel(l10n, status),
      style: TextStyle(
          color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

String _two(int n) => n < 10 ? '0$n' : '$n';

String formatTime(DateTime t) =>
    '${_two(t.day)}/${_two(t.month)} ${_two(t.hour)}:${_two(t.minute)}';

String statusLabel(AppLocalizations l10n, String status) => switch (status) {
      'pending' => l10n.statusPending,
      'accepted' => l10n.statusAccepted,
      'en_route' => l10n.statusEnRoute,
      'arrived' => l10n.statusArrived,
      'in_progress' => l10n.statusInProgress,
      'completed' => l10n.statusCompleted,
      'cancelled' => l10n.statusCancelled,
      _ => status,
    };

Color statusColor(BuildContext context, String status) => switch (status) {
      'pending' => Colors.orange,
      'accepted' || 'en_route' => Colors.blue,
      'arrived' => Colors.deepPurple,
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
                  const SizedBox(height: 100),
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.receipt_long_outlined,
                          size: 44,
                          color: Theme.of(context).colorScheme.primary),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(l10n.noBookings,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
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

/// Compact 5-segment stepper:
/// Accepted → On the way → Arrived → Working → Done.
class _ProgressTimeline extends StatelessWidget {
  const _ProgressTimeline({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var i = 0; i < 5; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                color: i < step ? scheme.primary : scheme.outlineVariant,
              ),
            ),
          ),
          if (i < 4) const SizedBox(width: 4),
        ],
      ],
    );
  }
}

/// The trust handshake: customer shares this code at the door; the worker
/// cannot start the job without it.
class _ArrivalOtpBox extends StatelessWidget {
  const _ArrivalOtpBox({required this.otp});

  final String otp;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark
        ? Colors.amber.shade900.withValues(alpha: 0.3)
        : Colors.amber.shade50;
    final fg = dark ? Colors.amber.shade200 : Colors.amber.shade900;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.otpShareHint,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: fg),
          ),
          const SizedBox(height: 2),
          Text(
            otp.split('').join(' '),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: fg,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 6,
                ),
          ),
        ],
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
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openDetails(context, ref),
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
                statusChip(context, l10n, booking.status),
              ],
            ),
            if (booking.workerName != null)
              Row(
                children: [
                  Expanded(
                      child:
                          Text('${l10n.technician}: ${booking.workerName}')),
                  if (booking.workerPhone != null &&
                      booking.progressStep > 0 &&
                      booking.status != 'completed')
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      icon: Icon(Icons.call,
                          size: 20,
                          color: Theme.of(context).colorScheme.primary),
                      tooltip: l10n.callLabel,
                      onPressed: () => callNumber(booking.workerPhone!),
                    ),
                ],
              ),
            Text(booking.address,
                style: Theme.of(context).textTheme.bodySmall),
            if (booking.progressStep > 0 && booking.status != 'cancelled') ...[
              const SizedBox(height: 10),
              _ProgressTimeline(step: booking.progressStep),
            ],
            if (booking.showArrivalOtp) ...[
              const SizedBox(height: 10),
              _ArrivalOtpBox(otp: booking.arrivalOtp!),
            ],
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
                    onPressed: () => _cancelWithReason(context, ref),
                    child: Text(l10n.cancelBooking),
                  ),
                if (scope == 'past' && booking.status == 'completed')
                  TextButton.icon(
                    icon: const Icon(Icons.replay, size: 18),
                    label: Text(l10n.bookAgain),
                    onPressed: () => _bookAgain(context, ref),
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
      ),
    );
  }

  /// Real apps ask why — the reason lands in the DB + audit log so
  /// support/ops can see churn causes.
  Future<void> _cancelWithReason(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final reasons = <(String, String)>[
      ('change_of_plans', l10n.reasonChangeOfPlans),
      ('price_too_high', l10n.reasonPrice),
      ('booked_by_mistake', l10n.reasonMistake),
      ('worker_delay', l10n.reasonDelay),
      ('other', l10n.reasonOther),
    ];
    var selected = reasons.first.$1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.cancelReasonTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (key, label) in reasons)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(label),
                  leading: Icon(
                    selected == key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: selected == key
                        ? Theme.of(dialogContext).colorScheme.primary
                        : null,
                  ),
                  onTap: () => setState(() => selected = key),
                ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.cancelBooking),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(bookingsRepositoryProvider)
          .cancel(booking.id, reason: selected);
      _refresh(ref);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  Future<void> _bookAgain(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(bookingsRepositoryProvider).create(
            serviceId: booking.serviceId,
            address: booking.address,
            note: booking.note,
          );
      _refresh(ref);
      messenger.showSnackBar(SnackBar(content: Text(l10n.bookingCreated)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }

  void _openDetails(BuildContext context, WidgetRef ref) {
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    booking.serviceName,
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  booking.priceLabel,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(booking.address,
                style: Theme.of(sheetContext).textTheme.bodySmall),
            const SizedBox(height: 12),
            _timelineRow(sheetContext, l10n.statusPending, booking.createdAt),
            _timelineRow(
                sheetContext, l10n.statusAccepted, booking.acceptedAt),
            _timelineRow(sheetContext, l10n.statusArrived, booking.arrivedAt),
            _timelineRow(
                sheetContext, l10n.statusCompleted, booking.completedAt),
            _timelineRow(
                sheetContext, l10n.statusCancelled, booking.cancelledAt),
            if (booking.cancelReason != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${l10n.cancelReasonTitle} ${booking.cancelReason}',
                    style: Theme.of(sheetContext).textTheme.bodySmall),
              ),
            if (booking.discountPaise > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${l10n.couponApplied} ${booking.couponCode ?? ''}: '
                  '−${booking.discountLabel}',
                  style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                if (booking.workerName != null &&
                    booking.status != 'cancelled') ...[
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline, size: 18),
                      label: Text(l10n.chatTitle),
                      onPressed: () {
                        Navigator.of(sheetContext).pop();
                        context.push(
                            '/chat/${booking.id}?title=${Uri.encodeComponent(booking.workerName!)}');
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.share, size: 18),
                    label: Text(l10n.shareStatus),
                    onPressed: () {
                      final text = '${booking.serviceName} — '
                          '${statusLabel(l10n, booking.status)} · Servexa';
                      launchUrl(
                        Uri.parse(
                            'https://wa.me/?text=${Uri.encodeComponent(text)}'),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timelineRow(BuildContext context, String label, DateTime? time) {
    if (time == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(Icons.check_circle,
              size: 16, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 8),
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const Spacer(),
          Text(formatTime(time),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Theme.of(context).colorScheme.outline)),
        ],
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
                  filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
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
