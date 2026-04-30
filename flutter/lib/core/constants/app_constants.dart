class AppConstants {
  // ── Backend endpoints ──────────────────────────────────────────
  // For local emulator testing:
  // --dart-define=MOVEZY_API_URL=http://10.0.2.2:3000/api
  // --dart-define=MOVEZY_SOCKET_URL=http://10.0.2.2:3000
  //
  // For local physical device testing:
  // --dart-define=MOVEZY_API_URL=http://<YOUR-LAN-IP>:3000/api
  // --dart-define=MOVEZY_SOCKET_URL=http://<YOUR-LAN-IP>:3000
  static const String baseUrl = String.fromEnvironment(
    'MOVEZY_API_URL',
    defaultValue: 'https://movezy-backend.onrender.com/api',
  );
  static const String socketUrl = String.fromEnvironment(
    'MOVEZY_SOCKET_URL',
    defaultValue: 'https://movezy-backend.onrender.com',
  );

  // Shared prefs keys
  static const String keyToken = 'auth_token';
  static const String keyUser = 'user_data';
  static const String keyFcmToken = 'fcm_token';
  static const String keyNightMaps = 'night_maps_enabled';
  static const String keyAppThemeMode = 'app_theme_mode';
  static const String keyRegisteredDriverPhones = 'registered_driver_phones';

  // Maps
  static const double defaultZoom = 15.0;
  static const double dashboardMapZoom = 14.2;

  // Search
  static const int searchRadiusM = 5000;

  // Support
  static const String supportPhone = '+919876543210';
  static const String supportEmail = 'support@movezy.in';
  static const String supportWhatsApp = 'https://wa.me/919876543210';

  static bool get usesEmulatorLoopback =>
      baseUrl.contains('10.0.2.2') || socketUrl.contains('10.0.2.2');

  static String get localBackendHint =>
      'If you are testing on a real phone, replace 10.0.2.2 with your computer\'s LAN IP using '
      '--dart-define=MOVEZY_API_URL=http://<YOUR-IP>:3000/api '
      'and --dart-define=MOVEZY_SOCKET_URL=http://<YOUR-IP>:3000.';
}

class AppRoutes {
  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const otpVerify = '/otp';
  static const driverRegister = '/driver-register';
  static const customerHome = '/customer/home';
  static const booking = '/customer/booking';
  static const bookingHistory = '/customer/history';
  static const rateBooking = '/customer/rate';
  static const driverHome = '/driver/home';
  static const tripHistory = '/driver/history';
  static const driverPending = '/driver/pending';
  static const driverProfile = '/driver/profile';
}

// ── Vehicle catalogue ────────────────────────────────────────────
class VehicleOption {
  final String type;
  final String emoji;
  final String name;
  final String desc;
  final int baseFare;
  final int perKm;
  final int minFare;
  final int colorHex;

  const VehicleOption({
    required this.type,
    required this.emoji,
    required this.name,
    required this.desc,
    required this.baseFare,
    required this.perKm,
    required this.minFare,
    required this.colorHex,
  });

  int estimateFare(double km) {
    final distance = km < 0 ? 0 : km;
    final baseDistanceFare = baseFare + (perKm * distance);
    final longDistanceSurcharge = distance > 10 ? (distance - 10) * (perKm * 0.2) : 0;
    final bookingFee = 10;
    final hour = DateTime.now().hour;
    final isPeakHour = (hour >= 8 && hour <= 11) || (hour >= 17 && hour <= 21);
    final peakMultiplier = isPeakHour ? 1.2 : 1.0;
    final grossFare = (baseDistanceFare + longDistanceSurcharge + bookingFee) * peakMultiplier;
    return grossFare < minFare ? minFare : grossFare.round();
  }
}

const kVehicles = [
  VehicleOption(
      type: 'bike',
      emoji: '🏍️',
      name: 'Bike',
      desc: 'Small packages, quick delivery',
      baseFare: 20,
      perKm: 8,
      minFare: 35,
      colorHex: 0xFF22C55E),
  VehicleOption(
      type: 'auto',
      emoji: '🛺',
      name: 'Auto',
      desc: 'Medium goods, city transport',
      baseFare: 30,
      perKm: 12,
      minFare: 55,
      colorHex: 0xFF3B82F6),
  VehicleOption(
      type: 'mini_truck',
      emoji: '🚐',
      name: 'Mini Truck',
      desc: 'Furniture & appliances',
      baseFare: 80,
      perKm: 20,
      minFare: 140,
      colorHex: 0xFFF59E0B),
  VehicleOption(
      type: 'tempo',
      emoji: '🚚',
      name: 'Tempo',
      desc: 'Office & home shifting',
      baseFare: 100,
      perKm: 30,
      minFare: 180,
      colorHex: 0xFF8B5CF6),
  VehicleOption(
      type: 'truck',
      emoji: '🚛',
      name: 'Truck',
      desc: 'Heavy goods & warehouse',
      baseFare: 200,
      perKm: 50,
      minFare: 320,
      colorHex: 0xFFEF4444),
  VehicleOption(
      type: 'pickup',
      emoji: '🛻',
      name: 'Pickup',
      desc: 'Flat goods, bikes & material',
      baseFare: 120,
      perKm: 35,
      minFare: 220,
      colorHex: 0xFFFF6B00),
];

VehicleOption? vehicleByType(String t) {
  try {
    return kVehicles.firstWhere((v) => v.type == t);
  } catch (_) {
    return null;
  }
}
