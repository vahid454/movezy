import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/core/utils/vehicle_map_icons.dart';
import 'package:movezy/data/datasources/api_service.dart';
import 'package:movezy/data/models/models.dart';
import 'package:movezy/services/session_manager.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

enum _PinSelectionMode { pickup, dropoff }

class _BookingScreenState extends State<BookingScreen> {
  final _pickupCtrl = TextEditingController();
  final _dropCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  GoogleMapController? _mapCtrl;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  List<LatLng> _roadRoutePath = const [];
  String? _routeKey;
  double _pickupLat = 0, _pickupLng = 0;
  double _dropLat = 0, _dropLng = 0;
  VehicleOption _selected = kVehicles[1]; // default: auto
  bool _loading = false;
  bool _resolvingDrop = false;
  bool _loadingFareQuote = false;
  double? _distanceKm;
  int? _serverEstimatedFare;
  int? _quotePlatformFee;
  int? _quoteDriverPayout;
  String? _dropLookupMessage;
  List<NearbyDriver> _nearbyDrivers = const [];
  Timer? _dropDebounce;
  Timer? _routeRebuildDebounce;
  int _fareQuoteGeneration = 0;
  bool _resolvingRoadRoute = false;
  final _api = ApiService();
  _PinSelectionMode _pinMode = _PinSelectionMode.dropoff;
  Map<String, BitmapDescriptor> _vehicleBmps = {};

  double get _effectiveDistanceKm => _distanceKm ?? 0;

  @override
  void initState() {
    super.initState();
    _api.setToken(SessionManager.instance.getToken());
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVehicleMapIcons());
    _autoPickup();
  }

  Future<void> _loadVehicleMapIcons() async {
    try {
      await VehicleMapIcons.preloadAll();
      final m = <String, BitmapDescriptor>{};
      for (final v in kVehicles) {
        m[v.type] = await VehicleMapIcons.forVehicleType(v.type);
      }
      if (mounted) {
        setState(() => _vehicleBmps = m);
        _refreshMapPreview();
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _dropDebounce?.cancel();
    _routeRebuildDebounce?.cancel();
    _pickupCtrl.dispose();
    _dropCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _autoPickup() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _pickupLat = pos.latitude;
      _pickupLng = pos.longitude;
      final places =
          await placemarkFromCoordinates(pos.latitude, pos.longitude);
      final p = places.first;
      final addr = [p.thoroughfare, p.subLocality, p.locality]
          .where((e) => e?.isNotEmpty == true)
          .join(', ');
      if (mounted) {
        setState(() {
          _pickupCtrl.text = addr.isNotEmpty
              ? addr
              : '${pos.latitude.toStringAsFixed(5)}, '
                  '${pos.longitude.toStringAsFixed(5)}';
          _pinMode = _PinSelectionMode.dropoff;
        });
        _refreshMapPreview(fitCamera: true);
        _loadNearbyDrivers();
      }
    } catch (_) {}
  }

  Future<bool> _geocodeDrop({bool showError = false}) async {
    final query = _dropCtrl.text.trim();
    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _dropLat = 0;
          _dropLng = 0;
          _distanceKm = null;
          _serverEstimatedFare = null;
          _quotePlatformFee = null;
          _quoteDriverPayout = null;
          _dropLookupMessage = null;
          _roadRoutePath = const [];
          _routeKey = null;
        });
        _refreshMapPreview();
      }
      return false;
    }

    if (mounted) {
      setState(() {
        _resolvingDrop = true;
        _dropLookupMessage = null;
      });
    }
    try {
      final locs = await locationFromAddress(query);
      if (locs.isNotEmpty) {
        if (!mounted) return true;
        setState(() {
          _dropLat = locs.first.latitude;
          _dropLng = locs.first.longitude;
          _dropLookupMessage = null;
        });
        _refreshMapPreview(fitCamera: true);
        return true;
      }
    } catch (_) {
      if (showError && mounted) {
        showSnack(context, 'Unable to find that drop location', error: true);
      }
    } finally {
      if (mounted) {
        setState(() => _resolvingDrop = false);
      }
    }

    if (mounted) {
      setState(() {
        _dropLat = 0;
        _dropLng = 0;
        _distanceKm = null;
        _serverEstimatedFare = null;
        _quotePlatformFee = null;
        _quoteDriverPayout = null;
        _dropLookupMessage = 'Enter a more specific drop address';
      });
      _refreshMapPreview();
    }
    return false;
  }

  void _scheduleDropLookup(String _) {
    _dropDebounce?.cancel();
    setState(() {
      _dropLookupMessage = null;
      _dropLat = 0;
      _dropLng = 0;
      _distanceKm = null;
      _serverEstimatedFare = null;
      _quotePlatformFee = null;
      _quoteDriverPayout = null;
      _roadRoutePath = const [];
      _routeKey = null;
    });
    _refreshMapPreview();
    _dropDebounce = Timer(const Duration(milliseconds: 520), () {
      _geocodeDrop();
    });
  }

  void _refreshMapPreview({
    bool fitCamera = false,
    bool scheduleRoute = true,
  }) {
    final nextMarkers = <Marker>{};
    final nextPolylines = <Polyline>{};

    final pickupReady = _pickupLat != 0 || _pickupLng != 0;
    final dropReady = _dropLat != 0 || _dropLng != 0;

    if (pickupReady) {
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(_pickupLat, _pickupLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: InfoWindow(
            title: 'Pickup',
            snippet: _pickupCtrl.text.trim(),
          ),
          draggable: true,
          onDrag: (LatLng p) {
            setState(() {
              _pickupLat = p.latitude;
              _pickupLng = p.longitude;
            });
            _scheduleRouteRebuild();
          },
          onDragEnd: (latLng) => unawaited(_finalizePickupDrag(latLng)),
        ),
      );
    }

    if (dropReady) {
      nextMarkers.add(
        Marker(
          markerId: const MarkerId('dropoff'),
          position: LatLng(_dropLat, _dropLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: 'Drop-off',
            snippet: _dropCtrl.text.trim(),
          ),
          draggable: true,
          onDrag: (LatLng p) {
            setState(() {
              _dropLat = p.latitude;
              _dropLng = p.longitude;
            });
            _scheduleRouteRebuild();
          },
          onDragEnd: (latLng) => unawaited(_finalizeDropDrag(latLng)),
        ),
      );
    }

    for (final driver in _nearbyDrivers) {
      final lat = driver.latitude;
      final lng = driver.longitude;
      if (lat == null || lng == null || lat == 0 || lng == 0) continue;
      final vLabel = vehicleByType(driver.vehicleType)?.name ??
          driver.vehicleType.replaceAll('_', ' ');
      nextMarkers.add(
        Marker(
          markerId: MarkerId('nearby_${driver.id}'),
          position: LatLng(lat, lng),
          icon: _vehicleBmps[driver.vehicleType] ??
              BitmapDescriptor.defaultMarkerWithHue(
                  _markerHueForVehicle(driver.vehicleType)),
          infoWindow: InfoWindow(
            title: '${vLabel.toUpperCase()} · ${driver.vehicleNumber}',
            snippet: driver.name.isNotEmpty
                ? '${driver.name} · tap for details'
                : 'Tap pin for driver details',
          ),
          onTap: () => showNearbyDriverPeekSheet(context, driver),
        ),
      );
    }

    if (pickupReady && dropReady) {
      if (scheduleRoute) _scheduleRouteRebuild();
      if (_roadRoutePath.length >= 2) {
        nextPolylines.add(
          Polyline(
            polylineId: const PolylineId('booking-route'),
            points: _roadRoutePath,
            width: 5,
            color: AppColors.primary,
            geodesic: true,
          ),
        );
      }
      if (_serverEstimatedFare == null) {
        _distanceKm = Geolocator.distanceBetween(
              _pickupLat,
              _pickupLng,
              _dropLat,
              _dropLng,
            ) /
            1000;
      }
    } else {
      _distanceKm = null;
      _serverEstimatedFare = null;
      _quotePlatformFee = null;
      _quoteDriverPayout = null;
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
        if (pickupReady) LatLng(_pickupLat, _pickupLng),
        if (dropReady) LatLng(_dropLat, _dropLng),
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

  void _scheduleRouteRebuild() {
    if (!(_pickupLat != 0 || _pickupLng != 0) ||
        !(_dropLat != 0 || _dropLng != 0)) {
      return;
    }
    _routeRebuildDebounce?.cancel();
    _routeRebuildDebounce = Timer(const Duration(milliseconds: 240), () {
      if (!mounted) return;
      unawaited(_resolveRoadRouteAndFare());
    });
  }

  Future<void> _resolveRoadRouteAndFare() async {
    await Future.wait([
      _ensureRoadRoutePath(),
      _fetchFareQuote(),
    ]);
    if (!mounted) return;
    _refreshMapPreview(scheduleRoute: false);
  }

  Future<void> _finalizePickupDrag(LatLng latLng) async {
    setState(() {
      _pickupLat = latLng.latitude;
      _pickupLng = latLng.longitude;
    });
    final address = await _reverseGeocode(latLng);
    if (!mounted) return;
    setState(() => _pickupCtrl.text = address);
    await _loadNearbyDrivers();
    _scheduleRouteRebuild();
    _refreshMapPreview(fitCamera: false, scheduleRoute: false);
  }

  Future<void> _finalizeDropDrag(LatLng latLng) async {
    setState(() {
      _dropLat = latLng.latitude;
      _dropLng = latLng.longitude;
      _dropLookupMessage = null;
    });
    final address = await _reverseGeocode(latLng);
    if (!mounted) return;
    setState(() => _dropCtrl.text = address);
    _scheduleRouteRebuild();
    _refreshMapPreview(fitCamera: false, scheduleRoute: false);
  }

  void _onMapTapped(LatLng latLng) {
    if (_pinMode == _PinSelectionMode.pickup) {
      unawaited(_setPickupFromMap(latLng));
      return;
    }
    unawaited(_setDropFromMap(latLng));
  }

  Future<void> _setPickupFromMap(LatLng latLng) async {
    setState(() {
      _pickupLat = latLng.latitude;
      _pickupLng = latLng.longitude;
    });
    _refreshMapPreview(fitCamera: true);
    final address = await _reverseGeocode(latLng);
    if (!mounted) return;
    setState(() => _pickupCtrl.text = address);
    await _loadNearbyDrivers();
    _refreshMapPreview(fitCamera: false);
  }

  Future<void> _setDropFromMap(LatLng latLng) async {
    setState(() {
      _dropLat = latLng.latitude;
      _dropLng = latLng.longitude;
      _dropLookupMessage = null;
    });
    _refreshMapPreview(fitCamera: true);
    final address = await _reverseGeocode(latLng);
    if (!mounted) return;
    setState(() => _dropCtrl.text = address);
    _refreshMapPreview(fitCamera: false);
  }

  Future<String> _reverseGeocode(LatLng latLng) async {
    try {
      final places =
          await placemarkFromCoordinates(latLng.latitude, latLng.longitude);
      if (places.isEmpty) {
        return '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
      }
      final place = places.first;
      final address = [
        place.name,
        place.thoroughfare,
        place.subLocality,
        place.locality
      ].where((part) => part?.trim().isNotEmpty == true).join(', ');
      if (address.isNotEmpty) return address;
    } catch (_) {}
    return '${latLng.latitude.toStringAsFixed(5)}, ${latLng.longitude.toStringAsFixed(5)}';
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

  Future<void> _ensureRoadRoutePath() async {
    if (!(_pickupLat != 0 || _pickupLng != 0) ||
        !(_dropLat != 0 || _dropLng != 0)) {
      return;
    }
    final routeKey =
        '${_pickupLat.toStringAsFixed(5)},${_pickupLng.toStringAsFixed(5)}:${_dropLat.toStringAsFixed(5)},${_dropLng.toStringAsFixed(5)}';
    if (_routeKey == routeKey && _roadRoutePath.isNotEmpty) return;

    _routeKey = routeKey;
    if (mounted) {
      setState(() => _resolvingRoadRoute = true);
    }
    try {
      final routeCoordinates = await _api.getRoutePath(
        originLat: _pickupLat,
        originLng: _pickupLng,
        destinationLat: _dropLat,
        destinationLng: _dropLng,
      );
      if (!mounted || _routeKey != routeKey) return;

      final routePath = routeCoordinates
          .map((coordinate) => LatLng(coordinate[0], coordinate[1]))
          .toList();
      if (!mounted) return;
      setState(() {
        _roadRoutePath = routePath.length >= 2 ? routePath : const [];
      });
    } catch (_) {
      if (!mounted || _routeKey != routeKey) return;
      setState(() => _roadRoutePath = const []);
    } finally {
      if (mounted) {
        setState(() => _resolvingRoadRoute = false);
      }
    }
  }

  Future<void> _loadNearbyDrivers() async {
    if (_pickupLat == 0 && _pickupLng == 0) return;
    try {
      final drivers = await _api.getNearbyDrivers(
        latitude: _pickupLat,
        longitude: _pickupLng,
      );
      if (!mounted) return;
      setState(() => _nearbyDrivers = drivers);
      _refreshMapPreview();
    } catch (_) {}
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

  int _estimateFare() {
    if (_serverEstimatedFare != null) return _serverEstimatedFare!;
    final km = _distanceKm;
    if (km == null) return _selected.baseFare;
    return _selected.estimateFare(km);
  }

  Future<void> _fetchFareQuote() async {
    if (_pickupLat == 0 || _pickupLng == 0 || _dropLat == 0 || _dropLng == 0) {
      return;
    }
    final gen = ++_fareQuoteGeneration;
    if (mounted) setState(() => _loadingFareQuote = true);
    try {
      final quote = await _api.getFareQuote(
        originLat: _pickupLat,
        originLng: _pickupLng,
        destinationLat: _dropLat,
        destinationLng: _dropLng,
        vehicleType: _selected.type,
      );
      if (!mounted || gen != _fareQuoteGeneration) return;
      setState(() {
        _serverEstimatedFare = (quote['estimatedFare'] as num?)?.toInt();
        _quotePlatformFee = (quote['platformFee'] as num?)?.toInt();
        _quoteDriverPayout = (quote['driverPayout'] as num?)?.toInt();
        _distanceKm =
            (quote['estimatedDistance'] as num?)?.toDouble() ?? _distanceKm;
      });
    } catch (_) {
      // fallback to local estimate
    } finally {
      if (mounted && gen == _fareQuoteGeneration) {
        setState(() => _loadingFareQuote = false);
      }
    }
  }

  Future<bool> _confirmBooking() async {
    final fee = _estimateFare();
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
              side: const BorderSide(color: AppColors.border),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            contentPadding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
            title: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.primaryGlow,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.local_shipping_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Confirm booking')),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _ConfirmFareLine(label: 'Vehicle', value: _selected.name),
                _ConfirmFareLine(
                    label: 'Route',
                    value: _distanceKm == null
                        ? 'Pins selected'
                        : '${_distanceKm!.toStringAsFixed(1)} km'),
                _ConfirmFareLine(
                    label: 'You pay', value: '₹$fee', strong: true),
                if (_quotePlatformFee != null &&
                    _quoteDriverPayout != null) ...[
                  const Divider(height: 20, color: AppColors.border),
                  _ConfirmFareLine(
                      label: 'Movezy service fee',
                      value: '₹$_quotePlatformFee'),
                  _ConfirmFareLine(
                      label: 'Driver earns approx.',
                      value: '₹$_quoteDriverPayout'),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Fare and commission are locked by the server when this booking is created.',
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.35,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Confirm'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _book() async {
    if (_pickupCtrl.text.trim().isEmpty) {
      showSnack(context, 'Enter pickup location', error: true);
      return;
    }
    if (_dropCtrl.text.trim().isEmpty) {
      showSnack(context, 'Enter drop-off location', error: true);
      return;
    }
    if (_pickupLat == 0) {
      showSnack(context, 'Enable location permission', error: true);
      return;
    }
    final resolved = await _geocodeDrop(showError: true);
    if (!resolved || _dropLat == 0 && _dropLng == 0) {
      return;
    }
    final confirmed = await _confirmBooking();
    if (!confirmed) return;
    setState(() => _loading = true);
    try {
      final booking = await _api.createBooking(
        vehicleType: _selected.type,
        pickupAddress: _pickupCtrl.text.trim(),
        pickupLat: _pickupLat,
        pickupLng: _pickupLng,
        dropAddress: _dropCtrl.text.trim(),
        dropLat: _dropLat,
        dropLng: _dropLng,
        description:
            _descCtrl.text.trim().isEmpty ? null : _descCtrl.text.trim(),
      );
      if (!mounted) return;
      showSnack(
        context,
        '✅ Booking ${booking.displayBookingId} created! Finding drivers…',
      );
      if (!mounted) return;
      context.go(AppRoutes.customerHome);
    } on DioException catch (e) {
      if (!mounted) return;
      final msg =
          (e.response?.data as Map?)?['error']?.toString() ?? 'Booking failed';
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
      appBar: AppBar(
        title: const Text('Book Transport'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, size: 18),
          onPressed: () => context.pop(),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primaryGlow,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '₹${_estimateFare()}+',
              style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MCard(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _LocRow(
                    emoji: '🟢',
                    label: 'PICKUP',
                    ctrl: _pickupCtrl,
                    hint: 'Current location',
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: MDivider(),
                  ),
                  _LocRow(
                    emoji: '🔴',
                    label: 'DROP-OFF',
                    ctrl: _dropCtrl,
                    hint: 'Enter destination',
                    onChanged: _scheduleDropLookup,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            MCard(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'TRIP PREVIEW',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      if (_resolvingDrop)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: SizedBox(
                      height: (MediaQuery.sizeOf(context).height * 0.41)
                          .clamp(292.0, 480.0),
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(
                            _pickupLat != 0 ? _pickupLat : 20.5937,
                            _pickupLng != 0 ? _pickupLng : 78.9629,
                          ),
                          zoom: AppConstants.defaultZoom,
                        ),
                        onMapCreated: (controller) {
                          _mapCtrl = controller;
                          _refreshMapPreview(fitCamera: true);
                        },
                        style: SessionManager.instance.nightMapsEnabled.value
                            ? _kMapStyle
                            : null,
                        onTap: _onMapTapped,
                        markers: _markers,
                        polylines: _polylines,
                        myLocationEnabled: _pickupLat != 0 || _pickupLng != 0,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                        gestureRecognizers: {
                          Factory<OneSequenceGestureRecognizer>(
                            () => EagerGestureRecognizer(),
                          ),
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _MapPinModeChip(
                          selected: _pinMode == _PinSelectionMode.pickup,
                          icon: Icons.trip_origin,
                          label: 'Set pickup pin',
                          onTap: () => setState(
                              () => _pinMode = _PinSelectionMode.pickup),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _MapPinModeChip(
                          selected: _pinMode == _PinSelectionMode.dropoff,
                          icon: Icons.place_outlined,
                          label: 'Set drop pin',
                          onTap: () => setState(
                              () => _pinMode = _PinSelectionMode.dropoff),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.route_outlined,
                        label: _resolvingRoadRoute && _roadRoutePath.length < 2
                            ? 'Drawing road route…'
                            : _distanceKm != null
                                ? '${_distanceKm!.toStringAsFixed(1)} km · road path'
                                : 'Add drop-off to preview route',
                      ),
                      _InfoChip(
                        icon: Icons.local_shipping_outlined,
                        label: '${_selected.name} selected',
                      ),
                      _InfoChip(
                        icon: Icons.radar_outlined,
                        label: _nearbyDrivers.isEmpty
                            ? 'No nearby ${_selected.name.toLowerCase()} visible yet'
                            : '${_nearbyDrivers.length} nearby ${_selected.name.toLowerCase()} drivers',
                      ),
                      _InfoChip(
                        icon: Icons.currency_rupee,
                        label: _loadingFareQuote
                            ? 'Fetching live fare...'
                            : '₹${_estimateFare()} estimate',
                      ),
                    ],
                  ),
                  if (_dropLookupMessage != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _dropLookupMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Vehicle selector
            MCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Expanded(
                      child: Text('SELECT VEHICLE',
                          style: TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8)),
                    ),
                    Text(
                      '₹${_estimateFare()}+',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: AppColors.primary),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: kVehicles.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final v = kVehicles[i];
                      final isSelected = _selected.type == v.type;
                      return GestureDetector(
                        onTap: () {
                          setState(() {
                            _selected = v;
                            _serverEstimatedFare = null;
                            _quotePlatformFee = null;
                            _quoteDriverPayout = null;
                          });
                          _loadNearbyDrivers();
                          _fetchFareQuote();
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? Color(v.colorHex).withValues(alpha: 0.12)
                                : AppColors.surface2,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected
                                  ? Color(v.colorHex)
                                  : AppColors.border,
                              width: isSelected ? 1.6 : 1,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text(v.emoji,
                                  style: const TextStyle(fontSize: 28)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      v.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${v.desc} · ${v.capacity}',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    Text(
                                      v.suitableFor,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  if (isSelected)
                                    Icon(Icons.check_circle,
                                        color: Color(v.colorHex), size: 20)
                                  else
                                    const SizedBox(height: 20),
                                  Text(
                                    _distanceKm != null
                                        ? '₹${v.estimateFare(_effectiveDistanceKm)}'
                                        : '₹${v.baseFare}+',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                      color: Color(v.colorHex),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _FareBreakupCard(
                    selectedVehicle: _selected,
                    distanceKm: _distanceKm,
                    serverTotal: _serverEstimatedFare,
                    serverPlatformFee: _quotePlatformFee,
                    serverDriverPayout: _quoteDriverPayout,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Description
            MCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'WHAT ARE YOU MOVING?',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descCtrl,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      height: 1.4,
                    ),
                    minLines: 3,
                    maxLines: 6,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: InputDecoration(
                      hintText:
                          'e.g. 2-seater sofa, 3 cartons of books, fridge…',
                      hintMaxLines: 3,
                      hintStyle: TextStyle(
                        color: AppColors.textMuted.withValues(alpha: 0.9),
                        fontSize: 13,
                        height: 1.35,
                      ),
                      filled: true,
                      fillColor: AppColors.surface2,
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: AppColors.border),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.5,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Icon(Icons.info_outline,
                  size: 13, color: AppColors.textMuted),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _distanceKm != null
                      ? (_serverEstimatedFare != null
                          ? 'Fare is server quoted for ${_distanceKm!.toStringAsFixed(1)} km between selected pins. Your confirmed booking stores this fare and commission split.'
                          : 'Estimated fare for ${_distanceKm!.toStringAsFixed(1)} km. The server recalculates and locks the final amount when you book.')
                      : 'Add a clear drop-off address to calculate distance and route before booking.',
                  style:
                      const TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
              ),
            ]),
            const SizedBox(height: 24),
            PrimaryButton(
                label: '📦   Confirm Booking', onTap: _book, loading: _loading),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final maxW = (MediaQuery.sizeOf(context).width - 56).clamp(140.0, 320.0);
    return Container(
      constraints: BoxConstraints(maxWidth: maxW),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConfirmFareLine extends StatelessWidget {
  final String label;
  final String value;
  final bool strong;

  const _ConfirmFareLine({
    required this.label,
    required this.value,
    this.strong = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: strong ? 18 : 13,
              color: strong ? AppColors.primary : AppColors.textPrimary,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LocRow extends StatelessWidget {
  final String emoji;
  final String label;
  final TextEditingController ctrl;
  final String hint;
  final ValueChanged<String>? onChanged;

  const _LocRow({
    required this.emoji,
    required this.label,
    required this.ctrl,
    required this.hint,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textMuted,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          onChanged: onChanged,
          minLines: 1,
          maxLines: 2,
          keyboardType: TextInputType.streetAddress,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.newline,
          scrollPhysics: const BouncingScrollPhysics(),
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w500,
            height: 1.35,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintMaxLines: 2,
            hintStyle: TextStyle(
              color: AppColors.textMuted.withValues(alpha: 0.9),
              fontSize: 13,
              height: 1.35,
            ),
            filled: true,
            fillColor: AppColors.surface2,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
          ),
        ),
      ],
    );
  }
}

const _kMapStyle = '''[
  {"elementType":"geometry","stylers":[{"color":"#0d0d0d"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#746855"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#242f3e"}]},
  {"featureType":"road","elementType":"geometry","stylers":[{"color":"#1a1a1a"}]},
  {"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#222222"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#17263c"}]},
  {"featureType":"poi","elementType":"geometry","stylers":[{"color":"#0d0d0d"}]}
]''';

class _MapPinModeChip extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MapPinModeChip({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primaryGlow : AppColors.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 14,
                color: selected ? AppColors.primary : AppColors.textSecondary),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Splits the platform slice into credible line items (display only; sums to [platformInr]).
List<Widget> _farePlatformCategoryRows(int platformInr) {
  if (platformInr <= 0) return [];
  final maps = (platformInr * 0.40).round();
  final support = (platformInr * 0.32).round();
  final ops = platformInr - maps - support;
  return [
    _FareRow(label: 'Maps, traffic & live GPS routing', value: maps),
    _FareRow(label: 'Help desk & trip safeguards', value: support),
    _FareRow(label: 'Partner ops, compliance & billing', value: ops),
  ];
}

class _FareBreakupCard extends StatelessWidget {
  final VehicleOption selectedVehicle;
  final double? distanceKm;
  final int? serverTotal;
  final int? serverPlatformFee;
  final int? serverDriverPayout;

  const _FareBreakupCard({
    required this.selectedVehicle,
    required this.distanceKm,
    this.serverTotal,
    this.serverPlatformFee,
    this.serverDriverPayout,
  });

  @override
  Widget build(BuildContext context) {
    final distance = distanceKm ?? 0;
    final baseDistanceFare =
        selectedVehicle.baseFare + (selectedVehicle.perKm * distance);
    final longDistanceSurcharge =
        distance > 10 ? (distance - 10) * (selectedVehicle.perKm * 0.2) : 0;
    const bookingFee = 10;
    final currentHour = DateTime.now().hour;
    final isPeakHour = (currentHour >= 8 && currentHour <= 11) ||
        (currentHour >= 17 && currentHour <= 21);
    final peakMultiplier = isPeakHour ? 1.2 : 1.0;
    final subtotal = baseDistanceFare + longDistanceSurcharge + bookingFee;
    final totalFare = (subtotal * peakMultiplier).round();
    final localEstimate = totalFare < selectedVehicle.minFare
        ? selectedVehicle.minFare
        : totalFare;

    final useServer = serverTotal != null;
    final titleAmount = useServer ? serverTotal! : localEstimate;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          iconColor: AppColors.primary,
          collapsedIconColor: AppColors.textSecondary,
          title: Text(
            useServer
                ? 'Fare breakup (you pay ₹$titleAmount)'
                : 'Fare breakup (₹$titleAmount est.)',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          subtitle: Text(
            distanceKm == null
                ? 'Set drop pin for precise fare'
                : '${distance.toStringAsFixed(1)} km · ${selectedVehicle.name}'
                    '${useServer ? ' · priced on route pins' : ''}',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
          children: useServer &&
                  serverPlatformFee != null &&
                  serverDriverPayout != null
              ? [
                  _FareRow(label: 'You pay (total)', value: serverTotal!),
                  ..._farePlatformCategoryRows(serverPlatformFee!),
                  _FareRow(
                    label: 'Partner driver (this trip)',
                    value: serverDriverPayout!,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Movezy share on this ride is ₹${serverPlatformFee!} across the items above. Fare is locked from pin-to-pin distance when you confirm.',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textMuted,
                        height: 1.35,
                      ),
                    ),
                  ),
                ]
              : useServer
                  ? [
                      _FareRow(label: 'You pay (total)', value: serverTotal!),
                      _FareRow(
                        label: 'Driver earns (approx.)',
                        value:
                            serverDriverPayout ?? (serverTotal! * 0.9).round(),
                      ),
                    ]
                  : [
                      _FareRow(
                          label: 'Base fare', value: selectedVehicle.baseFare),
                      _FareRow(
                          label: 'Distance charge',
                          value: (selectedVehicle.perKm * distance).round()),
                      _FareRow(
                          label: 'Long distance surcharge',
                          value: longDistanceSurcharge.round()),
                      _FareRow(label: 'Platform fee', value: bookingFee),
                      _FareRow(
                          label: isPeakHour
                              ? 'After peak multiplier (1.2x)'
                              : 'After peak multiplier (1.0x)',
                          value: (subtotal * peakMultiplier).round()),
                      _FareRow(
                          label: 'Minimum fare floor',
                          value: selectedVehicle.minFare,
                          muted: true),
                    ],
        ),
      ),
    );
  }
}

class _FareRow extends StatelessWidget {
  final String label;
  final int value;
  final bool muted;

  const _FareRow({
    required this.label,
    required this.value,
    this.muted = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: muted ? AppColors.textMuted : AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          ),
          Text(
            '₹$value',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
