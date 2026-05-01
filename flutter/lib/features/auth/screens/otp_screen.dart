import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pinput/pinput.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/data/datasources/api_service.dart';
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
  bool _resending = false;
  String? _inlineError;
  int _failedAttempts = 0;
  int _seconds = 30;
  Timer? _timer;
  final _api = ApiService();

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
    setState(() {
      _loading = true;
      _inlineError = null;
    });
    try {
      final credential = await PhoneAuthService.instance.verifyOtp(_otpCtrl.text);
      final idToken = await credential.user?.getIdToken();
      if (idToken == null) {
        throw Exception('Could not verify phone. Please request OTP again.');
      }
      final res = await _api.exchangeFirebaseToken(
        idToken: idToken,
        isDriver: widget.isDriver,
        name: widget.isDriver ? null : widget.name,
        fcmToken: SessionManager.instance.getFcmToken(),
      );
      if (res['success'] != true) {
        throw Exception('OTP verification failed');
      }

      final token = (res['token'] ?? '').toString();
      final userJson = (res['user'] as Map?)?.cast<String, dynamic>() ?? {};
      final user = UserModel.fromJson(userJson);
      await SessionManager.instance.saveSession(token, user);
      if (!mounted) return;
      context.go(
        user.isDriver ? AppRoutes.driverHome : AppRoutes.customerHome,
      );
    } on Exception catch (e) {
      if (!mounted) return;
      var msg = e.toString().replaceFirst('Exception: ', '');
      if (msg.contains('status code of 403') && widget.isDriver) {
        msg = 'Thanks for registering. Your profile is under review. Please wait while our backend team processes your approval.';
      }
      if (msg.contains('status code of 404') && widget.isDriver) {
        msg = 'Driver profile not found yet. Please complete driver registration first.';
      }
      setState(() {
        _failedAttempts += 1;
        _inlineError = msg;
      });
      showSnack(context, msg, error: true);
      _otpCtrl
        ..clear()
        ..selection = const TextSelection.collapsed(offset: 0);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resend() async {
    if (_seconds > 0) return;
    setState(() {
      _resending = true;
      _inlineError = null;
      _failedAttempts = 0;
    });
    try {
      await PhoneAuthService.instance.sendOtp(widget.phone);
      if (!mounted) return;
      showSnack(context, 'OTP resent!');
      _startTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _inlineError = e.toString().replaceFirst('Exception: ', '');
      });
      showSnack(context, _inlineError ?? 'Failed to resend', error: true);
    } finally {
      if (mounted) {
        setState(() => _resending = false);
      }
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
                  onChanged: (_) {
                    if (_inlineError != null) {
                      setState(() => _inlineError = null);
                    }
                  },
                  androidSmsAutofillMethod:
                      AndroidSmsAutofillMethod.smsUserConsentApi,
                  autofocus: true,
                ),
              ),
              if (_inlineError != null) ...[
                const SizedBox(height: 14),
                Text(
                  _inlineError!,
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              if (_failedAttempts > 0) ...[
                const SizedBox(height: 6),
                Text(
                  'Attempt $_failedAttempts failed. Verify the latest OTP and try again.',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
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
                                ? (_resending
                                    ? AppColors.warning
                                    : AppColors.textMuted)
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
