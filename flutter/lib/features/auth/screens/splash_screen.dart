import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/services/session_manager.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashSlide {
  final String emoji;
  final String headline;
  final String line;
  final List<Color> gradient;

  const _SplashSlide({
    required this.emoji,
    required this.headline,
    required this.line,
    required this.gradient,
  });
}

const _kSlides = [
  _SplashSlide(
    emoji: '📦',
    headline: 'Load',
    line: 'Parcels, cartons, and home goods',
    gradient: [Color(0xFF1E3A5F), Color(0xFF0F172A)],
  ),
  _SplashSlide(
    emoji: '🚚',
    headline: 'Move',
    line: 'Tempos & trucks when you need scale',
    gradient: [Color(0xFF422006), Color(0xFF1C1917)],
  ),
  _SplashSlide(
    emoji: '🏠',
    headline: 'Deliver',
    line: 'Door-to-door, city-wide',
    gradient: [Color(0xFF14532D), Color(0xFF0F172A)],
  ),
];

class _SplashScreenState extends State<SplashScreen> {
  final PageController _pageController = PageController();
  Timer? _carouselTimer;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _carouselTimer = Timer.periodic(const Duration(milliseconds: 2200), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final current = _pageController.page?.round() ?? _pageIndex;
      final next = (current + 1) % _kSlides.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
    });
    _navigate();
  }

  Future<void> _navigate() async {
    await Future.delayed(const Duration(milliseconds: 2400));
    if (!mounted) return;
    final session = SessionManager.instance;
    if (!session.isLoggedIn()) {
      context.go(AppRoutes.onboarding);
      return;
    }
    context.go(
      session.role == 'driver' ? AppRoutes.driverHome : AppRoutes.customerHome,
    );
  }

  @override
  void dispose() {
    _carouselTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          PageView.builder(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(),
            onPageChanged: (i) => setState(() => _pageIndex = i),
            itemCount: _kSlides.length,
            itemBuilder: (context, i) {
              final s = _kSlides[i];
              return DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: s.gradient,
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Text(
                          s.emoji,
                          style: const TextStyle(fontSize: 88, height: 1),
                        ),
                        const Spacer(),
                        Text(
                          s.headline,
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: -0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          s.line,
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.45,
                            color: Colors.white.withValues(alpha: 0.88),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 36),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 36,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(_kSlides.length, (i) {
                    final active = i == _pageIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 22 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active
                            ? AppColors.primary
                            : Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 20),
                const Text(
                  'MOVEZY',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                    letterSpacing: 8,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
