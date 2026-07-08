import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

/// Previous · "page / pages" · Next — the 10-per-page explore lists.
class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.totalPages,
    required this.onPage,
  });

  final int page;
  final int totalPages;
  final ValueChanged<int> onPage;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            OutlinedButton.icon(
              icon: const Icon(Icons.chevron_left, size: 18),
              label: Text(l10n.previousLabel),
              onPressed: page > 1 ? () => onPage(page - 1) : null,
            ),
            Text('$page / $totalPages',
                style: Theme.of(context).textTheme.labelLarge),
            OutlinedButton.icon(
              icon: const Icon(Icons.chevron_right, size: 18),
              iconAlignment: IconAlignment.end,
              label: Text(l10n.nextLabel),
              onPressed: page < totalPages ? () => onPage(page + 1) : null,
            ),
          ],
        ),
      ),
    );
  }
}
