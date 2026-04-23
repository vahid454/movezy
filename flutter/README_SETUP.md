# Movezy Flutter App — Fixed & Clean Build

## Quick Start (3 steps)

### 1. Install dependencies
```bash
cd movezy_fixed
flutter pub get
```

### 2. Add Google Maps API key
Edit `android/app/src/main/AndroidManifest.xml`:
```xml
<meta-data
    android:name="com.google.android.geo.API_KEY"
    android:value="YOUR_REAL_KEY_HERE"/>
```
Get a key at: https://console.cloud.google.com → Enable **Maps SDK for Android**

For iOS, also set `ios/Runner/Info.plist`:
```xml
<key>GMSApiKey</key>
<string>YOUR_IOS_GOOGLE_MAPS_API_KEY</string>
```

### 3. Point to your backend
This app now supports `--dart-define`, so you do not need to hardcode URLs anymore.

Android emulator:
```bash
flutter run
```

Real Android or iPhone on the same Wi-Fi:
```bash
flutter run \
  --dart-define=MOVEZY_API_URL=http://192.168.1.XX:3000/api \
  --dart-define=MOVEZY_SOCKET_URL=http://192.168.1.XX:3000
```

### 4. Run
```bash
flutter run
```

### 5. Quick map verification
If the map area is still blank:
1. Confirm billing is enabled in Google Cloud.
2. Enable `Maps SDK for Android` and `Maps SDK for iOS`.
3. Remove overly strict API-key restrictions until tiles load once.
4. For Android, verify package name and SHA-1 restrictions.
5. For real devices, make sure backend URLs are not still using `10.0.2.2`.

### Build release APK
```bash
flutter build apk --release
# or split for Play Store:
flutter build apk --split-per-abi --release
```

---

## What was fixed vs the broken version

| Issue | Fix applied |
|-------|-------------|
| V1 embedding error | Manifest uses `flutterEmbedding = 2`, MainActivity extends `FlutterActivity` |
| Wrong relative imports `../core/..` | All imports use `package:movezy/...` |
| Missing screens in router | Every route maps to a concrete screen class |
| Undefined classes | All widgets/helpers in `lib/core/widgets/widgets.dart` |
| `records` syntax crash | Replaced record tuples `(a, b, c).$1` with plain class fields |
| `flutter_animate` dependency conflicts | Removed, uses standard `AnimationController` |
| Dart 3 record feature in widgets.dart | Used `switch` returning a `(Color, Color)` record — compatible with Dart >=3.0 |
| Assets folder missing | Placeholder file added so `pubspec.yaml` asset path resolves |
| `google-services.json` hard dependency | Firebase init is commented out; app runs without it |

---

## Firebase Push Notifications (optional)
1. Create project at https://console.firebase.google.com
2. Add Android app, package `com.movezy`
3. Download `google-services.json` → place at `android/app/google-services.json`
4. In `android/app/build.gradle` add at the bottom: `apply plugin: 'com.google.gms.google-services'`
5. Uncomment Firebase init in `lib/main.dart`

---

## Project structure
```
movezy_fixed/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── constants/app_constants.dart   ← URLs, routes, vehicle types
│   │   ├── theme/app_theme.dart           ← Dark orange Material3 theme
│   │   ├── utils/router.dart              ← GoRouter config
│   │   └── widgets/widgets.dart           ← All shared widgets
│   ├── data/
│   │   ├── models/models.dart             ← UserModel, BookingModel, DriverProfile
│   │   └── datasources/api_service.dart   ← Dio API calls
│   ├── services/
│   │   ├── session_manager.dart           ← JWT + SharedPreferences
│   │   └── socket_service.dart            ← Socket.IO realtime
│   └── features/
│       ├── auth/screens/                  ← Splash, Onboarding, Login, OTP, Register
│       ├── customer/screens/              ← Home(Map), Booking, History, Rate
│       └── driver/screens/               ← Home(Map), History, Pending, Profile
├── android/                              ← All Android platform files
├── assets/images/
└── pubspec.yaml
```
