import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/utils/vehicle_map_icons.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/data/datasources/api_service.dart';
import 'package:movezy/data/models/models.dart';
import 'package:movezy/services/session_manager.dart';
import 'package:movezy/services/socket_service.dart';

class DriverHomeScreen extends StatefulWidget {
  const DriverHomeScreen({super.key});

  @override
  State<DriverHomeScreen> createState() => _DriverHomeScreenState();
}

class _DriverHomeScreenState extends State<DriverHomeScreen> {
  GoogleMapController? _mapCtrl;
  Position? _pos;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  List<LatLng> _tripRoutePath = const [];
  String? _tripRouteKey;
  DriverProfile? _profile;
  BookingModel? _activeBooking;
  bool _isOnline = false;
  bool _toggleLoading = false;
  StreamSubscription<Position>? _locSub;
  Timer? _refreshTimer;
  Timer? _customerAnimationTimer;
  bool _dashboardSyncInFlight = false;
  bool _mapReady = false;
  String? _locationNotice;
  String? _customerPhone;
  LatLng? _customerLatLng;
  final _api = ApiService();
  Map<String, BitmapDescriptor> _vehicleBmps = {};
  Map<String, BitmapDescriptor> _vehicleBmpsCompact = {};
  List<Map<String, dynamic>> _openNearby = const [];
  Timer? _openBookingsPoll;

  /// Match server default `COMPLETE_TRIP_MAX_DROP_DISTANCE_M` (meters).
  static const double _kCompleteDropMaxM = 450;

  double? get _metersToDropOff {
    final b = _activeBooking;
    final p = _pos;
    final d = b?.dropoff;
    if (p == null || d == null) return null;
    if (d.latitude == 0 && d.longitude == 0) return null;
    return Geolocator.distanceBetween(
      p.latitude,
      p.longitude,
      d.latitude,
      d.longitude,
    );
  }

  bool get _canCompleteNearDrop {
    final m = _metersToDropOff;
    if (m == null) return false;
    return m <= _kCompleteDropMaxM;
  }

  @override
  void initState() {
    super.initState();
    _api.setToken(SessionManager.instance.getToken());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVehicleMapIcons());
    _loadProfile();
    _initLoc();
    _connectSocket();
    _startLiveRefresh();
  }

  @override
  void dispose() {
    _locSub?.cancel();
    _refreshTimer?.cancel();
    _customerAnimationTimer?.cancel();
    _openBookingsPoll?.cancel();
    SocketService.instance.offAll();
    super.dispose();
  }

  Future<void> _loadVehicleMapIcons() async {
    try {
      await VehicleMapIcons.preloadAll();
      final m = <String, BitmapDescriptor>{};
      final compact = <String, BitmapDescriptor>{};
      for (final v in kVehicles) {
        m[v.type] = await VehicleMapIcons.forVehicleType(v.type);
        compact[v.type] = await VehicleMapIcons.forVehicleType(
          v.type,
          logicalSide: VehicleMapIcons.kLogicalSideCompact,
        );
      }
      if (mounted) {
        setState(() {
          _vehicleBmps = m;
          _vehicleBmpsCompact = compact;
        });
        _refreshMapOverlay();
      }
    } catch (_) {}
  }

  BitmapDescriptor? _mapVehicleIcon(String? vehicleType) {
    final t = (vehicleType ?? '').trim();
    if (t.isNotEmpty && _vehicleBmpsCompact[t] != null) {
      return _vehicleBmpsCompact[t];
    }
    return _vehicleBmpsCompact['auto'] ?? _vehicleBmps[t.isNotEmpty ? t : 'auto'];
  }

  void _syncOpenBookingsPoll() {
    _openBookingsPoll?.cancel();
    if (!_isOnline || _activeBooking != null || _pos == null) {
      return;
    }
    _openBookingsPoll =
        Timer.periodic(const Duration(seconds: 22), (_) => _fetchNearbyOpenBookings());
    unawaited(_fetchNearbyOpenBookings());
  }

  Future<void> _fetchNearbyOpenBookings() async {
    if (_pos == null || !_isOnline || _activeBooking != null) return;
    try {
      final list = await _api.getDriverNearbyOpenBookings(
        latitude: _pos!.latitude,
        longitude: _pos!.longitude,
      );
      if (!mounted) return;
      setState(() => _openNearby = list);
      _refreshMapOverlay();
    } catch (_) {}
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
      await _loadProfile(fitCamera: fitCamera);
    } finally {
      _dashboardSyncInFlight = false;
    }
  }

  Future<void> _loadProfile({bool fitCamera = false}) async {
    try {
      final p = await _api.getDriverProfile();
      if (!mounted) return;
      setState(() {
        _profile = p;
        _isOnline = p.isOnline;
      });

      if (p.isApproved) {
        final active = await _api.getDriverActiveBooking();
        if (!mounted) return;
        setState(() {
          _activeBooking = active;
          _customerPhone = active?.customerPhone;
          _customerLatLng = active?.hasCustomerLiveLocation == true
              ? LatLng(active!.customerLatitude!, active.customerLongitude!)
              : null;
          if (active == null) {
            _tripRoutePath = const [];
            _tripRouteKey = null;
          }
        });
        if (active != null) {
          SocketService.instance.joinBooking(active.id);
          _openBookingsPoll?.cancel();
        } else {
          _syncOpenBookingsPoll();
        }
        _refreshMapOverlay(fitCamera: fitCamera || active != null);
      } else if (p.isPending || p.isRejected) {
        if (mounted) context.go(AppRoutes.driverPending);
      }
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Failed to load profile: $e', error: true);
      }
    }
  }

  Future<void> _initLoc() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _locationNotice =
              'Allow location so the driver app can update live tracking and nearby dispatch accurately.';
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
    if (_isOnline && _activeBooking == null) {
      _syncOpenBookingsPoll();
    }

    _locSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, distanceFilter: 10),
    ).listen((p) {
      if (!mounted) return;
      setState(() => _pos = p);
      if (_isOnline) {
        _api.updateDriverLocation(p.latitude, p.longitude);
        SocketService.instance.emitDriverLoc(p.latitude, p.longitude,
            bookingId: _activeBooking?.id);
        if (_activeBooking == null) {
          unawaited(_fetchNearbyOpenBookings());
        }
      }
      _refreshMapOverlay();
    });
  }

  void _connectSocket() {
    final token = SessionManager.instance.getToken();
    if (token == null) return;
    SocketService.instance.connect(token);

    SocketService.instance.on('new_booking_request', (data) {
      if (!mounted || _activeBooking != null) return;
      unawaited(_fetchNearbyOpenBookings());
      _showRequestDialog(data);
    });

    SocketService.instance.on('customer_location_update', (data) {
      if (!mounted) return;
      final lat = (data['latitude'] as num?)?.toDouble();
      final lng = (data['longitude'] as num?)?.toDouble();
      if (lat != null && lng != null) {
        _animateCustomerPosition(LatLng(lat, lng));
      }
    });

    SocketService.instance.on('booking_cancelled', (_) {
      if (!mounted) return;
      setState(() {
        _activeBooking = null;
        _customerPhone = null;
        _customerLatLng = null;
        _tripRoutePath = const [];
        _tripRouteKey = null;
      });
      _refreshMapOverlay(fitCamera: true);
      _syncOpenBookingsPoll();
      showSnack(context, 'Customer cancelled the booking', error: true);
    });
  }

  void _animateCustomerPosition(LatLng target) {
    final start = _customerLatLng;
    if (start == null) {
      setState(() => _customerLatLng = target);
      _refreshMapOverlay();
      return;
    }
    _customerAnimationTimer?.cancel();
    const steps = 8;
    var currentStep = 0;
    _customerAnimationTimer =
        Timer.periodic(const Duration(milliseconds: 120), (timer) {
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
      setState(() => _customerLatLng = next);
      _refreshMapOverlay();
      if (currentStep >= steps) {
        timer.cancel();
      }
    });
  }

  void _refreshMapOverlay({bool fitCamera = false}) {
    final nextMarkers = <Marker>{};
    final nextPolylines = <Polyline>{};

    if (_pos != null) {
      final vt = _profile?.vehicleType ?? 'auto';
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('driver'),
          position: LatLng(_pos!.latitude, _pos!.longitude),
          icon: _mapVehicleIcon(vt) ??
              BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueYellow,
              ),
          infoWindow: const InfoWindow(title: 'Your vehicle'),
        ),
      );
    }

    if (_activeBooking == null && _isOnline) {
      for (final o in _openNearby) {
        final lat = (o['pickupLat'] as num?)?.toDouble();
        final lng = (o['pickupLng'] as num?)?.toDouble();
        final id = o['id']?.toString() ?? '';
        final vt = o['vehicleType']?.toString() ?? 'auto';
        if (lat == null || lng == null || id.isEmpty) continue;
        nextMarkers.add(
          Marker(
            markerId: MarkerId('open_$id'),
            position: LatLng(lat, lng),
            icon: _mapVehicleIcon(vt) ??
                BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueOrange,
                ),
            infoWindow: InfoWindow(
              title: 'Open · ${o['bookingId'] ?? ''}',
              snippet: (o['pickupAddress'] ?? '').toString(),
            ),
            onTap: () => _showOfferBookingDialog(o),
          ),
        );
      }
    }

    final booking = _activeBooking;
    final pickup = booking?.pickup;
    final dropoff = booking?.dropoff;
    final pickupLatLng =
        pickup != null && pickup.latitude != 0 && pickup.longitude != 0
            ? LatLng(pickup.latitude, pickup.longitude)
            : null;
    final dropLatLng =
        dropoff != null && dropoff.latitude != 0 && dropoff.longitude != 0
            ? LatLng(dropoff.latitude, dropoff.longitude)
            : null;

    if (pickupLatLng != null) {
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickupLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(title: 'Pickup', snippet: pickup!.address),
        ),
      );
    }

    if (dropLatLng != null) {
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: dropLatLng,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(title: 'Drop-off', snippet: dropoff!.address),
        ),
      );
    }

    if (_customerLatLng != null) {
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('customer-live'),
          position: _customerLatLng!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Customer live location'),
        ),
      );
    }

    if (pickupLatLng != null && dropLatLng != null) {
      _ensureTripRoutePath(pickupLatLng, dropLatLng);
      nextPolylines.add(
        Polyline(
          polylineId: const PolylineId('trip-route'),
          points: _tripRoutePath.length >= 2 ? _tripRoutePath : [pickupLatLng, dropLatLng],
          width: 5,
          color: AppColors.primary,
          geodesic: true,
        ),
      );
    }

    final liveTarget =
        booking?.isInProgress == true ? dropLatLng : pickupLatLng;
    if (_pos != null && liveTarget != null) {
      nextPolylines.add(
        Polyline(
          polylineId: const PolylineId('driver-progress'),
          points: [LatLng(_pos!.latitude, _pos!.longitude), liveTarget],
          width: 4,
          color: AppColors.warning,
          patterns: [PatternItem.dash(24), PatternItem.gap(12)],
        ),
      );
    }

    if (_customerLatLng != null &&
        _pos != null &&
        booking?.isAccepted == true) {
      nextPolylines.add(
        Polyline(
          polylineId: const PolylineId('customer-sync'),
          points: [LatLng(_pos!.latitude, _pos!.longitude), _customerLatLng!],
          width: 3,
          color: AppColors.info,
          patterns: [PatternItem.dot, PatternItem.gap(14)],
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
        if (pickupLatLng != null) pickupLatLng,
        if (dropLatLng != null) dropLatLng,
        if (_customerLatLng != null) _customerLatLng!,
      ]);
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

  void _showOfferBookingDialog(Map<String, dynamic> o) {
    _showRequestDialog({
      'bookingId': o['id'],
      'bookingCode': o['bookingId'],
      'vehicleType': o['vehicleType'],
      'pickup': {'address': o['pickupAddress']},
      'dropoff': {'address': o['dropoffAddress']},
      'estimatedDistance': o['estimatedDistance'],
      'estimatedFare': o['estimatedFare'],
      'driverPayout': o['driverPayout'],
      'platformFee': o['platformFee'],
      'description': o['description'],
    });
  }

  void _showRequestDialog(Map<String, dynamic> data) {
    final bookingId = data['bookingId']?.toString() ?? '';
    final code = data['bookingCode']?.toString() ?? '';
    final vType = data['vehicleType']?.toString() ?? '';
    final v = vehicleByType(vType);
    final pickup =
        (data['pickup'] as Map?)?['address']?.toString() ?? 'Unknown';
    final drop = (data['dropoff'] as Map?)?['address']?.toString() ?? 'Unknown';
    final dist = (data['estimatedDistance'] as num?)?.toDouble() ?? 0;
    final customerFare = (data['estimatedFare'] as num?)?.toInt() ?? 0;
    final driverPayout = (data['driverPayout'] as num?)?.toInt() ??
        (customerFare > 0 ? (customerFare * 0.9).round() : 0);
    final desc = data['description']?.toString() ?? '';

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(v?.emoji ?? '📦', style: const TextStyle(fontSize: 22)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('New Request! 📦',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary)),
                Text(code,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Row('🚛', v?.name.toUpperCase() ?? vType.toUpperCase()),
            _Row('📍', pickup),
            _Row('🏁', drop),
            _Row('📏', '${dist.toStringAsFixed(1)} km'),
            _Row('💰', 'Customer ₹$customerFare · You earn ~₹$driverPayout'),
            if (desc.isNotEmpty) _Row('📝', desc),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await _api.respondToBooking(bookingId, 'reject');
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.danger),
                    foregroundColor: AppColors.danger,
                  ),
                  child: const Text('✕  Reject'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    final ok = await _api.respondToBooking(bookingId, 'accept');
                    if (ok && mounted) {
                      SocketService.instance.joinBooking(bookingId);
                      await _loadProfile();
                      showSnack(context, '✅ Booking accepted!');
                    }
                  },
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success),
                  child: const Text('✓  Accept'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _toggleOnline() async {
    setState(() => _toggleLoading = true);
    try {
      final on = await _api.toggleOnline();
      if (!mounted) return;
      setState(() {
        _isOnline = on;
        if (!on) {
          _openNearby = const [];
        }
      });
      if (!on) {
        _openBookingsPoll?.cancel();
      } else if (_activeBooking == null && _pos != null) {
        _syncOpenBookingsPoll();
      }
      if (on && _pos != null) {
        await _api.updateDriverLocation(_pos!.latitude, _pos!.longitude);
      }
      showSnack(context, on ? '✅ You are ONLINE' : '⭕ You are OFFLINE');
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Failed to toggle', error: true);
      }
    } finally {
      if (mounted) setState(() => _toggleLoading = false);
    }
  }

  Future<void> _startTrip() async {
    if (_activeBooking == null) return;
    try {
      await _api.startTrip(_activeBooking!.id);
      await _loadProfile();
      if (mounted) showSnack(context, '🚀 Trip started!');
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Failed to start trip', error: true);
      }
    }
  }

  Future<void> _completeTrip() async {
    if (_activeBooking == null) return;
    final ok = await _confirmDialog();
    if (!ok) return;
    try {
      await _api.completeTrip(_activeBooking!.id);
      if (!mounted) return;
      setState(() {
        _activeBooking = null;
        _customerPhone = null;
        _tripRoutePath = const [];
        _tripRouteKey = null;
      });
      _refreshMapOverlay(fitCamera: true);
      _syncOpenBookingsPoll();
      showSnack(context, '✅ Trip completed!');
    } on DioException catch (e) {
      if (!mounted) return;
      final msg = (e.response?.data as Map?)?['error']?.toString() ??
          'Failed to complete trip';
      showSnack(context, msg, error: true);
    } catch (_) {
      if (mounted) {
        showSnack(context, 'Failed to complete', error: true);
      }
    }
  }

  Future<bool> _confirmDialog() async {
    final res = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border)),
        title: const Text('Complete Trip?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: const Text('Confirm that the delivery is done?',
            style: TextStyle(color: AppColors.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Yes, Done ✓',
                style: TextStyle(color: AppColors.success)),
          ),
        ],
      ),
    );
    return res == true;
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
                        : 'D',
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
                        user?.name ?? 'Driver',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      Text(
                        _profile?.vehicleNumber ?? user?.phone ?? '',
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
                    color: _isOnline ? AppColors.successBg : AppColors.surface2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _isOnline ? 'Online' : 'Offline',
                    style: TextStyle(
                      color:
                          _isOnline ? AppColors.success : AppColors.textMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            SettingsTile(
              icon: Icons.person_outline,
              title: 'Driver Profile',
              subtitle: 'Vehicle details, approval, and account info',
              onTap: () {
                Navigator.pop(sheetContext);
                context.push(AppRoutes.driverProfile);
              },
            ),
            const SizedBox(height: 10),
            SettingsTile(
              icon: Icons.history_rounded,
              title: 'Trip History',
              subtitle: 'See earnings, completed jobs, and delivery logs',
              onTap: () {
                Navigator.pop(sheetContext);
                context.push(AppRoutes.tripHistory);
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
              subtitle: 'Get help with bookings, payments, or driver issues',
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
              icon: Icons.logout_rounded,
              title: 'Logout',
              subtitle: 'Sign out of the driver account',
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
    _fitMapToVisiblePoints([
      if (_pos != null) LatLng(_pos!.latitude, _pos!.longitude),
      if (_customerLatLng != null) _customerLatLng!,
      for (final o in _openNearby)
        if ((o['pickupLat'] as num?) != null && (o['pickupLng'] as num?) != null)
          LatLng(
            (o['pickupLat'] as num).toDouble(),
            (o['pickupLng'] as num).toDouble(),
          ),
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
    if (_activeBooking == null && _isOnline) {
      return InlineNoticeCard(
        icon: Icons.radar_outlined,
        title: 'Driver is online',
        subtitle: _openNearby.isEmpty
            ? 'Dispatch is live. Nearby open jobs appear on the map and below when customers book.'
            : '${_openNearby.length} open job${_openNearby.length == 1 ? '' : 's'} near you — tap a pin or card to accept.',
        accent: AppColors.success,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final user = SessionManager.instance.getUser();
    final notice = _buildDashboardNotice();
    final mapBottomInset = _activeBooking != null
        ? 284.0
        : (_openNearby.isNotEmpty && _isOnline ? 312.0 : 228.0);
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
                style: SessionManager.instance.nightMapsEnabled.value
                    ? _kMapStyle
                    : null,
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
                      AppColors.background.withValues(alpha: 0.18),
                      Colors.transparent,
                      Colors.transparent,
                      AppColors.background.withValues(alpha: 0.68),
                    ],
                    stops: const [0, 0.18, 0.5, 1],
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
                        child: _DriverDashboardHero(
                          name: user?.name ?? 'Driver',
                          vehicleNumber:
                              _profile?.vehicleNumber ?? 'Vehicle pending',
                          isOnline: _isOnline,
                          loading: _toggleLoading,
                          onToggle: _toggleOnline,
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
                        icon: Icons.local_shipping_outlined,
                        label: _activeBooking != null
                            ? _activeBooking!.statusLabel
                            : _isOnline
                                ? 'Ready for dispatch'
                                : 'Offline',
                        color:
                            _isOnline ? AppColors.success : AppColors.warning,
                        backgroundColor:
                            AppColors.surface.withValues(alpha: 0.9),
                      ),
                      InfoPill(
                        icon: Icons.route_outlined,
                        label: _activeBooking != null
                            ? '${_activeBooking!.estimatedDistance.toStringAsFixed(1)} km trip'
                            : 'Live tracking ready',
                      ),
                      InfoPill(
                        icon: Icons.person_pin_circle_outlined,
                        label: _customerLatLng != null
                            ? 'Customer live location'
                            : _activeBooking != null
                                ? 'Pickup pinned'
                                : 'Waiting for request',
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
                          'If the map stays blank, check the Google Maps API key, billing, enabled SDKs, and app restrictions first.',
                      accent: AppColors.warning,
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_activeBooking == null &&
              _isOnline &&
              _openNearby.isNotEmpty)
            Positioned(
              left: 8,
              right: 8,
              bottom: 210,
              height: 96,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Nearby open bookings',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.6,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _openNearby.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (_, i) {
                          final o = _openNearby[i];
                          final vt = o['vehicleType']?.toString() ?? '';
                          final v = vehicleByType(vt);
                          final customerFare =
                              (o['estimatedFare'] as num?)?.toInt() ?? 0;
                          final earn = (o['driverPayout'] as num?)?.toInt() ??
                              (customerFare > 0
                                  ? (customerFare * 0.9).round()
                                  : 0);
                          final km = (o['distanceKm'] as num?)?.toDouble() ?? 0;
                          return Material(
                            color: AppColors.surface2,
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              onTap: () => _showOfferBookingDialog(o),
                              borderRadius: BorderRadius.circular(14),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(v?.emoji ?? '📦',
                                        style: const TextStyle(fontSize: 22)),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          v?.name ?? vt,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 13,
                                            color: AppColors.textPrimary,
                                          ),
                                        ),
                                        Text(
                                          '${km.toStringAsFixed(1)} km · earn ~₹$earn',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _activeBooking != null
                ? _TripPanel(
                    booking: _activeBooking!,
                    customerPhone: _customerPhone,
                    onStart: _startTrip,
                    onComplete: _completeTrip,
                    canCompleteNearDrop: _canCompleteNearDrop,
                    metersToDrop: _metersToDropOff,
                    maxCompleteDropM: _kCompleteDropMaxM,
                  )
                : _IdlePanel(
                    isOnline: _isOnline,
                    profile: _profile,
                    onHistory: () => context.push(AppRoutes.tripHistory),
                    onProfile: () => context.push(AppRoutes.driverProfile),
                    onToggle: _toggleOnline,
                  ),
          ),
        ],
      ),
    );
  }
}

class _DriverDashboardHero extends StatelessWidget {
  final String name;
  final String vehicleNumber;
  final bool isOnline;
  final bool loading;
  final VoidCallback onToggle;

  const _DriverDashboardHero({
    required this.name,
    required this.vehicleNumber,
    required this.isOnline,
    required this.loading,
    required this.onToggle,
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
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primaryGlow,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : 'D',
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
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  vehicleNumber,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          loading
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                )
              : InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(999),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color:
                          isOnline ? AppColors.successBg : AppColors.surface2,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: isOnline ? AppColors.success : AppColors.border,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: isOnline
                                ? AppColors.success
                                : AppColors.textMuted,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: isOnline
                                ? AppColors.success
                                : AppColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
        ],
      ),
    );
  }
}

// ── Dialog info row ────────────────────────────────────────────────
class _Row extends StatelessWidget {
  final String icon;
  final String label;
  const _Row(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon, style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Idle bottom panel ──────────────────────────────────────────────
class _IdlePanel extends StatelessWidget {
  final bool isOnline;
  final DriverProfile? profile;
  final VoidCallback onHistory;
  final VoidCallback onProfile;
  final VoidCallback onToggle;

  const _IdlePanel({
    required this.isOnline,
    this.profile,
    required this.onHistory,
    required this.onProfile,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return _Sheet(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (profile != null)
          Row(children: [
            _Stat('${profile!.totalTrips}', 'Trips', '🚛'),
            _Stat(profile!.rating.toStringAsFixed(1), 'Rating', '⭐'),
            _Stat(isOnline ? 'Online' : 'Offline', 'Status',
                isOnline ? '🟢' : '⭕'),
          ]),
        const SizedBox(height: 14),
        PrimaryButton(
          label: isOnline ? '⭕   Go Offline' : '✅   Go Online',
          onTap: onToggle,
          color: isOnline ? AppColors.danger : AppColors.success,
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: OutlineBtn(label: '📋 History', onTap: onHistory)),
          const SizedBox(width: 10),
          Expanded(child: OutlineBtn(label: '👤 Profile', onTap: onProfile)),
        ]),
        if (!isOnline) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(children: [
              Text('💡', style: TextStyle(fontSize: 16)),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Go online to start receiving transport requests nearby',
                  style: TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                      height: 1.4),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final String icon;
  const _Stat(this.value, this.label, this.icon);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(children: [
          Text(icon, style: const TextStyle(fontSize: 20)),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

// ── Active trip panel ──────────────────────────────────────────────
class _TripPanel extends StatelessWidget {
  final BookingModel booking;
  final String? customerPhone;
  final VoidCallback onStart;
  final VoidCallback onComplete;
  final bool canCompleteNearDrop;
  final double? metersToDrop;
  final double maxCompleteDropM;

  const _TripPanel({
    required this.booking,
    this.customerPhone,
    required this.onStart,
    required this.onComplete,
    required this.canCompleteNearDrop,
    required this.metersToDrop,
    required this.maxCompleteDropM,
  });

  @override
  Widget build(BuildContext context) {
    final v = vehicleByType(booking.vehicleType);
    return _Sheet(
      borderColor: AppColors.success,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
                child: Text(v?.emoji ?? '📦',
                    style: const TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(booking.statusLabel,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success)),
                Text(
                    '${booking.displayBookingId} · '
                    '${booking.estimatedDistance.toStringAsFixed(1)} km · '
                    'You earn ₹${booking.driverEarnsInr} · customer ₹${booking.customerPaysInr}',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
                if ((booking.customerName?.isNotEmpty ?? false) ||
                    customerPhone != null)
                  Text(
                    [
                      if (booking.customerName?.isNotEmpty ?? false)
                        booking.customerName!,
                      if (customerPhone != null) customerPhone!,
                    ].join(' · '),
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          if (customerPhone != null)
            GestureDetector(
              onTap: () => launchUrl(Uri.parse('tel:$customerPhone')),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.phone, color: AppColors.info, size: 20),
              ),
            ),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Text('📍', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(booking.pickup?.address ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textPrimary)),
                ),
              ]),
              const SizedBox(height: 6),
              Row(children: [
                const Text('🏁', style: TextStyle(fontSize: 13)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(booking.dropoff?.address ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ),
              ]),
            ],
          ),
        ),
        if ((booking.description ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              'Goods: ${booking.description!.trim()}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
        const SizedBox(height: 14),
        if (booking.isAccepted)
          PrimaryButton(
              label: '🚀   Start Trip',
              onTap: onStart,
              color: AppColors.success)
        else if (booking.isInProgress) ...[
          if (!canCompleteNearDrop && metersToDrop != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Move within ${maxCompleteDropM.round()} m of the drop pin to finish (${metersToDrop!.round()} m away).',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.warning,
                  fontWeight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
            ),
          PrimaryButton(
            label: '✅   Complete Trip',
            onTap: canCompleteNearDrop ? onComplete : null,
            color: AppColors.success,
          ),
        ],
      ]),
    );
  }
}

// ── Shared sheet container ─────────────────────────────────────────
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

const _kMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#0d0d0d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#222222"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#0d0d0d"}]}
]''';
