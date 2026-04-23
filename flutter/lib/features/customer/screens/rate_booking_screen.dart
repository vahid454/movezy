import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/data/datasources/api_service.dart';
import 'package:movezy/services/session_manager.dart';

class RateBookingScreen extends StatefulWidget {
  final String bookingId;
  const RateBookingScreen({super.key, required this.bookingId});

  @override
  State<RateBookingScreen> createState() =>
      _RateBookingScreenState();
}

class _RateBookingScreenState extends State<RateBookingScreen> {
  double _rating = 4;
  String? _quick;
  final _reviewCtrl = TextEditingController();
  bool _loading = false;
  final _api = ApiService();

  static const _quickList = [
    'Great service!',
    'On time',
    'Handled goods carefully',
    'Friendly driver',
    'Would use again',
  ];

  @override
  void initState() {
    super.initState();
    _api.setToken(SessionManager.instance.getToken());
  }

  @override
  void dispose() {
    _reviewCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      final review =
          _quick ?? _reviewCtrl.text.trim();
      await _api.rateBooking(
          widget.bookingId, _rating.round(), review);
      if (!mounted) return;
      showSnack(context, '✅ Thank you for your feedback!');
      context.go(AppRoutes.customerHome);
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Failed to submit rating',
            error: true);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String get _ratingLabel {
    if (_rating >= 5) return 'Excellent! 🌟';
    if (_rating >= 4) return 'Great! 👍';
    if (_rating >= 3) return 'Good 🙂';
    if (_rating >= 2) return 'Below average 😐';
    return 'Poor 😞';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            const SizedBox(height: 40),
            const Text('🎉',
                style: TextStyle(fontSize: 72)),
            const SizedBox(height: 20),
            const Text(
              'Trip Completed!',
              style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'How was your experience?',
              style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),

            // Star rating
            RatingBar.builder(
              initialRating: _rating,
              minRating: 1,
              itemCount: 5,
              itemSize: 48,
              glow: true,
              glowColor: AppColors.primary.withOpacity(0.3),
              itemBuilder: (_, __) => const Icon(
                  Icons.star_rounded,
                  color: AppColors.primary),
              onRatingUpdate: (r) =>
                  setState(() => _rating = r),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Text(
                _ratingLabel,
                key: ValueKey(_rating),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: _rating >= 4
                      ? AppColors.success
                      : _rating >= 3
                          ? AppColors.warning
                          : AppColors.danger,
                ),
              ),
            ),

            const SizedBox(height: 28),

            // Quick review chips
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _quickList
                  .map(
                    (r) => GestureDetector(
                      onTap: () => setState(
                          () => _quick = _quick == r ? null : r),
                      child: AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _quick == r
                              ? AppColors.primaryGlow
                              : AppColors.surface2,
                          borderRadius:
                              BorderRadius.circular(20),
                          border: Border.all(
                            color: _quick == r
                                ? AppColors.primary
                                : AppColors.border,
                          ),
                        ),
                        child: Text(r,
                            style: TextStyle(
                              fontSize: 13,
                              color: _quick == r
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ),
                  )
                  .toList(),
            ),

            const SizedBox(height: 20),

            TextField(
              controller: _reviewCtrl,
              style: const TextStyle(
                  color: AppColors.textPrimary, fontSize: 14),
              maxLines: 3,
              decoration: const InputDecoration(
                hintText:
                    'Write a detailed review (optional)…',
                filled: true,
                fillColor: AppColors.surface2,
              ),
            ),

            const SizedBox(height: 28),
            PrimaryButton(
                label: 'Submit Rating',
                onTap: _submit,
                loading: _loading),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.go(AppRoutes.customerHome),
              child: const Text('Skip for now',
                  style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 14)),
            ),
            const SizedBox(height: 24),
          ]),
        ),
      ),
    );
  }
}
