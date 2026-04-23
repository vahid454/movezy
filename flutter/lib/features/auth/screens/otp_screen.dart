import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/data/models/models.dart';
import 'package:movezy/services/phone_auth_service.dart';
import 'package:movezy/services/session_manager.dart';

class OtpScreen extends StatefulWidget {
  final String phone;
  final String? name;
  final bool isDriver;

  const OtpScreen({
    super.key,
    required this.phone,
    this.name,
    required this.isDriver,
  });

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _otpCtrl = TextEditingController();
  bool _loading = false;
  int _seconds = 30;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    setState(() => _seconds = 30);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_seconds == 0) {
        t.cancel();
        return;
      }
      if (mounted) setState(() => _seconds--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _otpCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_otpCtrl.text.length != 6) return;
    setState(() => _loading = true);
    try {
      final res = await PhoneAuthService.instance.verifyOtp(
        _otpCtrl.text,
      );
      final firebaseUser = res.user;
      if (firebaseUser == null) {
        throw FirebaseAuthException(
          code: 'missing-user',
          message: 'Phone verification completed without a user session.',
        );
      }

      final token = await firebaseUser.getIdToken();
      final user = UserModel(
        id: firebaseUser.uid,
        name: (widget.name?.trim().isNotEmpty ?? false)
            ? widget.name!.trim()
            : (widget.isDriver ? 'Driver' : widget.phone),
        phone: widget.phone,
        role: widget.isDriver ? 'driver' : 'customer',
      );
      await SessionManager.instance.saveSession(token ?? '', user);
      if (!mounted) return;
      context.go(
        user.isDriver ? AppRoutes.driverHome : AppRoutes.customerHome,
      );
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      final msg = e.message ?? 'Verification failed';
      showSnack(context, msg, error: true);
      _otpCtrl.clear();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_seconds > 0) return;
    try {
      await PhoneAuthService.instance.sendOtp(widget.phone);
      if (!mounted) return;
      showSnack(context, 'OTP resent!');
      _startTimer();
    } catch (_) {
      if (!mounted) return;
      showSnack(context, 'Failed to resend', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pinTheme = PinTheme(
      width: 54,
      height: 60,
      textStyle: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              size: 18, color: AppColors.textPrimary),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                'Verify OTP 🔐',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '6-digit code sent to ${widget.phone}',
                style: const TextStyle(
                    fontSize: 15, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 48),
              Center(
                child: Pinput(
                  length: 6,
                  controller: _otpCtrl,
                  defaultPinTheme: pinTheme,
                  focusedPinTheme: pinTheme.copyWith(
                    decoration: pinTheme.decoration!.copyWith(
                      border: Border.all(color: AppColors.primary, width: 2),
                    ),
                  ),
                  submittedPinTheme: pinTheme.copyWith(
                    decoration: pinTheme.decoration!.copyWith(
                      color: AppColors.primaryGlow,
                      border: Border.all(color: AppColors.primary),
                    ),
                  ),
                  onCompleted: (_) => _verify(),
                  autofocus: true,
                ),
              ),
              const SizedBox(height: 40),
              PrimaryButton(
                  label: 'Verify & Continue',
                  onTap: _verify,
                  loading: _loading),
              const SizedBox(height: 24),
              Center(
                child: GestureDetector(
                  onTap: _resend,
                  child: RichText(
                    text: TextSpan(
                      text: "Didn't receive it? ",
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 14),
                      children: [
                        TextSpan(
                          text: _seconds > 0
                              ? 'Resend in ${_seconds}s'
                              : 'Resend OTP',
                          style: TextStyle(
                            color: _seconds > 0
                                ? AppColors.textMuted
                                : AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
