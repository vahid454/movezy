import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/services/session_manager.dart';

class DriverPendingScreen extends StatelessWidget {
  const DriverPendingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child:
              Column(mainAxisAlignment: MainAxisAlignment.center,
                  children: [
            const Text('⏳',
                style: TextStyle(fontSize: 80)),
            const SizedBox(height: 28),
            const Text(
              'Account Pending Approval',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary),
            ),
            const SizedBox(height: 12),
            const Text(
              'Our admin team is reviewing your documents. '
              'This typically takes up to 24 hours.\n\n'
              'You\'ll receive a push notification once approved.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textSecondary,
                  height: 1.6),
            ),
            const SizedBox(height: 36),
            MCard(
              borderColor: AppColors.warning.withOpacity(0.4),
              color: AppColors.warningBg,
              child: const Column(children: [
                InfoRow(
                    label: 'Status',
                    value: 'Under Review',
                    valueColor: AppColors.warning),
                MDivider(),
                InfoRow(
                    label: 'Expected time',
                    value: '24 hours'),
                MDivider(),
                InfoRow(
                    label: 'Notification',
                    value: 'Via push & call'),
              ]),
            ),
            const SizedBox(height: 28),
            OutlineBtn(
              label: '🚪  Logout',
              onTap: () {
                SessionManager.instance.clear();
                context.go(AppRoutes.login);
              },
            ),
          ]),
        ),
      ),
    );
  }
}
