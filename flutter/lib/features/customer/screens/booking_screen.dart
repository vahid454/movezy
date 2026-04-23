import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:dio/dio.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/widgets/widgets.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/data/datasources/api_service.dart';
import 'package:movezy/data/models/models.dart';
import 'package:movezy/services/session_manager.dart';

class BookingScreen extends StatefulWidget {
  const BookingScreen({super.key});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  final _pickupCtrl = TextEditingController();
  final _dropCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  GoogleMapController? _mapCtrl;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  double _pickupLat = 0, _pickupLng = 0;
  double _dropLat = 0, _dropLng = 0;
  VehicleOption _selected = kVehicles[1]; // default: auto
  bool _loading = false;
  bool _resolvingDrop = false;
  double? _distanceKm;
  String? _dropLookupMessage;
  List<NearbyDriver> _nearbyDrivers = const [];
  Timer? _dropDebounce;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _api.setToken(SessionManager.instance.getToken());
    _autoPickup();
  }

  @override
  void dispose() {
    _dropDebounce?.cancel();
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
          _dropLookupMessage = null;
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
    });
    _refreshMapPreview();
    _dropDebounce = Timer(const Duration(milliseconds: 650), () {
      _geocodeDrop();
    });
  }

  void _refreshMapPreview({bool fitCamera = false}) {
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
        ),
      );
    }

    for (final driver in _nearbyDrivers) {
      final lat = driver.latitude;
      final lng = driver.longitude;
      if (lat == null || lng == null || lat == 0 || lng == 0) continue;
      nextMarkers.add(
        Marker(
          markerId: MarkerId('nearby_${driver.id}'),
          position: LatLng(lat, lng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueOrange,
          ),
          infoWindow: InfoWindow(
            title: driver.name.isNotEmpty ? driver.name : 'Nearby driver',
            snippet:
                '${driver.vehicleNumber} · ${driver.rating.toStringAsFixed(1)}★',
          ),
        ),
      );
    }

    if (pickupReady && dropReady) {
      nextPolylines.add(
        Polyline(
          polylineId: const PolylineId('booking-route'),
          points: [
            LatLng(_pickupLat, _pickupLng),
            LatLng(_dropLat, _dropLng),
          ],
          width: 5,
          color: AppColors.primary,
          geodesic: true,
        ),
      );
      _distanceKm = Geolocator.distanceBetween(
            _pickupLat,
            _pickupLng,
            _dropLat,
            _dropLng,
          ) /
          1000;
    } else {
      _distanceKm = null;
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

  Future<void> _loadNearbyDrivers() async {
    if (_pickupLat == 0 && _pickupLng == 0) return;
    try {
      final drivers = await _api.getNearbyDrivers(
        latitude: _pickupLat,
        longitude: _pickupLng,
        vehicleType: _selected.type,
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
    final km = _distanceKm;
    if (km == null) return _selected.baseFare;
    return _selected.estimateFare(km);
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
      context.pop();
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
            // Location card
            MCard(
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
                    padding: EdgeInsets.symmetric(vertical: 8),
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
                      height: 220,
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
                        markers: _markers,
                        polylines: _polylines,
                        myLocationEnabled: _pickupLat != 0 || _pickupLng != 0,
                        myLocationButtonEnabled: false,
                        zoomControlsEnabled: false,
                        mapToolbarEnabled: false,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(
                        icon: Icons.route_outlined,
                        label: _distanceKm != null
                            ? '${_distanceKm!.toStringAsFixed(1)} km route'
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
                        label: '₹${_estimateFare()} estimate',
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
                  ...kVehicles.map(
                    (v) => GestureDetector(
                      onTap: () {
                        setState(() => _selected = v);
                        _loadNearbyDrivers();
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: _selected.type == v.type
                              ? Color(v.colorHex).withValues(alpha: 0.1)
                              : AppColors.surface2,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _selected.type == v.type
                                ? Color(v.colorHex)
                                : AppColors.border,
                            width: _selected.type == v.type ? 1.5 : 1,
                          ),
                        ),
                        child: Row(children: [
                          Text(v.emoji, style: const TextStyle(fontSize: 24)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(v.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.textPrimary,
                                        fontSize: 15)),
                                Text(v.desc,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          Text('₹${v.baseFare}+',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: Color(v.colorHex))),
                          if (_selected.type == v.type) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_circle,
                                color: Color(v.colorHex), size: 18),
                          ],
                        ]),
                      ),
                    ),
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
                  const Text('WHAT ARE YOU MOVING?',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descCtrl,
                    style: const TextStyle(
                        color: AppColors.textPrimary, fontSize: 14),
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'e.g. 2-seater sofa, 3 cartons of books…',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
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
                      ? 'Estimated fare for ${_distanceKm!.toStringAsFixed(1)} km. Final amount can still be confirmed with the driver.'
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.textMuted,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
              TextField(
                controller: ctrl,
                onChanged: onChanged,
                style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500),
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle:
                      const TextStyle(color: AppColors.textMuted, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
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
