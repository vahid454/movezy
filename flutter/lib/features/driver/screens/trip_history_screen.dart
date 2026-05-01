import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shimmer/shimmer.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/data/datasources/api_service.dart';
import 'package:movezy/data/models/models.dart';
import 'package:movezy/services/session_manager.dart';

class TripHistoryScreen extends StatefulWidget {
  const TripHistoryScreen({super.key});

  @override
  State<TripHistoryScreen> createState() => _TripHistoryScreenState();
}

class _TripHistoryScreenState extends State<TripHistoryScreen> {
  List<BookingModel> _trips = [];
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
      final t = await _api.getDriverTripHistory();
      if (mounted) setState(() => _trips = t);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _totalTrips => _trips.where((t) => t.isCompleted).length;

  int get _totalEarnings =>
      _trips.where((t) => t.isCompleted).fold(0, (s, t) => s + t.estimatedFare);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: backAppBar('Trip History', () => context.pop()),
      body: _loading
          ? const _TripHistoryShimmer()
          : Column(children: [
              if (_trips.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: MCard(
                    color: AppColors.primaryGlow,
                    borderColor: AppColors.primary.withValues(alpha: 0.3),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(children: [
                      _Sum('🚛', '$_totalTrips', 'Trips'),
                      _Sum('💰', '₹$_totalEarnings', 'Earnings'),
                    ]),
                  ),
                ),
              const SizedBox(height: 4),
              Expanded(
                child: _trips.isEmpty
                    ? const EmptyState(
                        emoji: '📭',
                        title: 'No trips yet',
                        subtitle: 'Go online to start accepting requests!')
                    : RefreshIndicator(
                        color: AppColors.primary,
                        backgroundColor: AppColors.surface,
                        onRefresh: _load,
                        child: ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _trips.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (_, i) => _TripCard(trip: _trips[i]),
                        ),
                      ),
              ),
            ]),
    );
  }
}

class _TripHistoryShimmer extends StatelessWidget {
  const _TripHistoryShimmer();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: AppColors.surface2,
        highlightColor: AppColors.surface,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

class _Sum extends StatelessWidget {
  final String icon;
  final String value;
  final String label;
  const _Sum(this.icon, this.value, this.label);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 10),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.textSecondary)),
        ]),
      ]),
    );
  }
}

class _TripCard extends StatelessWidget {
  final BookingModel trip;
  const _TripCard({required this.trip});

  @override
  Widget build(BuildContext context) {
    final v = vehicleByType(trip.vehicleType);
    final dateStr = trip.createdAt != null
        ? DateFormat('d MMM, hh:mm a').format(trip.createdAt!)
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
                  Text(trip.displayBookingId,
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
            StatusBadge(status: trip.status),
          ]),
          const SizedBox(height: 10),
          const MDivider(),
          const SizedBox(height: 10),
          Text('📍 ${trip.pickup?.address ?? '—'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('🏁 ${trip.dropoff?.address ?? '—'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 10),
          Row(children: [
            Text('${trip.estimatedDistance.toStringAsFixed(1)} km',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const Spacer(),
            Text('₹${trip.estimatedFare}',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary)),
          ]),
        ],
      ),
    );
  }
}
