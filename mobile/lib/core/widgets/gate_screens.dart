import 'package:flutter/material.dart';

import '../../l10n/gen/app_localizations.dart';

/// Full-screen gate shown while `maintenance_mode` is on (admins bypass).
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Gate(
      icon: Icons.engineering,
      title: l10n.maintenanceTitle,
      body: l10n.maintenanceBody,
    );
  }
}

/// Full-screen gate shown when the installed build is older than the
/// admin-set `min_build`.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return _Gate(
      icon: Icons.system_update,
      title: l10n.forceUpdateTitle,
      body: l10n.forceUpdateBody,
    );
  }
}

class _Gate extends StatelessWidget {
  const _Gate({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon,
                  size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}
