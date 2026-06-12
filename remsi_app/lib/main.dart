import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'screens/dashboard_screen.dart';
import 'services/settings_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  String fcmToken = '';
  try {
    // Graceful initialization to prevent crashes on non-configured environments
    await Firebase.initializeApp();
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );
    fcmToken = await messaging.getToken() ?? '';
    debugPrint("Retrieved FCM Token: $fcmToken");

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint("Foreground message: ${message.notification?.body}");
    });
  } catch (e) {
    debugPrint("Firebase Messaging initialization bypassed: $e");
  }

  runApp(
    ProviderScope(
      child: MyApp(initialFcmToken: fcmToken),
    ),
  );
}

class MyApp extends ConsumerWidget {
  final String initialFcmToken;
  const MyApp({super.key, this.initialFcmToken = ''});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (initialFcmToken.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(settingsProvider.notifier).updateNotifierSettings(
          fcmToken: initialFcmToken,
        );
      });
    }

    return MaterialApp(
      title: 'REMSI Dashboard',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF8B5CF6),
        scaffoldBackgroundColor: const Color(0xFF0B0E17),
        cardColor: const Color(0x99131926),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF8B5CF6),
          secondary: Color(0xFF06B6D4),
          surface: Color(0x99131926),
          error: Color(0xFFEF4444),
        ),
        fontFamily: 'Outfit',
      ),
      home: const DashboardScreen(),
    );
  }
}
