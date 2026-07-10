import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/widgets/page_bar.dart';
import '../../../l10n/gen/app_localizations.dart';
import '../../bookings/presentation/bookings_screen.dart' show formatTime;

class AdminCoupon {
  const AdminCoupon({
    required this.id,
    required this.code,
    required this.isActive,
    required this.createdAt,
    this.percentOff,
    this.flatOffPaise,
  });

  factory AdminCoupon.fromJson(Map<String, dynamic> json) => AdminCoupon(
        id: json['id'] as String,
        code: json['code'] as String,
        isActive: json['is_active'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        percentOff: json['percent_off'] as int?,
        flatOffPaise: json['flat_off_paise'] as int?,
      );

  final String id;
  final String code;
  final bool isActive;
  final DateTime createdAt;
  final int? percentOff;
  final int? flatOffPaise;

  /// Legacy percent coupons still render; new ones are always flat ₹.
  String get valueLabel => percentOff != null
      ? '$percentOff% off'
      : '₹${((flatOffPaise ?? 0) / 100).toStringAsFixed(0)} off';
}

typedef CouponsPage = ({List<AdminCoupon> items, int total, int page});

/// Admin coupons keyed by page — server paginates 10/page.
final adminCouponsProvider =
    FutureProvider.autoDispose.family<CouponsPage, int>((ref, page) async {
  final dio = ref.watch(dioProvider);
  final res = await dio
      .get<Map<String, dynamic>>('/api/v1/admin/coupons?page=$page');
  final data = unwrapEnvelope(res) as Map<String, dynamic>;
  return (
    items: (data['items'] as List<dynamic>)
        .map((c) => AdminCoupon.fromJson(c as Map<String, dynamic>))
        .toList(),
    total: data['total'] as int,
    page: data['page'] as int,
  );
});

/// Admin coupon manager. One redemption per user is enforced by the
/// backend forever — deactivating and reactivating never resets usage.
class CouponsScreen extends ConsumerStatefulWidget {
  const CouponsScreen({super.key});

  @override
  ConsumerState<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends ConsumerState<CouponsScreen> {
  int _page = 1;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final coupons = ref.watch(adminCouponsProvider(_page));
    return Scaffold(
      appBar: AppBar(title: Text(l10n.couponsAdmin)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(l10n.addCoupon),
        onPressed: _addCoupon,
      ),
      body: Column(
        children: [
          Expanded(
            child: coupons.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(apiErrorMessage(e))),
              data: (page) => RefreshIndicator(
                onRefresh: () async => ref.invalidate(adminCouponsProvider),
                child: page.items.isEmpty
                    ? ListView(children: [
                        const SizedBox(height: 120),
                        Icon(Icons.local_offer_outlined,
                            size: 56,
                            color: Theme.of(context).colorScheme.outline),
                        const SizedBox(height: 12),
                        Center(child: Text(l10n.noCoupons)),
                      ])
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                        itemCount: page.items.length,
                        itemBuilder: (context, i) => _CouponCard(
                          coupon: page.items[i],
                          onChanged: () =>
                              ref.invalidate(adminCouponsProvider),
                        ),
                      ),
              ),
            ),
          ),
          SafeArea(
            child: coupons.maybeWhen(
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

  /// Add coupon: fixed ₹ discount only — percent coupons are no longer
  /// offered (existing ones keep working and rendering).
  Future<void> _addCoupon() async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final scheme = Theme.of(context).colorScheme;
    final code = TextEditingController();
    final amount = TextEditingController();
    final submitted = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.local_offer, color: scheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(l10n.addCoupon)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: code,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.couponLabel,
                prefixIcon: const Icon(Icons.confirmation_number_outlined),
                helperText: l10n.oncePerUser,
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: amount,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.priceRupeesLabel,
                prefixIcon: const Icon(Icons.currency_rupee),
                filled: true,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.check, size: 18),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            label: Text(l10n.save),
          ),
        ],
      ),
    );
    if (submitted != true) return;
    final rupees = int.tryParse(amount.text.trim());
    if (code.text.trim().length < 3 || rupees == null || rupees <= 0) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.invalidNumber)));
      return;
    }
    try {
      await ref.read(dioProvider).post<Map<String, dynamic>>(
        '/api/v1/admin/coupons',
        data: {
          'code': code.text.trim().toUpperCase(),
          'flat_off_paise': rupees * 100,
        },
      );
      ref.invalidate(adminCouponsProvider);
    } on DioException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
    }
  }
}

/// A coupon as a card: offer tile, dashed-feel code, discount + status
/// badges, created date, and the activate toggle.
class _CouponCard extends ConsumerWidget {
  const _CouponCard({required this.coupon, required this.onChanged});

  final AdminCoupon coupon;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final accent = coupon.isActive ? scheme.primary : scheme.outline;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.local_offer, color: accent),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coupon.code,
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    decoration:
                        coupon.isActive ? null : TextDecoration.lineThrough,
                    color: coupon.isActive ? null : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(coupon.valueLabel,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: accent)),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 3),
                      decoration: BoxDecoration(
                        color: (coupon.isActive
                                ? Colors.green.shade600
                                : scheme.outline)
                            .withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        coupon.isActive
                            ? l10n.activeLabel
                            : l10n.inactiveLabel,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: coupon.isActive
                                ? Colors.green.shade600
                                : scheme.outline),
                      ),
                    ),
                    Text(formatTime(coupon.createdAt),
                        style: text.labelSmall
                            ?.copyWith(color: scheme.outline)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(l10n.oncePerUser,
                    style: text.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          Switch(
            value: coupon.isActive,
            onChanged: (v) async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await ref.read(dioProvider).patch<Map<String, dynamic>>(
                  '/api/v1/admin/coupons/${coupon.id}',
                  data: {'is_active': v},
                );
                onChanged();
              } catch (e) {
                messenger
                    .showSnackBar(SnackBar(content: Text(apiErrorMessage(e))));
              }
            },
          ),
        ],
      ),
    );
  }
}
