import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movezy/core/constants/app_constants.dart';
import 'package:movezy/data/models/models.dart';

class SessionManager {
  SessionManager._();
  static final instance = SessionManager._();

  SharedPreferences? _p;
  final ValueNotifier<bool> nightMapsEnabled = ValueNotifier(true);
  final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier(ThemeMode.light);

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    nightMapsEnabled.value = _p?.getBool(AppConstants.keyNightMaps) ?? false;
    final storedThemeMode = _p?.getString(AppConstants.keyAppThemeMode) ?? 'light';
    appThemeMode.value = storedThemeMode == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> saveSession(String token, UserModel user) async {
    await _p?.setString(AppConstants.keyToken, token);
    await _p?.setString(AppConstants.keyUser, user.toJsonString());
  }

  String? getToken() => _p?.getString(AppConstants.keyToken);

  UserModel? getUser() {
    final s = _p?.getString(AppConstants.keyUser);
    if (s == null) return null;
    try {
      return UserModel.fromJsonString(s);
    } catch (_) {
      return null;
    }
  }

  bool isLoggedIn() => getToken() != null && getUser() != null;

  String get role => getUser()?.role ?? '';

  Future<void> saveFcmToken(String t) async {
    await _p?.setString(AppConstants.keyFcmToken, t);
  }

  String? getFcmToken() => _p?.getString(AppConstants.keyFcmToken);

  Future<void> setNightMapsEnabled(bool enabled) async {
    nightMapsEnabled.value = enabled;
    await _p?.setBool(AppConstants.keyNightMaps, enabled);
  }

  Future<void> setAppThemeMode(ThemeMode mode) async {
    appThemeMode.value = mode;
    await _p?.setString(
      AppConstants.keyAppThemeMode,
      mode == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  List<String> getRegisteredDriverPhones() =>
      _p?.getStringList(AppConstants.keyRegisteredDriverPhones) ?? const [];

  bool isDriverPhoneRegistered(String phone) =>
      getRegisteredDriverPhones().contains(phone);

  Future<void> markDriverPhoneRegistered(String phone) async {
    final phones = {...getRegisteredDriverPhones(), phone}.toList()..sort();
    await _p?.setStringList(AppConstants.keyRegisteredDriverPhones, phones);
  }

  Future<void> clear() async {
    await FirebaseAuth.instance.signOut();
    await _p?.remove(AppConstants.keyToken);
    await _p?.remove(AppConstants.keyUser);
    await _p?.remove(AppConstants.keyFcmToken);
  }
}
