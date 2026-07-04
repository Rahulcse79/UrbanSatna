import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/auth_controller.dart';
import '../../l10n/gen/app_localizations.dart';
import '../bookings/presentation/bookings_screen.dart';
import '../home/presentation/home_screen.dart';
import '../jobs/presentation/jobs_screen.dart';
import '../profile/presentation/profile_screen.dart';
import 'current_tab.dart';

/// Bottom-navigation shell: Home · Bookings · Jobs (workers) · Profile.
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isWorker =
        ref.watch(authControllerProvider.select((t) => t?.isWorker ?? false));
    final pages = [
      const HomeScreen(),
      const BookingsScreen(),
      if (isWorker) const JobsScreen(),
      const ProfileScreen(),
    ];
    final tab =
        ref.watch(currentTabProvider).clamp(0, pages.length - 1);

    return Scaffold(
      body: IndexedStack(index: tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) =>
            ref.read(currentTabProvider.notifier).state = i,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: l10n.navBookings,
          ),
          if (isWorker)
            NavigationDestination(
              icon: const Icon(Icons.work_outline),
              selectedIcon: const Icon(Icons.work),
              label: l10n.navJobs,
            ),
          NavigationDestination(
            icon: const Icon(Icons.person_outline),
            selectedIcon: const Icon(Icons.person),
            label: l10n.navProfile,
          ),
        ],
      ),
    );
  }
}
