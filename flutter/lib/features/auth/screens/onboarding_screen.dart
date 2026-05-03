import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/movezy_tempo_mark.dart';
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
    emoji: '🚚',
    title: 'Goods moved\ndoor to door',
    sub: 'Parcels, furniture, appliances — book a bike, auto, or truck for the load you actually have.',
    chip: 'Verified drivers · goods-focused fleet',
    chipIcon: Icons.local_shipping_outlined,
    accent: AppColors.primary,
  ),
  _Page(
    emoji: '🚚',
    title: 'Drivers matched\nin seconds',
    sub: 'Nearby approved drivers see your request instantly and head your way.',
    chip: 'Live map · quick dispatch',
    chipIcon: Icons.local_shipping_rounded,
    accent: Color(0xFFF59E0B),
  ),
  _Page(
    emoji: '🗺️',
    title: 'Watch every\npickup & drop',
    sub: 'Follow your goods from collection to delivery with a live route on the map.',
    chip: 'GPS tracking · clear ETAs',
    chipIcon: Icons.route_rounded,
    accent: Color(0xFF3B82F6),
  ),
  _Page(
    emoji: '💳',
    title: 'Clear fare\nbefore you pay',
    sub: 'See an upfront estimate, then confirm with your driver before the trip starts.',
    chip: 'Transparent pricing · no shocks',
    chipIcon: Icons.payments_outlined,
    accent: Color(0xFF22C55E),
  ),
];

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _ctrl = PageController();
  late final AnimationController _motionCtrl;
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _motionCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _motionCtrl.dispose();
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
        AnimatedBuilder(
          animation: _motionCtrl,
          builder: (context, _) {
            final t = _motionCtrl.value * math.pi * 2;
            return Positioned.fill(
              child: IgnorePointer(
                child: Stack(
                  children: [
                    _FloatingVehicle(
                      icon: Icons.inventory_2_rounded,
                      color: AppColors.success,
                      left: 26 + math.sin(t) * 12,
                      top: 138 + math.cos(t * 0.8) * 10,
                      angle: math.sin(t) * 0.08,
                    ),
                    _FloatingVehicle(
                      icon: Icons.local_shipping_rounded,
                      color: AppColors.primary,
                      right: 28 + math.cos(t * 0.9) * 10,
                      top: 238 + math.sin(t) * 14,
                      angle: -0.08 + math.cos(t) * 0.08,
                    ),
                    _FloatingVehicle(
                      icon: Icons.fire_truck_rounded,
                      color: AppColors.info,
                      left: 34 + math.cos(t * 1.1) * 14,
                      bottom: 250 + math.sin(t * 0.9) * 10,
                      angle: math.cos(t) * 0.06,
                    ),
                  ],
                ),
              ),
            );
          },
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
                  _MovingHeroBadge(
                    animation: _motionCtrl,
                    accent: p.accent,
                    emoji: p.emoji,
                    useTempoBrand: i == 1,
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      border:
                          Border.all(color: p.accent.withValues(alpha: 0.28)),
                    ),
                    child: Row(
                      children: [
                        if (i == 1)
                          MovezyTempoMark(size: 22, truckColor: p.accent)
                        else
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
                        color:
                            _idx == i ? _pages[_idx].accent : AppColors.border,
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
                        style: TextStyle(color: AppColors.textSecondary)),
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

class _MovingHeroBadge extends StatelessWidget {
  final Animation<double> animation;
  final Color accent;
  final String emoji;
  final bool useTempoBrand;

  const _MovingHeroBadge({
    required this.animation,
    required this.accent,
    required this.emoji,
    this.useTempoBrand = false,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value * math.pi * 2;
        return Transform.translate(
          offset: Offset(0, math.sin(t) * 7),
          child: Transform.rotate(
            angle: math.sin(t * 0.7) * 0.035,
            child: child,
          ),
        );
      },
      child: Container(
        width: 132,
        height: 132,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.22),
              AppColors.surface,
            ],
          ),
          borderRadius: BorderRadius.circular(34),
          border: Border.all(
            color: accent.withValues(alpha: 0.45),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.22),
              blurRadius: 34,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 16,
              right: 16,
              bottom: 26,
              child: Container(
                height: 3,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            useTempoBrand
                ? MovezyTempoMark(size: 56, truckColor: accent)
                : Text(emoji, style: const TextStyle(fontSize: 58)),
          ],
        ),
      ),
    );
  }
}

class _FloatingVehicle extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double? left;
  final double? right;
  final double? top;
  final double? bottom;
  final double angle;

  const _FloatingVehicle({
    required this.icon,
    required this.color,
    this.left,
    this.right,
    this.top,
    this.bottom,
    this.angle = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: AppColors.surface.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: color.withValues(alpha: 0.24)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.13),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 24),
        ),
      ),
    );
  }
}
