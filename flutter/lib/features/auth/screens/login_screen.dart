import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/data/datasources/api_service.dart';
import 'package:movezy/data/models/models.dart';
import 'package:movezy/services/phone_auth_service.dart';
import 'package:movezy/services/session_manager.dart';

enum _Mode { customer, driver }

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  _Mode _mode = _Mode.customer;
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  final _api = ApiService();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;
    final phone = '+91${_phoneCtrl.text.trim()}';
    setState(() => _loading = true);
    try {
      final start = await PhoneAuthService.instance.sendOtp(phone);
      if (!mounted) return;
      if (!start.requiresCode && start.credential != null) {
        final idToken = await start.credential!.user?.getIdToken();
        if (idToken == null) {
          throw Exception('Could not verify phone. Please try again.');
        }
        final res = await _api.exchangeFirebaseToken(
          idToken: idToken,
          isDriver: _mode == _Mode.driver,
          name: _mode == _Mode.customer ? _nameCtrl.text.trim() : null,
          fcmToken: SessionManager.instance.getFcmToken(),
        );
        final token = (res['token'] ?? '').toString();
        final userJson = (res['user'] as Map?)?.cast<String, dynamic>() ?? {};
        if (token.isEmpty || userJson.isEmpty) {
          throw Exception('Login failed. Please try again.');
        }
        final user = UserModel.fromJson(userJson);
        await SessionManager.instance.saveSession(token, user);
        if (!mounted) return;
        context.go(user.isDriver ? AppRoutes.driverHome : AppRoutes.customerHome);
        return;
      }
      context.push(AppRoutes.otpVerify, extra: {
        'phone': phone,
        'name': _mode == _Mode.customer ? _nameCtrl.text.trim() : null,
        'isDriver': _mode == _Mode.driver,
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst('Exception: ', '');
      showSnack(context, msg, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 32),
                // Logo
                Row(children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.primaryGlow,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Center(
                        child: Text('⚡', style: TextStyle(fontSize: 22))),
                  ),
                  const SizedBox(width: 12),
                  const Text('Movezy',
                      style: TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                ]),
                const SizedBox(height: 44),
                const Text('Welcome back 👋',
                    style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5)),
                const SizedBox(height: 6),
                const Text('Sign in to continue',
                    style: TextStyle(
                        fontSize: 15, color: AppColors.textSecondary)),
                const SizedBox(height: 32),

                // Mode toggle
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(4),
                  child: Row(children: [
                    _Tab(
                      label: '👤  Customer',
                      selected: _mode == _Mode.customer,
                      onTap: () => setState(() => _mode = _Mode.customer),
                    ),
                    _Tab(
                      label: '🚗  Driver',
                      selected: _mode == _Mode.driver,
                      onTap: () => setState(() => _mode = _Mode.driver),
                    ),
                  ]),
                ),
                const SizedBox(height: 24),

                if (_mode == _Mode.customer) ...[
                  TextFormField(
                    controller: _nameCtrl,
                    style: const TextStyle(color: AppColors.textPrimary),
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person_outline,
                          color: AppColors.textSecondary),
                    ),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Name is required' : null,
                  ),
                  const SizedBox(height: 14),
                ],

                TextFormField(
                  controller: _phoneCtrl,
                  style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(10),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Phone Number',
                    prefixText: '+91  ',
                    prefixStyle:
                        TextStyle(color: AppColors.textSecondary, fontSize: 16),
                    prefixIcon: Icon(Icons.phone_outlined,
                        color: AppColors.textSecondary),
                  ),
                  validator: (v) => (v?.trim().length ?? 0) < 10
                      ? 'Enter a valid 10-digit number'
                      : null,
                ),
                const SizedBox(height: 28),

                PrimaryButton(
                    label: 'Send OTP →', onTap: _sendOtp, loading: _loading),

                const SizedBox(height: 24),

                if (_mode == _Mode.customer)
                  Center(
                    child: GestureDetector(
                      onTap: () => context.push(AppRoutes.driverRegister),
                      child: RichText(
                        text: const TextSpan(
                          text: 'Own a vehicle? ',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 14),
                          children: [
                            TextSpan(
                              text: 'Register as Driver →',
                              style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w700),
                            )
                          ],
                        ),
                      ),
                    ),
                  ),
                if (_mode == _Mode.driver) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Driver access is enabled only after registration on this phone.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Tab(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}
