import 'dart:io';
import 'package:dio/dio.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/data/models/models.dart';

class ApiService {
  final Dio _dio;

  ApiService()
      : _dio = Dio(BaseOptions(
          baseUrl: AppConstants.baseUrl,
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        )) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (opts, handler) {
          final token = _token;
          if (token != null) {
            opts.headers['Authorization'] = 'Bearer $token';
          }
          handler.next(opts);
        },
      ),
    );
  }

  String? _token;
  void setToken(String? t) => _token = t;

  // ── AUTH ──────────────────────────────────────────────────────

  @Deprecated('Use Firebase PhoneAuthService + exchangeFirebaseToken instead')
  Future<Map<String, dynamic>> sendOtp(String phone) async {
    final r = await _dio.post('/auth/send-otp', data: {'phone': phone});
    return r.data as Map<String, dynamic>;
  }

  @Deprecated('Use Firebase PhoneAuthService + exchangeFirebaseToken instead')
  Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
    String? name,
    String? fcmToken,
    bool isDriver = false,
  }) async {
    final endpoint = isDriver ? '/auth/driver-verify-otp' : '/auth/verify-otp';
    final r = await _dio.post(endpoint, data: {
      'phone': phone,
      'otp': otp,
      if (name != null) 'name': name,
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> exchangeFirebaseToken({
    required String idToken,
    required bool isDriver,
    String? name,
    String? fcmToken,
  }) async {
    final r = await _dio.post('/auth/firebase-exchange', data: {
      'idToken': idToken,
      'isDriver': isDriver,
      if (name != null) 'name': name,
      if (fcmToken != null) 'fcmToken': fcmToken,
    });
    return r.data as Map<String, dynamic>;
  }

  // ── DRIVER REGISTER ──────────────────────────────────────────

  Future<Map<String, dynamic>> registerDriver({
    required String name,
    required String phone,
    required String license,
    required String vehicleNumber,
    required String vehicleType,
    String? vehicleModel,
    File? licenseImage,
    File? vehicleRC,
    File? insurance,
    File? profilePhoto,
  }) async {
    final form = FormData.fromMap({
      'name': name,
      'phone': phone,
      'drivingLicense': license,
      'vehicleNumber': vehicleNumber,
      'vehicleType': vehicleType,
      if (vehicleModel != null) 'vehicleModel': vehicleModel,
      if (licenseImage != null)
        'licenseImage': await MultipartFile.fromFile(licenseImage.path,
            filename: 'license.jpg'),
      if (vehicleRC != null)
        'vehicleRC':
            await MultipartFile.fromFile(vehicleRC.path, filename: 'rc.jpg'),
      if (insurance != null)
        'insurance': await MultipartFile.fromFile(insurance.path,
            filename: 'insurance.jpg'),
      if (profilePhoto != null)
        'profilePhoto': await MultipartFile.fromFile(profilePhoto.path,
            filename: 'profile.jpg'),
    });
    final r = await _dio.post('/driver/register', data: form);
    return r.data as Map<String, dynamic>;
  }

  // ── DRIVER ───────────────────────────────────────────────────

  Future<DriverProfile> getDriverProfile() async {
    final r = await _dio.get('/driver/profile');
    final data = r.data as Map<String, dynamic>;
    return DriverProfile.fromJson(data['driver'] as Map<String, dynamic>);
  }

  Future<bool> toggleOnline() async {
    final r = await _dio.put('/driver/toggle-online');
    final data = r.data as Map<String, dynamic>;
    return data['isOnline'] == true;
  }

  Future<void> updateDriverLocation(double lat, double lng) async {
    await _dio.put('/driver/update-location',
        data: {'latitude': lat, 'longitude': lng});
  }

  /// Open `searching` bookings near driver (two-way discovery).
  Future<List<Map<String, dynamic>>> getDriverNearbyOpenBookings({
    required double latitude,
    required double longitude,
    double maxKm = 18,
  }) async {
    final r = await _dio.get('/driver/nearby-open-bookings', queryParameters: {
      'latitude': latitude,
      'longitude': longitude,
      'maxKm': maxKm,
    });
    final data = r.data as Map<String, dynamic>;
    final list = data['bookings'] as List? ?? [];
    return list.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  Future<bool> respondToBooking(String bookingId, String action) async {
    final r = await _dio.post('/driver/respond-booking',
        data: {'bookingId': bookingId, 'action': action});
    final data = r.data as Map<String, dynamic>;
    return data['success'] == true;
  }

  Future<void> startTrip(String bookingId) async {
    await _dio.post('/driver/start-trip', data: {'bookingId': bookingId});
  }

  Future<void> completeTrip(String bookingId) async {
    await _dio.post('/driver/complete-trip', data: {'bookingId': bookingId});
  }

  Future<List<BookingModel>> getDriverTripHistory() async {
    final r = await _dio.get('/driver/trip-history');
    final data = r.data as Map<String, dynamic>;
    final list = data['bookings'] as List? ?? [];
    return list
        .map((e) => BookingModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<BookingModel?> getDriverActiveBooking() async {
    final r = await _dio.get('/booking/driver/active');
    final data = r.data as Map<String, dynamic>;
    if (data['booking'] == null) return null;
    return BookingModel.fromJson(data['booking'] as Map<String, dynamic>);
  }

  // ── CUSTOMER ─────────────────────────────────────────────────

  Future<BookingModel> createBooking({
    required String vehicleType,
    required String pickupAddress,
    required double pickupLat,
    required double pickupLng,
    required String dropAddress,
    required double dropLat,
    required double dropLng,
    String? description,
  }) async {
    final r = await _dio.post('/customer/create-booking', data: {
      'vehicleType': vehicleType,
      'pickup': {
        'address': pickupAddress,
        'latitude': pickupLat,
        'longitude': pickupLng,
      },
      'dropoff': {
        'address': dropAddress,
        'latitude': dropLat,
        'longitude': dropLng,
      },
      if (description != null && description.isNotEmpty)
        'description': description,
    });
    final data = r.data as Map<String, dynamic>;
    return BookingModel.fromJson(data['booking'] as Map<String, dynamic>);
  }

  Future<BookingModel?> getActiveBooking() async {
    final r = await _dio.get('/customer/active-booking');
    final data = r.data as Map<String, dynamic>;
    if (data['booking'] == null) return null;
    return BookingModel.fromJson(data['booking'] as Map<String, dynamic>);
  }

  Future<BookingModel> getBooking(String id) async {
    final r = await _dio.get('/booking/$id/status');
    final data = r.data as Map<String, dynamic>;
    return BookingModel.fromJson(data['booking'] as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> getBookingCancelQuote(String bookingId) async {
    final r = await _dio.get(
      '/customer/booking-cancel-quote',
      queryParameters: {'bookingId': bookingId},
    );
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cancelBooking(String id,
      {String reason = 'Customer cancelled'}) async {
    final r = await _dio.post('/customer/cancel-booking',
        data: {'bookingId': id, 'reason': reason});
    return r.data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getFareQuote({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
    required String vehicleType,
  }) async {
    final r = await _dio.get('/customer/fare-quote', queryParameters: {
      'originLat': originLat,
      'originLng': originLng,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
      'vehicleType': vehicleType,
    });
    return r.data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> getPlaceSuggestions(String query) async {
    final r = await _dio.get('/customer/places-autocomplete', queryParameters: {
      'query': query,
    });
    final data = r.data as Map<String, dynamic>;
    final list = data['predictions'] as List? ?? const [];
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<void> rateBooking(String id, int rating, String review) async {
    await _dio.post('/customer/rate-booking',
        data: {'bookingId': id, 'rating': rating, 'review': review});
  }

  Future<List<BookingModel>> getBookingHistory() async {
    final r = await _dio.get('/customer/booking-history');
    final data = r.data as Map<String, dynamic>;
    final list = data['bookings'] as List? ?? [];
    return list
        .map((e) => BookingModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateCustomerLocation(double lat, double lng) async {
    await _dio.put('/customer/update-location',
        data: {'latitude': lat, 'longitude': lng});
  }

  Future<List<NearbyDriver>> getNearbyDrivers({
    required double latitude,
    required double longitude,
    String? vehicleType,
  }) async {
    final r = await _dio.get('/customer/nearby-drivers', queryParameters: {
      'latitude': latitude,
      'longitude': longitude,
      if (vehicleType != null && vehicleType.isNotEmpty)
        'vehicleType': vehicleType,
    });
    final data = r.data as Map<String, dynamic>;
    final list = data['drivers'] as List? ?? [];
    return list
        .map((e) => NearbyDriver.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<List<double>>> getRoutePath({
    required double originLat,
    required double originLng,
    required double destinationLat,
    required double destinationLng,
  }) async {
    final r = await _dio.get('/booking/route-path', queryParameters: {
      'originLat': originLat,
      'originLng': originLng,
      'destinationLat': destinationLat,
      'destinationLng': destinationLng,
    });
    final data = r.data as Map<String, dynamic>;
    final coordinates = data['coordinates'] as List? ?? const [];
    return coordinates
        .whereType<List>()
        .map((coord) {
          final longitude = (coord.isNotEmpty ? coord[0] : null) as num?;
          final latitude = (coord.length > 1 ? coord[1] : null) as num?;
          if (longitude == null || latitude == null) return <double>[];
          return <double>[latitude.toDouble(), longitude.toDouble()];
        })
        .where((coord) => coord.length == 2)
        .toList();
  }
}
