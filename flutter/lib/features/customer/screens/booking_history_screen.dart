import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/data/datasources/api_service.dart';
import 'package:movezy/data/models/models.dart';
import 'package:movezy/services/session_manager.dart';

class BookingHistoryScreen extends StatefulWidget {
  const BookingHistoryScreen({super.key});

  @override
  State<BookingHistoryScreen> createState() => _BookingHistoryScreenState();
}

class _BookingHistoryScreenState extends State<BookingHistoryScreen> {
  List<BookingModel> _list = [];
  bool _loading = true;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _api.setToken(SessionManager.instance.getToken());
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _api.getBookingHistory();
      if (mounted) setState(() => _list = data);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: backAppBar('Booking History', () => context.pop()),
      body: _loading
          ? const CentreLoader()
          : _list.isEmpty
              ? const EmptyState(
                  emoji: '📭',
                  title: 'No bookings yet',
                  subtitle: 'Your transport requests will appear here.',
                )
              : RefreshIndicator(
                  color: AppColors.primary,
                  backgroundColor: AppColors.surface,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) => _BookingCard(b: _list[i]),
                  ),
                ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  final BookingModel b;
  const _BookingCard({required this.b});

  @override
  Widget build(BuildContext context) {
    final v = vehicleByType(b.vehicleType);
    final dateStr = b.createdAt != null
        ? DateFormat('d MMM, hh:mm a').format(b.createdAt!)
        : '';

    return MCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                  child: Text(v?.emoji ?? '📦',
                      style: const TextStyle(fontSize: 20))),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.displayBookingId,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary)),
                  Text(dateStr,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
            StatusBadge(status: b.status),
          ]),
          const SizedBox(height: 12),
          const MDivider(),
          const SizedBox(height: 10),
          Text('📍 ${b.pickup?.address ?? '—'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('🏁 ${b.dropoff?.address ?? '—'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Row(children: [
            _Chip(v?.name ?? b.vehicleType, v?.emoji ?? '🚗'),
            const SizedBox(width: 8),
            _Chip('${b.estimatedDistance.toStringAsFixed(1)} km', '📏'),
            const Spacer(),
            Text('₹${b.estimatedFare}',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ]),
          if (b.isCompleted && b.customerRating == null) ...[
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => context
                  .push(AppRoutes.rateBooking, extra: {'bookingId': b.id}),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('⭐', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 6),
                    Text('Rate this trip',
                        style: TextStyle(
                            color: AppColors.warning,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final String icon;
  const _Chip(this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(icon, style: const TextStyle(fontSize: 12)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
