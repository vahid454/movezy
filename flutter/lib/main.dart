import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:movezy/core/theme/app_theme.dart';
import 'package:movezy/core/utils/router.dart';
import 'package:movezy/services/push_notification_service.dart';
import 'package:movezy/services/session_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    systemNavigationBarColor: Color(0xFFF6F8FC),
    systemNavigationBarIconBrightness: Brightness.dark,
  ));

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await runZonedGuarded(
    () async {
      await Firebase.initializeApp();
      await SessionManager.instance.init();
      await PushNotificationService.instance.initialize();

      runApp(const MovezyApp());
    },
    (error, stackTrace) {
      debugPrint('Unhandled app error: $error');
      debugPrint('$stackTrace');
    },
  );
}

class MovezyApp extends StatelessWidget {
  const MovezyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SessionManager.instance.appThemeMode,
      builder: (context, themeMode, _) => MaterialApp.router(
        title: 'Movezy',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        routerConfig: appRouter,
      ),
    );
  }
}
