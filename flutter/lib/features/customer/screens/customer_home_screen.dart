import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/data/datasources/api_service.dart';
import 'package:movezy/data/models/models.dart';
import 'package:movezy/services/session_manager.dart';
import 'package:movezy/services/socket_service.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen> {
  GoogleMapController? _mapCtrl;
  Position? _pos;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  List<LatLng> _tripRoutePath = const [];
  String? _tripRouteKey;
  List<NearbyDriver> _nearbyDrivers = const [];
  BookingModel? _activeBooking;
  String? _driverPhone;
  LatLng? _driverLatLng;
  StreamSubscription<Position>? _locSub;
  Timer? _refreshTimer;
  Timer? _driverAnimationTimer;
  bool _dashboardSyncInFlight = false;
  bool _mapReady = false;
  static const Duration _searchTimeout = Duration(minutes: 5);
  String? _locationNotice;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _api.setToken(SessionManager.instance.getToken());
    _initLoc();
    _connectSocket();
    _checkActive(fitCamera: true);
    _startLiveRefresh();
  }

  @override
  void dispose() {
    _locSub?.cancel();
    _refreshTimer?.cancel();
    _driverAnimationTimer?.cancel();
    SocketService.instance.offAll();
    super.dispose();
  }

  void _startLiveRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!SocketService.instance.connected || _activeBooking == null) {
        _syncDashboard();
      }
    });
  }

  Future<void> _syncDashboard({bool fitCamera = false}) async {
    if (_dashboardSyncInFlight) return;
    _dashboardSyncInFlight = true;
    try {
      await _checkActive(fitCamera: fitCamera);
    } finally {
      _dashboardSyncInFlight = false;
    }
  }

  Future<void> _initLoc() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _locationNotice =
              'Allow location to see your live position, nearby drivers, and accurate booking tracking.';
        });
      }
      return;
    }
    final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high);
    if (!mounted) return;
    setState(() {
      _pos = pos;
      _locationNotice = null;
    });
    _refreshMapOverlay(fitCamera: true);
    _refreshNearbyDrivers();

    _locSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 20),
    ).listen((p) {
      if (!mounted) return;
      setState(() => _pos = p);
      _api.updateCustomerLocation(p.latitude, p.longitude);
      if (_activeBooking != null) {
        SocketService.instance.emitCustomerLoc(p.latitude, p.longitude,
            bookingId: _activeBooking!.id);
      } else {
        _refreshNearbyDrivers();
      }
      _refreshMapOverlay();
    });
  }

  void _connectSocket() {
    final token = SessionManager.instance.getToken();
    if (token == null) return;
    SocketService.instance.connect(token);

    SocketService.instance.on('booking_accepted', (data) {
      if (!mounted) return;
      final bid = data['bookingId']?.toString();
      if (bid != null && bid == _activeBooking?.id) {
        final d = data['driver'] as Map?;
        setState(() {
          _driverPhone = d?['phone']?.toString();
          final lat = (d?['latitude'] as num?)?.toDouble();
          final lng = (d?['longitude'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            _driverLatLng = LatLng(lat, lng);
          }
        });
        _syncDashboard(fitCamera: true);
        showSnack(
          context,
          '🚗 Driver found: ${d?['name']} · ${d?['vehicleNumber']}',
        );
      }
    });

    SocketService.instance.on('driver_location_update', (data) {
      if (!mounted) return;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        _updateDriverLocation(lat, lng, fitCamera: true);
      }
    });

    SocketService.instance.on('trip_started', (_) {
      if (!mounted) return;
      _syncDashboard(fitCamera: true);
      showSnack(context, '🚀 Trip started! Goods on the way.');
    });

    SocketService.instance.on('trip_completed', (_) {
      if (!mounted) return;
      final bid = _activeBooking?.id;
      setState(() {
        _activeBooking = null;
        _driverPhone = null;
        _driverLatLng = null;
        _tripRoutePath = const [];
        _tripRouteKey = null;
      });
      _refreshNearbyDrivers(fitCamera: true);
      if (bid != null) {
        context.push(AppRoutes.rateBooking, extra: {'bookingId': bid});
      }
    });

    SocketService.instance.on('booking_cancelled', (data) {
      if (!mounted) return;
      if (data['by'] == 'driver') {
        showSnack(context, 'Driver cancelled. Please rebook.', error: true);
      }
      setState(() {
        _activeBooking = null;
        _driverPhone = null;
        _driverLatLng = null;
        _tripRoutePath = const [];
        _tripRouteKey = null;
      });
      _refreshNearbyDrivers(fitCamera: true);
    });
  }

  Future<void> _checkActive({bool fitCamera = false}) async {
    try {
      final b = await _api.getActiveBooking();
      if (!mounted) return;
      setState(() {
        _activeBooking = b;
        final lat = b?.driver?.latitude;
        final lng = b?.driver?.longitude;
        _driverPhone = b?.driver?.phone;
        _driverLatLng = lat != null && lng != null ? LatLng(lat, lng) : null;
        if (b != null) {
          _nearbyDrivers = const [];
        } else {
          _tripRoutePath = const [];
          _tripRouteKey = null;
        }
      });
      if (b != null) {
        SocketService.instance.joinBooking(b.id);
      } else {
        await _refreshNearbyDrivers(fitCamera: fitCamera);
      }
      _refreshMapOverlay(fitCamera: fitCamera);
    } catch (_) {}
  }

  Future<void> _refreshNearbyDrivers({bool fitCamera = false}) async {
    if (_pos == null || _activeBooking != null) return;
    try {
      final drivers = await _api.getNearbyDrivers(
        latitude: _pos!.latitude,
        longitude: _pos!.longitude,
      );
      if (!mounted) return;
      setState(() => _nearbyDrivers = drivers);
      _refreshMapOverlay(fitCamera: fitCamera);
    } catch (_) {}
  }

  void _updateDriverLocation(double lat, double lng, {bool fitCamera = false}) {
    final target = LatLng(lat, lng);
    final start = _driverLatLng;
    if (start == null) {
      setState(() => _driverLatLng = target);
      _refreshMapOverlay(fitCamera: fitCamera);
      return;
    }
    _driverAnimationTimer?.cancel();
    const steps = 8;
    var currentStep = 0;
    _driverAnimationTimer = Timer.periodic(const Duration(milliseconds: 120), (timer) {
      currentStep += 1;
      final t = currentStep / steps;
      final next = LatLng(
        start.latitude + ((target.latitude - start.latitude) * t),
        start.longitude + ((target.longitude - start.longitude) * t),
      );
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() => _driverLatLng = next);
      _refreshMapOverlay(fitCamera: fitCamera && currentStep == steps);
      if (currentStep >= steps) {
        timer.cancel();
      }
    });
  }

  void _refreshMapOverlay({bool fitCamera = false}) {
    final nextMarkers = <Marker>{};
    final nextPolylines = <Polyline>{};

    if (_pos != null) {
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('customer'),
          position: LatLng(_pos!.latitude, _pos!.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Your location'),
        ),
      );
    }

    final booking = _activeBooking;
    final pickup = booking?.pickup;
    final dropoff = booking?.dropoff;
    if (pickup != null && pickup.latitude != 0 && pickup.longitude != 0) {
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(pickup.latitude, pickup.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(title: 'Pickup', snippet: pickup.address),
        ),
      );
    }
    if (dropoff != null && dropoff.latitude != 0 && dropoff.longitude != 0) {
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(dropoff.latitude, dropoff.longitude),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(title: 'Drop-off', snippet: dropoff.address),
        ),
      );
    }
    if (_driverLatLng != null) {
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: _driverLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueYellow,
          ),
          infoWindow: const InfoWindow(title: 'Driver'),
        ),
      );
    }

    if (booking == null) {
      for (final driver in _nearbyDrivers) {
        final lat = driver.latitude;
        final lng = driver.longitude;
        if (lat == null || lng == null || lat == 0 || lng == 0) continue;
        nextMarkers.add(
          Marker(
            markerId: MarkerId('nearby_${driver.id}'),
            position: LatLng(lat, lng),
            icon: BitmapDescriptor.defaultMarkerWithHue(_markerHueForVehicle(driver.vehicleType)),
            infoWindow: InfoWindow(
              title: '${_vehicleEmoji(driver.vehicleType)} ${driver.name.isNotEmpty ? driver.name : 'Nearby driver'}',
              snippet:
                  '${driver.vehicleNumber} · ${driver.vehicleType.replaceAll('_', ' ')}',
            ),
          ),
        );
      }
    }

    final routePoints = <LatLng>[
      if (pickup != null && pickup.latitude != 0 && pickup.longitude != 0)
        LatLng(pickup.latitude, pickup.longitude),
      if (dropoff != null && dropoff.latitude != 0 && dropoff.longitude != 0)
        LatLng(dropoff.latitude, dropoff.longitude),
    ];
    if (routePoints.length >= 2) {
      _ensureTripRoutePath(routePoints[0], routePoints[1]);
      nextPolylines.add(
        Polyline(
          polylineId: const PolylineId('trip-route'),
          points: _tripRoutePath.length >= 2 ? _tripRoutePath : routePoints,
          width: 5,
          color: AppColors.primary,
          geodesic: true,
        ),
      );
    }

    final driverTarget = booking?.isInProgress == true
        ? (dropoff != null && dropoff.latitude != 0 && dropoff.longitude != 0
            ? LatLng(dropoff.latitude, dropoff.longitude)
            : null)
        : (pickup != null && pickup.latitude != 0 && pickup.longitude != 0
            ? LatLng(pickup.latitude, pickup.longitude)
            : null);
    if (_driverLatLng != null && driverTarget != null) {
      nextPolylines.add(
        Polyline(
          polylineId: const PolylineId('driver-progress'),
          points: [_driverLatLng!, driverTarget],
          width: 4,
          color: AppColors.warning,
          patterns: [PatternItem.dash(24), PatternItem.gap(12)],
        ),
      );
    }

    setState(() {
      _markers
        ..clear()
        ..addAll(nextMarkers);
      _polylines
        ..clear()
        ..addAll(nextPolylines);
    });

    if (fitCamera) {
      _fitMapToVisiblePoints([
        if (_pos != null) LatLng(_pos!.latitude, _pos!.longitude),
        ...routePoints,
        if (_driverLatLng != null) _driverLatLng!,
        if (booking == null)
          ..._nearbyDrivers
              .where((driver) =>
                  driver.latitude != null &&
                  driver.longitude != null &&
                  driver.latitude != 0 &&
                  driver.longitude != 0)
              .take(4)
              .map((driver) => LatLng(driver.latitude!, driver.longitude!)),
      ]);
    }
  }

  String _vehicleEmoji(String vehicleType) {
    final vehicle = vehicleByType(vehicleType);
    return vehicle?.emoji ?? '🚘';
  }

  double _markerHueForVehicle(String vehicleType) {
    switch (vehicleType) {
      case 'bike':
        return BitmapDescriptor.hueGreen;
      case 'auto':
        return BitmapDescriptor.hueAzure;
      case 'mini_truck':
        return BitmapDescriptor.hueOrange;
      case 'tempo':
        return BitmapDescriptor.hueViolet;
      case 'truck':
        return BitmapDescriptor.hueRed;
      case 'pickup':
        return BitmapDescriptor.hueYellow;
      default:
        return BitmapDescriptor.hueOrange;
    }
  }

  Future<void> _ensureTripRoutePath(LatLng start, LatLng end) async {
    final routeKey = '${start.latitude.toStringAsFixed(5)},${start.longitude.toStringAsFixed(5)}:${end.latitude.toStringAsFixed(5)},${end.longitude.toStringAsFixed(5)}';
    if (_tripRouteKey == routeKey && _tripRoutePath.isNotEmpty) return;

    _tripRouteKey = routeKey;
    try {
      final routeCoordinates = await _api.getRoutePath(
        originLat: start.latitude,
        originLng: start.longitude,
        destinationLat: end.latitude,
        destinationLng: end.longitude,
      );
      if (!mounted || _tripRouteKey != routeKey) return;

      final routePath = routeCoordinates
          .map((coordinate) => LatLng(coordinate[0], coordinate[1]))
          .toList();
      setState(() {
        _tripRoutePath = routePath.length >= 2 ? routePath : const [];
      });
    } catch (_) {
      if (!mounted || _tripRouteKey != routeKey) return;
      setState(() {
        _tripRoutePath = const [];
      });
    }
  }

  Future<void> _fitMapToVisiblePoints(List<LatLng> rawPoints) async {
    final points = rawPoints
        .where((p) => p.latitude.isFinite && p.longitude.isFinite)
        .toList();
    if (_mapCtrl == null || points.isEmpty) return;
    if (points.length == 1) {
      await _mapCtrl!.animateCamera(
        CameraUpdate.newLatLngZoom(points.first, AppConstants.defaultZoom),
      );
      return;
    }

    double minLat = points.first.latitude;
    double maxLat = points.first.latitude;
    double minLng = points.first.longitude;
    double maxLng = points.first.longitude;
    for (final point in points.skip(1)) {
      minLat = point.latitude < minLat ? point.latitude : minLat;
      maxLat = point.latitude > maxLat ? point.latitude : maxLat;
      minLng = point.longitude < minLng ? point.longitude : minLng;
      maxLng = point.longitude > maxLng ? point.longitude : maxLng;
    }

    if (minLat == maxLat) {
      minLat -= 0.01;
      maxLat += 0.01;
    }
    if (minLng == maxLng) {
      minLng -= 0.01;
      maxLng += 0.01;
    }

    await _mapCtrl!.animateCamera(
      CameraUpdate.newLatLngBounds(
        LatLngBounds(
          southwest: LatLng(minLat, minLng),
          northeast: LatLng(maxLat, maxLng),
        ),
        72,
      ),
    );
  }

  Future<void> _cancel() async {
    final ok = await _confirmDialog(
        'Cancel Booking?', 'Are you sure you want to cancel?');
    if (!ok || _activeBooking == null) return;
    if (_activeBooking!.isInProgress) {
      showSnack(context, 'Cannot cancel an in-progress booking.', error: true);
      return;
    }
    try {
      await _api.cancelBooking(_activeBooking!.id);
      setState(() {
        _activeBooking = null;
        _driverPhone = null;
        _driverLatLng = null;
      });
      _refreshMapOverlay(fitCamera: true);
      if (mounted) showSnack(context, 'Booking cancelled');
    } catch (_) {
      if (mounted) showSnack(context, 'Cancel failed', error: true);
    }
  }

  Future<bool> _confirmDialog(String title, String body) async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border)),
        title:
            Text(title, style: const TextStyle(color: AppColors.textPrimary)),
        content:
            Text(body, style: const TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child:
                  const Text('Yes', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    return res == true;
  }

  void _callDriver() {
    if (_driverPhone == null) return;
    launchUrl(Uri.parse('tel:$_driverPhone'));
  }

  Future<void> _openSupportUri(String uri) async {
    await launchUrl(Uri.parse(uri), mode: LaunchMode.externalApplication);
  }

  Future<void> _logout() async {
    await SessionManager.instance.clear();
    SocketService.instance.disconnect();
    if (!mounted) return;
    context.go(AppRoutes.login);
  }

  Future<void> _openSettingsSheet() async {
    final user = SessionManager.instance.getUser();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => AppSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: AppColors.primaryGlow,
                  child: Text(
                    user?.name.isNotEmpty == true
                        ? user!.name[0].toUpperCase()
                        : 'U',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.name ?? 'Movezy User',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        user?.phone ?? '',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primaryGlow,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'Customer',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SettingsTile(
              icon: Icons.history_rounded,
              title: 'Booking History',
              subtitle: 'Track past transport requests and receipts',
              onTap: () {
                Navigator.pop(sheetContext);
                context.push(AppRoutes.bookingHistory);
              },
            ),
            const SizedBox(height: 10),
            SettingsTile(
              icon: Icons.local_shipping_outlined,
              title: SessionManager.instance
                      .isDriverPhoneRegistered(user?.phone ?? '')
                  ? 'Driver Access Enabled'
                  : 'Register as Driver',
              subtitle: SessionManager.instance
                      .isDriverPhoneRegistered(user?.phone ?? '')
                  ? 'This phone can use the driver login flow'
                  : 'Register this phone before using driver login',
              onTap: () {
                Navigator.pop(sheetContext);
                if (!SessionManager.instance
                    .isDriverPhoneRegistered(user?.phone ?? '')) {
                  context.push(AppRoutes.driverRegister);
                }
              },
            ),
            const SizedBox(height: 10),
            ValueListenableBuilder<bool>(
              valueListenable: SessionManager.instance.nightMapsEnabled,
              builder: (context, nightMapsEnabled, _) => SettingsTile(
                icon: Icons.layers_outlined,
                title: 'Night Maps',
                subtitle: 'Use the darker navigation style across maps',
                trailing: Switch.adaptive(
                  value: nightMapsEnabled,
                  activeColor: AppColors.primary,
                  onChanged: (value) async {
                    await SessionManager.instance.setNightMapsEnabled(value);
                    if (mounted) {
                      setState(() {});
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            SettingsTile(
              icon: Icons.support_agent,
              title: 'Customer Service',
              subtitle: 'Talk to Movezy support for booking help',
              onTap: () => _openSupportUri(AppConstants.supportWhatsApp),
            ),
            const SizedBox(height: 10),
            SettingsTile(
              icon: Icons.call_outlined,
              title: 'Call Support',
              subtitle: AppConstants.supportPhone,
              onTap: () => _openSupportUri('tel:${AppConstants.supportPhone}'),
            ),
            const SizedBox(height: 10),
            SettingsTile(
              icon: Icons.mail_outline,
              title: 'Email Support',
              subtitle: AppConstants.supportEmail,
              onTap: () => _openSupportUri(
                  'mailto:${AppConstants.supportEmail}?subject=Movezy Help'),
            ),
            const SizedBox(height: 10),
            SettingsTile(
              icon: Icons.logout_rounded,
              title: 'Logout',
              subtitle: 'Sign out of your Movezy account',
              danger: true,
              trailing: const SizedBox.shrink(),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _logout();
              },
            ),
          ],
        ),
      ),
    );
    if (mounted) {
      _refreshMapOverlay();
    }
  }

  void _focusMap() {
    if (_pos == null && _driverLatLng == null) return;
    _fitMapToVisiblePoints([
      if (_pos != null) LatLng(_pos!.latitude, _pos!.longitude),
      if (_driverLatLng != null) _driverLatLng!,
      if (_activeBooking?.pickup != null &&
          _activeBooking!.pickup!.latitude != 0 &&
          _activeBooking!.pickup!.longitude != 0)
        LatLng(
          _activeBooking!.pickup!.latitude,
          _activeBooking!.pickup!.longitude,
        ),
      if (_activeBooking?.dropoff != null &&
          _activeBooking!.dropoff!.latitude != 0 &&
          _activeBooking!.dropoff!.longitude != 0)
        LatLng(
          _activeBooking!.dropoff!.latitude,
          _activeBooking!.dropoff!.longitude,
        ),
      if (_activeBooking == null)
        ..._nearbyDrivers
            .where((driver) =>
                driver.latitude != null &&
                driver.longitude != null &&
                driver.latitude != 0 &&
                driver.longitude != 0)
            .take(4)
            .map((driver) => LatLng(driver.latitude!, driver.longitude!)),
    ]);
  }

  Widget? _buildDashboardNotice() {
    if (_locationNotice != null) {
      return InlineNoticeCard(
        icon: Icons.location_off_outlined,
        title: 'Location access is needed',
        subtitle: _locationNotice!,
        accent: AppColors.warning,
      );
    }
    if (_activeBooking == null && _pos != null && _nearbyDrivers.isEmpty) {
      return const InlineNoticeCard(
        icon: Icons.radar_outlined,
        title: 'Map is ready',
        subtitle:
            'Your live map is working. Nearby driver markers will appear here as soon as approved online drivers are available.',
        accent: AppColors.success,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = SessionManager.instance.getUser();
    final notice = _buildDashboardNotice();
    final mapBottomInset = _activeBooking != null ? 292.0 : 228.0;
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(color: AppColors.background),
              child: GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: LatLng(
                    _pos?.latitude ?? 20.5937,
                    _pos?.longitude ?? 78.9629,
                  ),
                  zoom: AppConstants.dashboardMapZoom,
                ),
                onMapCreated: (c) {
                  _mapCtrl = c;
                  _mapReady = true;
                  _refreshMapOverlay(fitCamera: true);
                },
                style: SessionManager.instance.nightMapsEnabled.value ? _kMapStyle : null,
                markers: _markers,
                polylines: _polylines,
                padding: EdgeInsets.only(
                  top: 212,
                  bottom: mapBottomInset,
                  left: 12,
                  right: 12,
                ),
                myLocationEnabled: _pos != null,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.background.withValues(alpha: 0.16),
                      Colors.transparent,
                      Colors.transparent,
                      AppColors.background.withValues(alpha: 0.66),
                    ],
                    stops: const [0, 0.18, 0.52, 1],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _DashboardHero(
                          title:
                              'Hey, ${user?.name.split(' ').firstOrNull ?? 'there'} 👋',
                          subtitle: _activeBooking != null
                              ? '${_activeBooking!.statusLabel} · ${_activeBooking!.displayBookingId}'
                              : 'Live map, nearby vehicles, and quick booking',
                          accent: _activeBooking != null
                              ? 'Active booking'
                              : 'Customer',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        children: [
                          FloatingMapButton(
                            icon: Icons.tune_rounded,
                            onTap: _openSettingsSheet,
                          ),
                          const SizedBox(height: 10),
                          FloatingMapButton(
                            icon: Icons.my_location_rounded,
                            iconColor: AppColors.primary,
                            onTap: _focusMap,
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      InfoPill(
                        icon: Icons.place_outlined,
                        label: _activeBooking != null
                            ? _activeBooking!.statusLabel
                            : _nearbyDrivers.isEmpty
                                ? 'Searching nearby coverage'
                                : '${_nearbyDrivers.length} nearby drivers',
                        color: _activeBooking != null
                            ? AppColors.primary
                            : AppColors.success,
                        backgroundColor:
                            AppColors.surface.withValues(alpha: 0.9),
                      ),
                      InfoPill(
                        icon: Icons.route_outlined,
                        label: _activeBooking?.estimatedDistance != null
                            ? _activeBooking != null
                                ? '${_activeBooking!.estimatedDistance.toStringAsFixed(1)} km active route'
                                : 'Live map ready'
                            : 'Live map ready',
                      ),
                      if (_pos != null)
                        InfoPill(
                          icon: Icons.my_location,
                          label: '${_pos!.latitude.toStringAsFixed(4)}, ${_pos!.longitude.toStringAsFixed(4)}',
                          color: AppColors.info,
                        ),
                      InfoPill(
                        icon: Icons.directions_car_filled_outlined,
                        label: _driverPhone != null
                            ? 'Driver assigned'
                            : _activeBooking != null
                                ? 'Finding driver'
                                : 'Tap book to start',
                      ),
                    ],
                  ),
                  if (notice != null) ...[
                    const SizedBox(height: 12),
                    notice,
                  ],
                  if (!_mapReady) ...[
                    const SizedBox(height: 12),
                    const InlineNoticeCard(
                      icon: Icons.map_outlined,
                      title: 'Initializing map surface',
                      subtitle:
                          'If this stays blank, verify your Google Maps API key, billing, SDK enablement, and package or SHA restrictions.',
                      accent: AppColors.warning,
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _activeBooking != null
                ? _ActivePanel(
                    booking: _activeBooking!,
                    driverPhone: _driverPhone,
                    remainingSearch:
                        _activeBooking!.isSearching ? _searchRemaining() : null,
                    onCall: _callDriver,
                    onCancel: _cancel,
                  )
                : _HomePanel(
                    nearbyDriversCount: _nearbyDrivers.length,
                    onBook: () async {
                      await context.push(AppRoutes.booking);
                      _syncDashboard(fitCamera: true);
                    },
                    onHistory: () => context.push(AppRoutes.bookingHistory),
                  ),
          ),
        ],
      ),
    );
  }

  Duration? _searchRemaining() {
    final createdAt = _activeBooking?.createdAt;
    if (createdAt == null) return null;
    final elapsed = DateTime.now().difference(createdAt);
    final remaining = _searchTimeout - elapsed;
    if (remaining.isNegative) {
      return Duration.zero;
    }
    return remaining;
  }
}

class _DashboardHero extends StatelessWidget {
  final String title;
  final String subtitle;
  final String accent;

  const _DashboardHero({
    required this.title,
    required this.subtitle,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(
              child: Text('⚡', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              accent,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Home bottom panel ─────────────────────────────────────────────
class _HomePanel extends StatelessWidget {
  final int nearbyDriversCount;
  final VoidCallback onBook;
  final VoidCallback onHistory;
  const _HomePanel({
    required this.nearbyDriversCount,
    required this.onBook,
    required this.onHistory,
  });

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Quick Book',
                style: TextStyle(
                  fontSize: 15,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            InfoPill(
              icon: Icons.radar_outlined,
              label: nearbyDriversCount > 0
                  ? '$nearbyDriversCount live nearby'
                  : 'Waiting for drivers',
              color: nearbyDriversCount > 0
                  ? AppColors.success
                  : AppColors.textSecondary,
              backgroundColor: AppColors.surface2,
            ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 108,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: kVehicles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final v = kVehicles[i];
              return GestureDetector(
                onTap: onBook,
                child: Container(
                  width: 112,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(v.emoji, style: const TextStyle(fontSize: 22)),
                      ),
                      const SizedBox(height: 6),
                      Text(v.name,
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center),
                      const SizedBox(height: 2),
                      Text(
                        v.capacity,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        PrimaryButton(label: '📦   Book Transport', onTap: onBook),
        const SizedBox(height: 8),
        OutlineBtn(label: '📋   View History', onTap: onHistory),
      ]),
    );
  }
}

// ── Active booking panel ──────────────────────────────────────────
class _ActivePanel extends StatelessWidget {
  final BookingModel booking;
  final String? driverPhone;
  final Duration? remainingSearch;
  final VoidCallback onCall;
  final VoidCallback onCancel;
  const _ActivePanel({
    required this.booking,
    this.driverPhone,
    this.remainingSearch,
    required this.onCall,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final driver = booking.driver;
    return _Sheet(
      borderColor: AppColors.success,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child:
                const Center(child: Text('🚗', style: TextStyle(fontSize: 20))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.statusLabel,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text('${booking.displayBookingId} · ₹${booking.estimatedFare}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          StatusBadge(status: booking.status),
        ]),
        if (booking.isSearching) ...[
          const SizedBox(height: 14),
          const LinearProgressIndicator(
            backgroundColor: AppColors.surface2,
            valueColor: AlwaysStoppedAnimation(AppColors.primary),
          ),
          const SizedBox(height: 8),
          Text(
              booking.nearbyDriversCount > 0
                  ? 'Searching among ${booking.nearbyDriversCount} nearby drivers…'
                  : 'Searching for nearby drivers…',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          if (remainingSearch != null) ...[
            const SizedBox(height: 6),
            Text(
              remainingSearch == Duration.zero
                  ? 'Search window expired. Please rebook.'
                  : 'Search timeout in ${remainingSearch!.inMinutes}:${(remainingSearch!.inSeconds % 60).toString().padLeft(2, '0')}',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.warning,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
        if (driver != null && !booking.isSearching) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.primaryGlow,
                child: Text(
                  driver.name.isNotEmpty ? driver.name[0].toUpperCase() : 'D',
                  style: const TextStyle(
                      color: AppColors.primary, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    Text(
                        '${driver.vehicleNumber} · ⭐ ${driver.rating.toStringAsFixed(1)}',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (driverPhone != null)
                GestureDetector(
                  onTap: onCall,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.successBg,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.phone,
                        color: AppColors.success, size: 20),
                  ),
                ),
            ]),
          ),
        ],
        if (!booking.isInProgress && !booking.isCompleted) ...[
          const SizedBox(height: 12),
          OutlineBtn(label: '✕   Cancel Booking', onTap: onCancel, height: 44),
        ],
      ]),
    );
  }
}

// ── Shared bottom sheet container ─────────────────────────────────
class _Sheet extends StatelessWidget {
  final Widget child;
  final Color? borderColor;
  const _Sheet({required this.child, this.borderColor});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border(
          top: BorderSide(
              color: borderColor ?? AppColors.border,
              width: borderColor != null ? 1.5 : 1),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, -4)),
        ],
      ),
      padding: EdgeInsets.fromLTRB(20, 14, 20, 20 + bottomInset),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 4,
          margin: const EdgeInsets.only(bottom: 18),
          decoration: BoxDecoration(
            color: AppColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        child,
      ]),
    );
  }
}

// Dark map style
const _kMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#0d0d0d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#222222"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#0d0d0d"}]}
]''';
