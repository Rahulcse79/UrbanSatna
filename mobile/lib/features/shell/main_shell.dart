import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/widgets/bot_avatar.dart';
import '../../l10n/gen/app_localizations.dart';
import '../bookings/presentation/bookings_screen.dart';
import '../home/presentation/home_screen.dart';
import '../jobs/presentation/jobs_screen.dart';
import '../profile/presentation/complete_profile_screen.dart';
import '../profile/presentation/profile_screen.dart';
import 'current_tab.dart';

/// Bottom-navigation shell: Home · Bookings · Jobs (workers) · Profile.
/// First login is gated: name/address/T&C must be completed before the
/// tabs unlock (PRODUCT.md — real-world onboarding).
class MainShell extends ConsumerWidget {
  const MainShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final isWorker =
        ref.watch(authControllerProvider.select((t) => t?.isWorker ?? false));
    // Admins answer support from the inbox — chatting with themselves via
    // the bubble is pointless, so they don't get one.
    final isAdmin =
        ref.watch(authControllerProvider.select((t) => t?.isAdmin ?? false));
    final incomplete = ref.watch(meProvider).maybeWhen(
        data: (me) =>
            (me['full_name'] as String?)?.trim().isEmpty != false ||
            (me['city'] as String?)?.trim().isEmpty != false ||
            me['terms_accepted'] != true,
        orElse: () => false); // fail-open while loading/offline
    if (incomplete) return const CompleteProfileScreen();
    final pages = [
      const HomeScreen(),
      const BookingsScreen(),
      if (isWorker) const JobsScreen(),
      const ProfileScreen(),
    ];
    final tab =
        ref.watch(currentTabProvider).clamp(0, pages.length - 1);

    return Scaffold(
      body: LayoutBuilder(builder: (context, constraints) {
        return Stack(
          children: [
            IndexedStack(index: tab, children: pages),
            // Chatbot launcher: draggable bubble, customers/workers only.
            if (!isAdmin)
              _DraggableChatBubble(
                bounds: constraints.biggest,
                label: l10n.liveChat,
              ),
          ],
        );
      }),
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

/// The chatbot bubble: starts bottom-right, drag it anywhere; the spot is
/// remembered across app launches and clamped back on-screen when the
/// screen size changes.
class _DraggableChatBubble extends StatefulWidget {
  const _DraggableChatBubble({required this.bounds, required this.label});

  final Size bounds;
  final String label;

  @override
  State<_DraggableChatBubble> createState() => _DraggableChatBubbleState();
}

class _DraggableChatBubbleState extends State<_DraggableChatBubble> {
  static const _size = 58.0; // BotAvatar 52 + bubble padding
  static const _margin = 8.0;
  static const _dxKey = 'chat_bubble_dx';
  static const _dyKey = 'chat_bubble_dy';

  Offset? _pos; // null until restored or first dragged → default spot

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final dx = prefs.getDouble(_dxKey);
    final dy = prefs.getDouble(_dyKey);
    if (mounted && dx != null && dy != null) {
      setState(() => _pos = Offset(dx, dy));
    }
  }

  Future<void> _save(Offset pos) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_dxKey, pos.dx);
    await prefs.setDouble(_dyKey, pos.dy);
  }

  Offset _clamp(Offset raw) {
    final topInset = MediaQuery.of(context).padding.top;
    return Offset(
      raw.dx.clamp(_margin, widget.bounds.width - _size - _margin),
      raw.dy.clamp(topInset + _margin, widget.bounds.height - _size - _margin),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pos = _clamp(_pos ??
        Offset(
          widget.bounds.width - _size - 16,
          widget.bounds.height - _size - 16,
        ));
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() => _pos = _clamp(pos + d.delta)),
        onPanEnd: (_) => _save(_pos ?? pos),
        child: _SupportChatButton(label: widget.label),
      ),
    );
  }
}

/// Floating live-chat launcher wearing the bot mascot.
class _SupportChatButton extends StatelessWidget {
  const _SupportChatButton({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        elevation: 6,
        shadowColor: Colors.black45,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/support-chat'),
          child: const Padding(
            padding: EdgeInsets.all(3),
            child: BotAvatar(size: 52),
          ),
        ),
      ),
    );
  }
}
