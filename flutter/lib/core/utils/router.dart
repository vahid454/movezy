import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/services/session_manager.dart';
import 'package:movezy/features/auth/screens/splash_screen.dart';
import 'package:movezy/features/auth/screens/onboarding_screen.dart';
import 'package:movezy/features/auth/screens/login_screen.dart';
import 'package:movezy/features/auth/screens/otp_screen.dart';
import 'package:movezy/features/auth/screens/driver_register_screen.dart';
import 'package:movezy/features/customer/screens/customer_home_screen.dart';
import 'package:movezy/features/customer/screens/booking_screen.dart';
import 'package:movezy/features/customer/screens/booking_history_screen.dart';
import 'package:movezy/features/customer/screens/rate_booking_screen.dart';
import 'package:movezy/features/driver/screens/driver_home_screen.dart';
import 'package:movezy/features/driver/screens/trip_history_screen.dart';
import 'package:movezy/features/driver/screens/driver_pending_screen.dart';
import 'package:movezy/features/driver/screens/driver_profile_screen.dart';

final appRouter = GoRouter(
  initialLocation: AppRoutes.splash,
  redirect: (BuildContext context, GoRouterState state) {
    final isLoggedIn = SessionManager.instance.isLoggedIn();
    final role = SessionManager.instance.role;
    if (state.matchedLocation == AppRoutes.splash) {
      return null;
    }

    final authRoutes = {
      AppRoutes.onboarding,
      AppRoutes.login,
      AppRoutes.otpVerify,
      AppRoutes.driverRegister,
    };
    if (!isLoggedIn && !authRoutes.contains(state.matchedLocation)) {
      return AppRoutes.login;
    }
    if (isLoggedIn &&
        (state.matchedLocation == AppRoutes.login ||
            state.matchedLocation == AppRoutes.onboarding)) {
      return role == 'driver' ? AppRoutes.driverHome : AppRoutes.customerHome;
    }
    return null;
  },
  routes: [
    GoRoute(
      path: AppRoutes.splash,
      builder: (_, __) => const SplashScreen(),
    ),
    GoRoute(
      path: AppRoutes.onboarding,
      builder: (_, __) => const OnboardingScreen(),
    ),
    GoRoute(
      path: AppRoutes.login,
      builder: (_, __) => const LoginScreen(),
    ),
    GoRoute(
      path: AppRoutes.otpVerify,
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return OtpScreen(
          phone: (extra['phone'] ?? '').toString(),
          name: extra['name']?.toString(),
          isDriver: extra['isDriver'] == true,
        );
      },
    ),
    GoRoute(
      path: AppRoutes.driverRegister,
      builder: (_, __) => const DriverRegisterScreen(),
    ),
    GoRoute(
      path: AppRoutes.customerHome,
      builder: (_, __) => const CustomerHomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.booking,
      builder: (_, __) => const BookingScreen(),
    ),
    GoRoute(
      path: AppRoutes.bookingHistory,
      builder: (_, __) => const BookingHistoryScreen(),
    ),
    GoRoute(
      path: AppRoutes.rateBooking,
      builder: (_, state) {
        final extra = state.extra as Map<String, dynamic>? ?? {};
        return RateBookingScreen(
            bookingId: (extra['bookingId'] ?? '').toString());
      },
    ),
    GoRoute(
      path: AppRoutes.driverHome,
      builder: (_, __) => const DriverHomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.tripHistory,
      builder: (_, __) => const TripHistoryScreen(),
    ),
    GoRoute(
      path: AppRoutes.driverPending,
      builder: (_, __) => const DriverPendingScreen(),
    ),
    GoRoute(
      path: AppRoutes.driverProfile,
      builder: (_, __) => const DriverProfileScreen(),
    ),
  ],
  errorBuilder: (_, state) => Scaffold(
    backgroundColor: const Color(0xFF0A0A0A),
    body: Center(
      child: Text(
        'Page not found\n${state.error}',
        style: const TextStyle(color: Colors.white),
        textAlign: TextAlign.center,
      ),
    ),
  ),
);
