import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:movezy/services/session_manager.dart';

class PushNotificationService {
  PushNotificationService._();

  static final instance = PushNotificationService._();

  Future<void> initialize() async {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(alert: true, badge: true, sound: true);
    final token = await messaging.getToken();
    if (token != null && token.isNotEmpty) {
      await SessionManager.instance.saveFcmToken(token);
    }
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('FCM foreground message: ${message.messageId}');
    });
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('FCM opened app: ${message.messageId}');
    });
    messaging.onTokenRefresh.listen((newToken) async {
      await SessionManager.instance.saveFcmToken(newToken);
    });
  }
}
