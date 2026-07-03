import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/theme.dart';
import 'core/theme_manager.dart';
import 'screens/splash/splash_screen.dart';
import 'services/notification_navigator.dart';
import 'services/push_notification_service.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Register the background message handler (must be top-level function)
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  runApp(const LunaraApp());
}

class LunaraApp extends StatelessWidget {
  const LunaraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: themeManager,
      builder: (context, _) {
        return MaterialApp(
          title: 'Lunara',
          debugShowCheckedModeBanner: false,
          theme: LunaraTheme.lightTheme,
          darkTheme: LunaraTheme.darkTheme,
          themeMode: themeManager.themeMode,
          navigatorKey: NotificationNavigator.navigatorKey,
          home: const SplashScreen(),
        );
      },
    );
  }
}
