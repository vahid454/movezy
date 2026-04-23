import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/data/datasources/api_service.dart';
import 'package:movezy/data/models/models.dart';
import 'package:movezy/services/session_manager.dart';
import 'package:movezy/services/socket_service.dart';

class DriverProfileScreen extends StatefulWidget {
  const DriverProfileScreen({super.key});

  @override
  State<DriverProfileScreen> createState() =>
      _DriverProfileScreenState();
}

class _DriverProfileScreenState
    extends State<DriverProfileScreen> {
  DriverProfile? _profile;
  bool _loading = true;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _api.setToken(SessionManager.instance.getToken());
    _load();
  }

  Future<void> _load() async {
    try {
      final p = await _api.getDriverProfile();
      if (mounted) setState(() => _profile = p);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = SessionManager.instance.getUser();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar:
          backAppBar('My Profile', () => context.pop()),
      body: _loading
          ? const CentreLoader()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                // Avatar
                MCard(
                  child: Column(children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primaryGlow,
                      child: Text(
                        (user?.name.isNotEmpty == true)
                            ? user!.name[0].toUpperCase()
                            : 'D',
                        style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(user?.name ?? '—',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary)),
                    Text(user?.phone ?? '—',
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textSecondary)),
                    if (_profile != null) ...[
                      const SizedBox(height: 10),
                      StatusBadge(
                          status: _profile!.approvalStatus),
                    ],
                  ]),
                ),
                const SizedBox(height: 12),

                if (_profile != null) ...[
                  // Vehicle details
                  MCard(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text('VEHICLE DETAILS',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 10),
                        InfoRow(
                            label: 'Vehicle No.',
                            value: _profile!.vehicleNumber),
                        const MDivider(),
                        InfoRow(
                          label: 'Type',
                          value: vehicleByType(
                                      _profile!.vehicleType)
                                  ?.name ??
                              _profile!.vehicleType,
                        ),
                        if (_profile!.vehicleModel != null) ...[
                          const MDivider(),
                          InfoRow(
                              label: 'Model',
                              value: _profile!.vehicleModel!),
                        ],
                        if (_profile!.drivingLicense != null) ...[
                          const MDivider(),
                          InfoRow(
                              label: 'License',
                              value: _profile!.drivingLicense!),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Performance
                  MCard(
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        const Text('PERFORMANCE',
                            style: TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8)),
                        const SizedBox(height: 10),
                        InfoRow(
                          label: 'Rating',
                          value:
                              '⭐ ${_profile!.rating.toStringAsFixed(1)} / 5.0',
                          valueColor: AppColors.warning,
                        ),
                        const MDivider(),
                        InfoRow(
                            label: 'Total Trips',
                            value:
                                '${_profile!.totalTrips}'),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 20),
                OutlineBtn(
                  label: '🚪   Logout',
                  onTap: () {
                    SessionManager.instance.clear();
                    SocketService.instance.disconnect();
                    context.go(AppRoutes.login);
                  },
                ),
                const SizedBox(height: 32),
              ]),
            ),
    );
  }
}
