import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';

class _Page {
  final String emoji;
  final String title;
  final String sub;
  final String chip;
  final IconData chipIcon;
  final Color accent;

  const _Page({
    required this.emoji,
    required this.title,
    required this.sub,
    required this.chip,
    required this.chipIcon,
    required this.accent,
  });
}

const _pages = [
  _Page(
    emoji: '📦',
    title: 'Move Anything,\nAnywhere',
    sub: 'Bikes to trucks — the right vehicle for every load.',
    chip: 'Verified fleet · city-wide coverage',
    chipIcon: Icons.verified_outlined,
    accent: AppColors.primary,
  ),
  _Page(
    emoji: '⚡',
    title: 'Instant Driver\nMatching',
    sub: 'Nearby approved drivers get your request in real time.',
    chip: 'Live demand map · sub-minute matching',
    chipIcon: Icons.bolt_rounded,
    accent: Color(0xFFF59E0B),
  ),
  _Page(
    emoji: '📍',
    title: 'Live GPS\nTracking',
    sub: 'Follow pickup → drop-off with a clear route on the map.',
    chip: 'Turn-by-turn route · ETA you can trust',
    chipIcon: Icons.route_rounded,
    accent: Color(0xFF3B82F6),
  ),
  _Page(
    emoji: '🤝',
    title: 'Fair Fare,\nYour Way',
    sub: 'Transparent estimates before you book. Confirm with your driver.',
    chip: 'No surprise platform fees on small goods',
    chipIcon: Icons.payments_outlined,
    accent: Color(0xFF22C55E),
  ),
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
        Positioned(
          top: -120,
          left: -80,
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primaryGlow.withValues(alpha: 0.35),
            ),
          ),
        ),
        Positioned(
          bottom: 180,
          right: -80,
          child: Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.infoBg.withValues(alpha: 0.45),
            ),
          ),
        ),
        PageView.builder(
          controller: _ctrl,
          itemCount: _pages.length,
          onPageChanged: (i) => setState(() => _idx = i),
          itemBuilder: (_, i) {
            final p = _pages[i];
            return Padding(
              padding: const EdgeInsets.fromLTRB(28, 72, 28, 200),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 118,
                    height: 118,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          p.accent.withValues(alpha: 0.22),
                          AppColors.surface2,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(32),
                      border: Border.all(
                        color: p.accent.withValues(alpha: 0.45),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: p.accent.withValues(alpha: 0.18),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ],
                    ),
                    child: Center(
                        child: Text(p.emoji, style: const TextStyle(fontSize: 56))),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    p.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                      height: 1.12,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    p.sub,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      color: AppColors.textSecondary,
                      height: 1.55,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: p.accent.withValues(alpha: 0.28)),
                    ),
                    child: Row(
                      children: [
                        Icon(p.chipIcon, color: p.accent, size: 22),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            p.chip,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                              height: 1.35,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),

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
                  AppColors.background.withValues(alpha: 0),
                  AppColors.background,
                ],
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                            ? _pages[_idx].accent
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
