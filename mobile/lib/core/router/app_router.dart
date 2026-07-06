import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/admin/presentation/worker_approvals_screen.dart';
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
        path: '/admin/approvals',
        builder: (context, state) => const WorkerApprovalsScreen(),
      ),
    ],
  );
});
