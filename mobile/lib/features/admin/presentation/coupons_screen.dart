import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../l10n/gen/app_localizations.dart';

class AdminCoupon {
  const AdminCoupon({
    required this.id,
    required this.code,
    required this.isActive,
    this.percentOff,
    this.flatOffPaise,
  });

  factory AdminCoupon.fromJson(Map<String, dynamic> json) => AdminCoupon(
        id: json['id'] as String,
        code: json['code'] as String,
        isActive: json['is_active'] as bool,
        percentOff: json['percent_off'] as int?,
        flatOffPaise: json['flat_off_paise'] as int?,
      );

  final String id;
  final String code;
  final bool isActive;
  final int? percentOff;
  final int? flatOffPaise;

  String get valueLabel => percentOff != null
      ? '$percentOff% off'
      : '₹${((flatOffPaise ?? 0) / 100).toStringAsFixed(0)} off';
}

final adminCouponsProvider =
    FutureProvider.autoDispose<List<AdminCoupon>>((ref) async {
  final dio = ref.watch(dioProvider);
  final res = await dio.get<Map<String, dynamic>>('/api/v1/admin/coupons');
  return (unwrapEnvelope(res) as List<dynamic>)
      .map((c) => AdminCoupon.fromJson(c as Map<String, dynamic>))
      .toList();
});

/// Admin coupon manager. One redemption per user is enforced by the
/// backend forever — deactivating and reactivating never resets usage.
class CouponsScreen extends ConsumerWidget {
  const CouponsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final coupons = ref.watch(adminCouponsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.couponsAdmin)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l10n.addCoupon),
        onPressed: () => _addCoupon(context, ref),
      ),
      body: coupons.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(apiErrorMessage(e))),
        data: (items) => RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminCouponsProvider),
          child: items.isEmpty
              ? ListView(children: [
                  const SizedBox(height: 120),
                  Center(child: Text(l10n.noCoupons)),
                ])
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: items.length,
                  itemBuilder: (context, i) {
                    final coupon = items[i];
                    return SwitchListTile(
                      secondary: const Icon(Icons.local_offer),
                      title: Text(coupon.code,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${coupon.valueLabel} · ${l10n.oncePerUser}'),
                      value: coupon.isActive,
                      onChanged: (v) async {
                        final messenger = ScaffoldMessenger.of(context);
                        try {
                          await ref
                              .read(dioProvider)
                              .patch<Map<String, dynamic>>(
                            '/api/v1/admin/coupons/${coupon.id}',
                            data: {'is_active': v},
                          );
                          ref.invalidate(adminCouponsProvider);
                        } catch (e) {
                          messenger.showSnackBar(SnackBar(
                              content: Text(apiErrorMessage(e))));
                        }
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _addCoupon(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final code = TextEditingController();
    final value = TextEditingController();
    var isPercent = true;
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setState) => AlertDialog(
          title: Text(l10n.addCoupon),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: l10n.couponLabel,
                  filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: true, label: Text('%')),
                  ButtonSegment(value: false, label: Text('₹')),
                ],
                selected: {isPercent},
                onSelectionChanged: (selection) =>
                    setState(() => isPercent = selection.first),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: value,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: isPercent ? '% (1-90)' : l10n.priceRupeesLabel,
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
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
    if (submitted != true) return;
    final amount = int.tryParse(value.text.trim());
    if (code.text.trim().length < 3 || amount == null || amount <= 0) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.invalidNumber)));
      return;
    }
    try {
      await ref.read(dioProvider).post<Map<String, dynamic>>(
        '/api/v1/admin/coupons',
        data: {
          'code': code.text.trim().toUpperCase(),
          if (isPercent) 'percent_off': amount,
          if (!isPercent) 'flat_off_paise': amount * 100,
        },
      );
      ref.invalidate(adminCouponsProvider);
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}
