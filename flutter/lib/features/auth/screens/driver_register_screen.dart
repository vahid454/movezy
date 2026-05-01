import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/data/datasources/api_service.dart';
import 'package:movezy/services/session_manager.dart';

class DriverRegisterScreen extends StatefulWidget {
  const DriverRegisterScreen({super.key});

  @override
  State<DriverRegisterScreen> createState() => _DriverRegisterScreenState();
}

class _DriverRegisterScreenState extends State<DriverRegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _licCtrl = TextEditingController();
  final _vNumCtrl = TextEditingController();
  final _vModelCtrl = TextEditingController();
  String _vType = 'auto';
  File? _licImg, _rcImg, _insImg, _photoImg;
  bool _loading = false;
  bool _done = false;
  final _api = ApiService();
  final _picker = ImagePicker();

  double get _formProgress {
    var total = 9;
    var done = 0;
    if (_nameCtrl.text.trim().isNotEmpty) done++;
    if (_phoneCtrl.text.trim().length == 10) done++;
    if (_licCtrl.text.trim().isNotEmpty) done++;
    if (_vNumCtrl.text.trim().isNotEmpty) done++;
    if (_vModelCtrl.text.trim().isNotEmpty) done++;
    if (_licImg != null) done++;
    if (_rcImg != null) done++;
    if (_insImg != null) done++;
    if (_photoImg != null) done++;
    return done / total;
  }

  @override
  void initState() {
    super.initState();
    for (final controller in [
      _nameCtrl,
      _phoneCtrl,
      _licCtrl,
      _vNumCtrl,
      _vModelCtrl,
    ]) {
      controller.addListener(_refreshProgress);
    }
  }

  void _refreshProgress() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final controller in [
      _nameCtrl,
      _phoneCtrl,
      _licCtrl,
      _vNumCtrl,
      _vModelCtrl,
    ]) {
      controller.removeListener(_refreshProgress);
    }
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _licCtrl.dispose();
    _vNumCtrl.dispose();
    _vModelCtrl.dispose();
    super.dispose();
  }

  Future<File?> _pick(String label) async {
    final src = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Upload $label',
              style:
                  const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ListTile(
            leading: const Icon(Icons.camera_alt, color: AppColors.primary),
            title: const Text('Camera'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library, color: AppColors.primary),
            title: const Text('Gallery'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ]),
      ),
    );
    if (src == null) return null;
    final xf = await _picker.pickImage(source: src, imageQuality: 80);
    return xf == null ? null : File(xf.path);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await _api.registerDriver(
        name: _nameCtrl.text.trim(),
        phone: '+91${_phoneCtrl.text.trim()}',
        license: _licCtrl.text.trim().toUpperCase(),
        vehicleNumber: _vNumCtrl.text.trim().toUpperCase(),
        vehicleType: _vType,
        vehicleModel:
            _vModelCtrl.text.trim().isEmpty ? null : _vModelCtrl.text.trim(),
        licenseImage: _licImg,
        vehicleRC: _rcImg,
        insurance: _insImg,
        profilePhoto: _photoImg,
      );
      await SessionManager.instance
          .markDriverPhoneRegistered('+91${_phoneCtrl.text.trim()}');
      if (!mounted) return;
      setState(() => _done = true);
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['error']?.toString() ??
          'Registration failed';
      showSnack(context, msg, error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return _SuccessScreen();

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: AppColors.background,
      appBar: backAppBar('Driver Registration', () => context.pop()),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MCard(
                color: AppColors.primaryGlow,
                borderColor: AppColors.primary.withValues(alpha: 0.3),
                child: const Row(children: [
                  Text('🚗', style: TextStyle(fontSize: 30)),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Join as a Driver',
                            style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary)),
                        SizedBox(height: 4),
                        Text(
                          'Admin reviews within 24h. '
                          'Notification sent on approval.',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.textSecondary,
                              height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ]),
              ),
              const SizedBox(height: 24),
              LinearProgressIndicator(
                value: _formProgress,
                backgroundColor: AppColors.surface2,
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
              const SizedBox(height: 8),
              Text(
                'Profile completion: ${(_formProgress * 100).round()}%',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              _label('PERSONAL INFORMATION'),
              const SizedBox(height: 10),
              _field(_nameCtrl, 'Full Name *',
                  icon: Icons.person_outline,
                  caps: TextCapitalization.words,
                  validator: (v) =>
                      v?.trim().isEmpty == true ? 'Required' : null),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                style: const TextStyle(color: AppColors.textPrimary),
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(10),
                ],
                decoration: const InputDecoration(
                  labelText: 'Phone Number *',
                  prefixText: '+91  ',
                  prefixIcon: Icon(Icons.phone_outlined,
                      color: AppColors.textSecondary),
                ),
                validator: (v) => (v?.trim().length ?? 0) < 10
                    ? 'Enter valid 10-digit number'
                    : null,
              ),
              const SizedBox(height: 24),
              _label('LICENSE'),
              const SizedBox(height: 10),
              _field(
                _licCtrl,
                'Driving License Number *',
                icon: Icons.credit_card,
                caps: TextCapitalization.characters,
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 24),
              _label('VEHICLE DETAILS'),
              const SizedBox(height: 10),
              TextFormField(
                controller: _vNumCtrl,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w700),
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Vehicle Number *',
                  prefixIcon: Icon(Icons.confirmation_number_outlined,
                      color: AppColors.textSecondary),
                ),
                validator: (v) => v?.trim().isEmpty == true ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              _field(_vModelCtrl, 'Vehicle Model (optional)',
                  icon: Icons.directions_car_outlined),
              const SizedBox(height: 16),
              const Text('Vehicle Type *',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kVehicles
                    .map((v) => _VTypePill(
                          option: v,
                          selected: _vType == v.type,
                          onTap: () => setState(() => _vType = v.type),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 24),
              _label('DOCUMENTS'),
              const SizedBox(height: 10),
              ...[
                (
                  '🪪 Driving License Photo',
                  _licImg,
                  (File? f) => setState(() => _licImg = f)
                ),
                (
                  '📄 Vehicle RC',
                  _rcImg,
                  (File? f) => setState(() => _rcImg = f)
                ),
                (
                  '🛡️ Insurance Certificate',
                  _insImg,
                  (File? f) => setState(() => _insImg = f)
                ),
                (
                  '📷 Profile Photo',
                  _photoImg,
                  (File? f) => setState(() => _photoImg = f)
                ),
              ].map(
                (t) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _DocTile(
                    label: t.$1,
                    file: t.$2,
                    onTap: () async {
                      final f = await _pick(t.$1);
                      if (f != null) t.$3(f);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              PrimaryButton(
                  label: 'Submit Registration →',
                  onTap: _submit,
                  loading: _loading),
              const SizedBox(height: 12),
              Center(
                child: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Already registered? Login',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String t) => Text(t,
      style: const TextStyle(
          fontSize: 11,
          color: AppColors.primary,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8));

  Widget _field(
    TextEditingController ctrl,
    String label, {
    IconData? icon,
    TextCapitalization caps = TextCapitalization.none,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: ctrl,
      style: const TextStyle(color: AppColors.textPrimary),
      textCapitalization: caps,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon:
            icon != null ? Icon(icon, color: AppColors.textSecondary) : null,
      ),
      validator: validator,
    );
  }
}

class _VTypePill extends StatelessWidget {
  final VehicleOption option;
  final bool selected;
  final VoidCallback onTap;
  const _VTypePill(
      {required this.option, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(option.emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 6),
          Text(
            option.name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ]),
      ),
    );
  }
}

class _DocTile extends StatelessWidget {
  final String label;
  final File? file;
  final VoidCallback onTap;
  const _DocTile({required this.label, this.file, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final uploaded = file != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: uploaded ? AppColors.successBg : AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: uploaded ? AppColors.success : AppColors.border),
        ),
        child: Row(children: [
          Text(uploaded ? '✅' : '📎', style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              uploaded ? '$label (uploaded)' : label,
              style: TextStyle(
                fontSize: 14,
                color: uploaded ? AppColors.success : AppColors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(uploaded ? Icons.check_circle : Icons.upload_outlined,
              color: uploaded ? AppColors.success : AppColors.textMuted,
              size: 18),
        ]),
      ),
    );
  }
}

class _SuccessScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('⏳', style: TextStyle(fontSize: 80)),
              const SizedBox(height: 28),
              const Text('Registration Submitted!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 12),
              const Text(
                'Our admin team will review your documents '
                'within 24 hours. You\'ll receive a '
                'notification once approved.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 15, color: AppColors.textSecondary, height: 1.6),
              ),
              const SizedBox(height: 40),
              PrimaryButton(
                label: 'Login to Check Status',
                onTap: () => context.go(AppRoutes.login),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
