import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';

class _Page {
  final String emoji;
  final String title;
  final String sub;
  const _Page(this.emoji, this.title, this.sub);
}

const _pages = [
  _Page('📦', 'Move Anything,\nAnywhere',
      'Bikes to trucks — we have the right vehicle for every load.'),
  _Page('⚡', 'Instant Driver\nMatching',
      'Get matched with nearby verified drivers in seconds.'),
  _Page('📍', 'Live GPS\nTracking',
      'Watch your driver in real-time from pickup to drop-off.'),
  _Page('🤝', 'Fair Fare,\nYour Way',
      'Negotiate directly with drivers. No hidden charges.'),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _ctrl = PageController();
  int _idx = 0;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Stack(children: [
        PageView.builder(
          controller: _ctrl,
          itemCount: _pages.length,
          onPageChanged: (i) => setState(() => _idx = i),
          itemBuilder: (_, i) {
            final p = _pages[i];
            return Padding(
              padding: const EdgeInsets.fromLTRB(28, 80, 28, 200),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(p.emoji,
                      style: const TextStyle(fontSize: 80)),
                  const SizedBox(height: 40),
                  Text(
                    p.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.15,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    p.sub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        // bottom controls
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: Container(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 50),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.background.withOpacity(0),
                  AppColors.background,
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // dots
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    _pages.length,
                    (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: _idx == i ? 24 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _idx == i
                            ? AppColors.primary
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                if (_idx < _pages.length - 1) ...[
                  PrimaryButton(
                    label: 'Next',
                    onTap: () => _ctrl.nextPage(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeInOut,
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => context.go(AppRoutes.login),
                    child: const Text('Skip',
                        style: TextStyle(
                            color: AppColors.textSecondary)),
                  ),
                ] else
                  PrimaryButton(
                    label: "Let's Go →",
                    onTap: () => context.go(AppRoutes.login),
                  ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}
