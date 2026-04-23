import 'dart:convert';

// ── User ─────────────────────────────────────────────────────────
class UserModel {
  final String id;
  final String name;
  final String phone;
  final String role;

  const UserModel(
      {required this.id,
      required this.name,
      required this.phone,
      required this.role});

  factory UserModel.fromJson(Map<String, dynamic> j) => UserModel(
        id: (j['id'] ?? j['_id'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        role: (j['role'] ?? 'customer').toString(),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'phone': phone, 'role': role};

  String toJsonString() => jsonEncode(toJson());

  factory UserModel.fromJsonString(String s) =>
      UserModel.fromJson(jsonDecode(s) as Map<String, dynamic>);

  bool get isCustomer => role == 'customer';
  bool get isDriver => role == 'driver';
}

// ── Driver profile ────────────────────────────────────────────────
class DriverProfile {
  final String id;
  final String name;
  final String phone;
  final String vehicleNumber;
  final String vehicleType;
  final double? latitude;
  final double? longitude;
  final String? vehicleModel;
  final String? drivingLicense;
  final String approvalStatus;
  final bool isOnline;
  final bool isAvailable;
  final double rating;
  final int totalTrips;
  final String? rejectionReason;

  const DriverProfile({
    required this.id,
    required this.name,
    required this.phone,
    required this.vehicleNumber,
    required this.vehicleType,
    this.latitude,
    this.longitude,
    this.vehicleModel,
    this.drivingLicense,
    required this.approvalStatus,
    required this.isOnline,
    required this.isAvailable,
    required this.rating,
    required this.totalTrips,
    this.rejectionReason,
  });

  factory DriverProfile.fromJson(Map<String, dynamic> j) => DriverProfile(
        id: (j['id'] ?? j['_id'] ?? j['user'] ?? '').toString(),
        name: (j['name'] ?? '').toString(),
        phone: (j['phone'] ?? '').toString(),
        vehicleNumber: (j['vehicleNumber'] ?? '').toString(),
        vehicleType: (j['vehicleType'] ?? '').toString(),
        latitude: _parseLatitude(j),
        longitude: _parseLongitude(j),
        vehicleModel: j['vehicleModel']?.toString(),
        drivingLicense: j['drivingLicense']?.toString(),
        approvalStatus: (j['approvalStatus'] ?? 'pending').toString(),
        isOnline: j['isOnline'] == true,
        isAvailable: j['isAvailable'] != false,
        rating:
            (j['rating'] ?? 5.0) is num ? (j['rating'] ?? 5.0).toDouble() : 5.0,
        totalTrips: (j['totalTrips'] ?? 0) is int
            ? j['totalTrips'] as int
            : int.tryParse(j['totalTrips'].toString()) ?? 0,
        rejectionReason: j['rejectionReason']?.toString(),
      );

  bool get isPending => approvalStatus == 'pending';
  bool get isApproved => approvalStatus == 'approved';
  bool get isRejected => approvalStatus == 'rejected';
}

// ── Booking location ──────────────────────────────────────────────
class BookingLoc {
  final String address;
  final double latitude;
  final double longitude;

  const BookingLoc(
      {required this.address, required this.latitude, required this.longitude});

  factory BookingLoc.fromJson(Map<String, dynamic> j) {
    final lat = _parseLatitude(j) ?? 0;
    final lng = _parseLongitude(j) ?? 0;
    return BookingLoc(
      address: (j['address'] ?? '').toString(),
      latitude: lat,
      longitude: lng,
    );
  }
}

// ── Booking ───────────────────────────────────────────────────────
class BookingModel {
  final String id;
  final String bookingId;
  final String vehicleType;
  final String? customerName;
  final String? customerPhone;
  final double? customerLatitude;
  final double? customerLongitude;
  final BookingLoc? pickup;
  final BookingLoc? dropoff;
  final String? description;
  final String status;
  final int estimatedFare;
  final double estimatedDistance;
  final DriverProfile? driver;
  final int nearbyDriversCount;
  final DateTime? createdAt;
  final int? customerRating;

  const BookingModel({
    required this.id,
    required this.bookingId,
    required this.vehicleType,
    this.customerName,
    this.customerPhone,
    this.customerLatitude,
    this.customerLongitude,
    this.pickup,
    this.dropoff,
    this.description,
    required this.status,
    required this.estimatedFare,
    required this.estimatedDistance,
    this.driver,
    this.nearbyDriversCount = 0,
    this.createdAt,
    this.customerRating,
  });

  factory BookingModel.fromJson(Map<String, dynamic> j) {
    DriverProfile? driver;
    final dRaw = j['driver'];
    if (dRaw != null && dRaw is Map<String, dynamic> && dRaw.isNotEmpty) {
      try {
        driver = DriverProfile.fromJson(dRaw);
      } catch (_) {}
    }

    return BookingModel(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      bookingId: (j['bookingId'] ?? '').toString(),
      vehicleType: (j['vehicleType'] ?? '').toString(),
      customerName: _parseNestedString(j, ['customer', 'name']) ??
          j['customerName']?.toString(),
      customerPhone: _parseNestedString(j, ['customer', 'phone']) ??
          j['customerPhone']?.toString(),
      customerLatitude: _parseNestedDouble(
          j, ['customer', 'location', 'coordinates'],
          index: 1),
      customerLongitude: _parseNestedDouble(
          j, ['customer', 'location', 'coordinates'],
          index: 0),
      pickup: j['pickup'] is Map
          ? BookingLoc.fromJson(j['pickup'] as Map<String, dynamic>)
          : null,
      dropoff: j['dropoff'] is Map
          ? BookingLoc.fromJson(j['dropoff'] as Map<String, dynamic>)
          : null,
      description: j['description']?.toString(),
      status: (j['status'] ?? 'searching').toString(),
      estimatedFare: (j['estimatedFare'] ?? 0) is num
          ? (j['estimatedFare'] as num).toInt()
          : 0,
      estimatedDistance: (j['estimatedDistance'] ?? 0) is num
          ? (j['estimatedDistance'] as num).toDouble()
          : 0.0,
      driver: driver,
      nearbyDriversCount: (j['nearbyDriversCount'] ?? 0) is int
          ? j['nearbyDriversCount'] as int
          : 0,
      createdAt: j['createdAt'] != null
          ? DateTime.tryParse(j['createdAt'].toString())
          : null,
      customerRating:
          j['customerRating'] is int ? j['customerRating'] as int : null,
    );
  }

  bool get isSearching => status == 'searching';
  bool get isAccepted => status == 'accepted';
  bool get isInProgress => status == 'in_progress';
  bool get isCompleted => status == 'completed';
  bool get isCancelled => status == 'cancelled';
  bool get isActive => [
        'searching',
        'accepted',
        'driver_arriving',
        'in_progress'
      ].contains(status);

  String get displayBookingId {
    if (bookingId.trim().isNotEmpty) return bookingId.trim();
    if (id.trim().isEmpty) return 'MVZ-PENDING';
    final clean = id.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
    final tail = clean.length > 6 ? clean.substring(clean.length - 6) : clean;
    return 'MVZ-$tail';
  }

  String get statusLabel {
    switch (status) {
      case 'searching':
        return 'Finding Driver';
      case 'accepted':
        return 'Driver Accepted';
      case 'driver_arriving':
        return 'Driver Arriving';
      case 'in_progress':
        return 'In Progress';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  bool get hasCustomerLiveLocation =>
      customerLatitude != null &&
      customerLongitude != null &&
      customerLatitude != 0 &&
      customerLongitude != 0;
}

// ── Nearby driver (map pins) ──────────────────────────────────────
class NearbyDriver {
  final String id;
  final String name;
  final String vehicleNumber;
  final String vehicleType;
  final double rating;
  final double? latitude;
  final double? longitude;

  const NearbyDriver({
    required this.id,
    required this.name,
    required this.vehicleNumber,
    required this.vehicleType,
    required this.rating,
    this.latitude,
    this.longitude,
  });

  factory NearbyDriver.fromJson(Map<String, dynamic> j) {
    return NearbyDriver(
      id: (j['_id'] ?? j['id'] ?? '').toString(),
      name: (j['name'] ?? '').toString(),
      vehicleNumber: (j['vehicleNumber'] ?? '').toString(),
      vehicleType: (j['vehicleType'] ?? '').toString(),
      rating:
          (j['rating'] ?? 5.0) is num ? (j['rating'] as num).toDouble() : 5.0,
      latitude: _parseLatitude(j),
      longitude: _parseLongitude(j),
    );
  }
}

double? _parseLatitude(Map<String, dynamic> j) {
  final direct = j['latitude'];
  if (direct is num) return direct.toDouble();
  final loc = j['location'];
  if (loc is Map && loc['coordinates'] is List) {
    final c = loc['coordinates'] as List;
    if (c.length >= 2 && c[1] is num) {
      return (c[1] as num).toDouble();
    }
  }
  return null;
}

double? _parseLongitude(Map<String, dynamic> j) {
  final direct = j['longitude'];
  if (direct is num) return direct.toDouble();
  final loc = j['location'];
  if (loc is Map && loc['coordinates'] is List) {
    final c = loc['coordinates'] as List;
    if (c.length >= 2 && c[0] is num) {
      return (c[0] as num).toDouble();
    }
  }
  return null;
}

String? _parseNestedString(Map<String, dynamic> j, List<String> path) {
  dynamic current = j;
  for (final key in path) {
    if (current is Map && current[key] != null) {
      current = current[key];
    } else {
      return null;
    }
  }
  return current?.toString();
}

double? _parseNestedDouble(
  Map<String, dynamic> j,
  List<String> path, {
  required int index,
}) {
  dynamic current = j;
  for (final key in path) {
    if (current is Map && current[key] != null) {
      current = current[key];
    } else {
      return null;
    }
  }
  if (current is List && current.length > index && current[index] is num) {
    return (current[index] as num).toDouble();
  }
  return null;
}
