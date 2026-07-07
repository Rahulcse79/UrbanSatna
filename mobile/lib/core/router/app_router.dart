import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/admin_logs_screen.dart';
import '../../features/admin/presentation/admin_panel_screen.dart';
import '../../features/admin/presentation/admin_tickets_screen.dart';
import '../../features/admin/presentation/admin_users_screen.dart';
import '../../features/admin/presentation/catalog_manager_screen.dart';
import '../../features/admin/presentation/coupons_screen.dart';
import '../../features/admin/presentation/worker_approvals_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/jobs/presentation/earnings_screen.dart';
import '../../features/support/presentation/my_tickets_screen.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/catalog/presentation/services_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/shell/main_shell.dart';
import '../auth/auth_controller.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final loggedIn = ref.watch(authControllerProvider) != null;
  return GoRouter(
    initialLocation: loggedIn ? '/' : '/splash',
    redirect: (context, state) {
      final path = state.uri.path;
      final public =
          path == '/splash' || path == '/login' || path == '/settings';
      if (!loggedIn && !public) return '/splash';
      if (loggedIn && (path == '/splash' || path == '/login')) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/',
        builder: (context, state) => const MainShell(),
      ),
      GoRoute(
        path: '/category/:id',
        builder: (context, state) => ServicesScreen(
          categoryId: state.pathParameters['id']!,
          categoryName: state.uri.queryParameters['name'] ?? '',
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/admin',
        builder: (context, state) => const AdminPanelScreen(),
      ),
      GoRoute(
        path: '/admin/approvals',
        builder: (context, state) => const WorkerApprovalsScreen(),
      ),
      GoRoute(
        path: '/admin/catalog',
        builder: (context, state) => const CatalogManagerScreen(),
      ),
      GoRoute(
        path: '/admin/tickets',
        builder: (context, state) => const AdminTicketsScreen(),
      ),
      GoRoute(
        path: '/admin/coupons',
        builder: (context, state) => const CouponsScreen(),
      ),
      GoRoute(
        path: '/admin/users',
        builder: (context, state) => const AdminUsersScreen(),
      ),
      GoRoute(
        path: '/admin/logs',
        builder: (context, state) => const AdminLogsScreen(),
      ),
      GoRoute(
        path: '/earnings',
        builder: (context, state) => const EarningsScreen(),
      ),
      GoRoute(
        path: '/tickets',
        builder: (context, state) => const MyTicketsScreen(),
      ),
      GoRoute(
        path: '/chat/:bookingId',
        builder: (context, state) => ChatScreen(
          bookingId: state.pathParameters['bookingId']!,
          title: state.uri.queryParameters['title'] ?? 'Chat',
        ),
      ),
    ],
  );
});
