import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/data/bookings_repository.dart';
import '../../shell/current_tab.dart';
import '../data/catalog_repository.dart';
import '../domain/models.dart';

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({
    super.key,
    required this.categoryId,
    required this.categoryName,
  });

  final String categoryId;
  final String categoryName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final services = ref.watch(servicesProvider(categoryId));
    return Scaffold(
      appBar: AppBar(title: Text(categoryName)),
      body: services.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (items) => ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) => _ServiceTile(service: items[i]),
        ),
      ),
    );
  }
}

class _ServiceTile extends ConsumerWidget {
  const _ServiceTile({required this.service});

  final Service service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(service.name,
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  if (service.description != null)
                    Text(service.description!,
                        style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Text(
                    '${service.priceLabel} · ${service.durationMin} min',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
            FilledButton(
              onPressed: () => _openBookingSheet(context, ref),
              child: Text(l10n.bookNow),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBookingSheet(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final repo = ref.read(bookingsRepositoryProvider);
    final address = TextEditingController();
    final note = TextEditingController();
    final coupon = TextEditingController();
    double? lat;
    double? lng;
    int? quotedFinal;
    String? appliedCoupon;
    // Valid offers for this user (active + never used) — the dropdown.
    var offers = const <({String code, String label})>[];
    try {
      offers = await ref.read(availableCouponsProvider.future);
    } catch (_) {}
    if (!context.mounted) return;

    final booked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setState) => Padding(
          padding: EdgeInsets.fromLTRB(
              16, 16, 16, MediaQuery.of(sheetContext).viewInsets.bottom + 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                quotedFinal == null
                    ? '${service.name} — ${service.priceLabel}'
                    : '${service.name} — ₹${(quotedFinal! / 100).toStringAsFixed(0)}',
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              if (appliedCoupon != null)
                Text(
                  '${l10n.couponApplied}: $appliedCoupon',
                  style: TextStyle(
                      color: Colors.green.shade700,
                      fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: address,
                decoration: InputDecoration(
                  labelText: l10n.addressLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                decoration: InputDecoration(
                  labelText: l10n.noteLabel,
                  border: const OutlineInputBorder(),
                ),
              ),
              if (offers.isNotEmpty) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  hint: Text(l10n.selectOffer),
                  items: [
                    for (final offer in offers)
                      DropdownMenuItem(
                        value: offer.code,
                        child: Text('${offer.code} — ${offer.label}'),
                      ),
                  ],
                  onChanged: (code) async {
                    if (code == null) return;
                    coupon.text = code;
                    final sheetMessenger = ScaffoldMessenger.of(sheetContext);
                    try {
                      final quote = await repo.couponCheck(code, service.id);
                      setState(() {
                        quotedFinal = quote.finalPaise;
                        appliedCoupon = code;
                      });
                    } catch (e) {
                      setState(() {
                        quotedFinal = null;
                        appliedCoupon = null;
                      });
                      sheetMessenger.showSnackBar(
                          SnackBar(content: Text(apiErrorMessage(e))));
                    }
                  },
                  decoration: InputDecoration(
                    labelText: l10n.selectOffer,
                    prefixIcon: const Icon(Icons.local_offer_outlined),
                    border: const OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: coupon,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: l10n.couponLabel,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () async {
                      final code = coupon.text.trim();
                      if (code.isEmpty) return;
                      final sheetMessenger =
                          ScaffoldMessenger.of(sheetContext);
                      try {
                        final quote =
                            await repo.couponCheck(code, service.id);
                        setState(() {
                          quotedFinal = quote.finalPaise;
                          appliedCoupon = code.toUpperCase();
                        });
                      } catch (e) {
                        setState(() {
                          quotedFinal = null;
                          appliedCoupon = null;
                        });
                        sheetMessenger.showSnackBar(
                            SnackBar(content: Text(apiErrorMessage(e))));
                      }
                    },
                    child: Text(l10n.applyCoupon),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: Icon(
                  lat == null ? Icons.my_location : Icons.check_circle,
                  size: 18,
                  color: lat == null ? null : Colors.green,
                ),
                label: Text(
                    lat == null ? l10n.attachLocation : l10n.locationAttached),
                onPressed: () async {
                  final sheetMessenger = ScaffoldMessenger.of(sheetContext);
                  try {
                    var permission = await Geolocator.checkPermission();
                    if (permission == LocationPermission.denied) {
                      permission = await Geolocator.requestPermission();
                    }
                    if (permission == LocationPermission.denied ||
                        permission == LocationPermission.deniedForever) {
                      sheetMessenger.showSnackBar(
                          SnackBar(content: Text(l10n.locationFailed)));
                      return;
                    }
                    final position = await Geolocator.getCurrentPosition(
                      locationSettings: const LocationSettings(
                        accuracy: LocationAccuracy.high,
                        timeLimit: Duration(seconds: 15),
                      ),
                    );
                    setState(() {
                      lat = position.latitude;
                      lng = position.longitude;
                    });
                  } catch (_) {
                    sheetMessenger.showSnackBar(
                        SnackBar(content: Text(l10n.locationFailed)));
                  }
                },
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48)),
                onPressed: () {
                  if (address.text.trim().length < 5) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                        SnackBar(content: Text(l10n.addressInvalid)));
                    return;
                  }
                  Navigator.of(sheetContext).pop(true);
                },
                child: Text(l10n.confirmBooking),
              ),
            ],
          ),
        ),
      ),
    );

    if (booked != true) return;
    try {
      await repo.create(
        serviceId: service.id,
        address: address.text.trim(),
        note: note.text.trim(),
        lat: lat,
        lng: lng,
        couponCode: appliedCoupon,
      );
      messenger.showSnackBar(SnackBar(content: Text(l10n.bookingCreated)));
      ref.invalidate(myBookingsProvider);
      ref.read(currentTabProvider.notifier).state = 1; // Bookings tab
      router.go('/');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}
