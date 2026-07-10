import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

/// Reusable Prev / "page / lastPage" / Next control for server-paginated
/// lists (10 rows per page across the app).
class PageBar extends StatelessWidget {
  const PageBar({
    super.key,
    required this.page,
    required this.total,
    required this.onPrev,
    required this.onNext,
    this.perPage = 10,
  });

  final int page;
  final int total;
  final int perPage;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final lastPage = (total / perPage).ceil().clamp(1, 99999);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.chevron_left, size: 18),
            label: Text(l10n.prevLabel),
            onPressed: page > 1 ? onPrev : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('$page / $lastPage',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
          OutlinedButton.icon(
            icon: const Icon(Icons.chevron_right, size: 18),
            label: Text(l10n.nextLabel),
            onPressed: page < lastPage ? onNext : null,
          ),
        ],
      ),
    );
  }
}
