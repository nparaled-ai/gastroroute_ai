import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../core/storage/auth_storage.dart';
import '../features/auth/screens/splash_screen.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/register_screen.dart';
import '../features/auth/screens/select_role_screen.dart';
import '../features/rider/screens/rider_home_screen.dart';
import '../features/rider/screens/rider_profile_screen.dart';
import '../features/rider/screens/rider_edit_profile_screen.dart';
import '../features/rider/screens/rider_motos_screen.dart';
import '../features/rider/screens/rider_moto_form_screen.dart';

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
  ],
  redirect: (context, state) async {
    final isLoggedIn = await AuthStorage.isLoggedIn();
    final isSplash   = state.matchedLocation == '/splash';
    final isAuth     = state.matchedLocation == '/login' ||
                       state.matchedLocation == '/register' ||
                       state.matchedLocation == '/select-role';

    if (!isLoggedIn && !isAuth && !isSplash) return '/login';
    return null;
  },
);