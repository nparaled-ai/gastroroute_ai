import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/storage/auth_storage.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/select_role_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/auth/screens/reset_password_screen.dart';
import '../features/rider/screens/rider_home_screen.dart';
import '../features/rider/screens/rider_profile_screen.dart';
import '../features/rider/screens/rider_edit_profile_screen.dart';
import '../features/rider/screens/rider_motos_screen.dart';
import '../features/rider/screens/rider_moto_form_screen.dart';
import '../features/rider/screens/route_generator_screen.dart';
import '../features/rider/screens/route_import_screen.dart';
import '../features/rider/screens/route_result_screen.dart';
import '../features/rider/screens/friends_screen.dart';
import '../features/rider/screens/friends_search_screen.dart';
import '../features/rider/screens/my_routes_screen.dart';
import '../features/rider/screens/route_detail_screen.dart';
import '../features/rider/screens/planner_selection_screen.dart';

final router = GoRouter(
  initialLocation: '/splash',
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
      path: '/forgot-password',
      builder: (context, state) => const ForgotPasswordScreen(),
    ),
    GoRoute(
      path: '/reset-password',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return ResetPasswordScreen(email: extra?['email'] ?? '');
      },
    ),
    GoRoute(
      path: '/register',
      builder: (context, state) => const RegisterScreen(),
    ),
    GoRoute(
      path: '/select-role',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return SelectRoleScreen(
          userId: extra['user_id'],
          roles:  List<String>.from(extra['roles']),
          password: extra['password'],
        );
      },
    ),
    GoRoute(
      path: '/rider/home',
      builder: (context, state) => const RiderHomeScreen(),
    ),
    GoRoute(
      path: '/rider/profile',
      builder: (context, state) => const RiderProfileScreen(),
    ),
    GoRoute(
      path: '/rider/edit-profile',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return RiderEditProfileScreen(profile: extra);
      },
    ),
    GoRoute(
      path: '/rider/motos',
      builder: (context, state) => const RiderMotosScreen(),
    ),
    GoRoute(
      path: '/rider/motos/add',
      builder: (context, state) => const RiderMotoFormScreen(),
    ),
    GoRoute(
      path: '/rider/motos/edit',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return RiderMotoFormScreen(moto: extra);
      },
    ),
    GoRoute(
      path: '/rider/my-routes',
      builder: (context, state) => const MyRoutesScreen(),
    ),
    GoRoute(
      path: '/rider/routes/:id',
      builder: (context, state) {
        final id = int.parse(state.pathParameters['id']!);
        return RouteDetailScreen(routeId: id);
      },
    ),
    GoRoute(
      path: '/rider/friends',
      builder: (context, state) => const FriendsScreen(),
    ),
    GoRoute(
      path: '/rider/friends/search',
      builder: (context, state) => const FriendsSearchScreen(),
    ),
    GoRoute(
      path: '/rider/planner',
      builder: (context, state) => const PlannerSelectionScreen(),
    ),
    GoRoute(
      path: '/rider/route-generator',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>?;
        return RouteGeneratorScreen(initialData: extra);
      },
    ),
    GoRoute(
      path: '/rider/route-import',
      builder: (context, state) => const RouteImportScreen(),
    ),
    GoRoute(
      path: '/rider/route-result',
      builder: (context, state) {
        final extra = state.extra as Map<String, dynamic>;
        return RouteResultScreen(result: extra);
      },
    ),
  ],
  redirect: (context, state) async {
    final isLoggedIn = await AuthStorage.isLoggedIn();
    final isSplash   = state.matchedLocation == '/splash';
    final isAuth     = state.matchedLocation == '/login' ||
                       state.matchedLocation == '/register' ||
                       state.matchedLocation == '/select-role' ||
                       state.matchedLocation == '/forgot-password' ||
                       state.matchedLocation.startsWith('/reset-password');

    if (!isLoggedIn && !isAuth && !isSplash) return '/login';
    return null;
  },
);