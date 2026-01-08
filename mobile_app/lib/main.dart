
import 'package:flutter/material.dart';
import 'package:eventit/config.dart';
import 'package:eventit/screens/login_screen.dart';
import 'package:eventit/screens/home_screen.dart';
import 'package:eventit/utils/http_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

const AndroidNotificationChannel channel = AndroidNotificationChannel(
  'high_importance_channel',
  'Notifikasi Penting',
  description: 'Channel ini digunakan untuk notifikasi event penting.',
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
FlutterLocalNotificationsPlugin();

Future<void> sendFCMTokenToBackend(String? token) async {
  if (token == null) {
    print("--- FCM Token is null, skipping send to backend ---");
    return;
  }
  try {
    print("--- Sending FCM Token to Backend: $token ---");
    final response = await HttpClient.post('/api/user/update-fcm-token', {
      'token': token
    });

    if (response.statusCode == 200) {
      print("--- FCM Token successfully stored in backend ---");
    } else {
      print("--- Failed to store FCM Token, status: ${response.statusCode} ---");
    }
  } catch (e) {
    print("--- Error sending FCM Token to backend: $e ---");
  }
}

class AuthCheckWrapper extends StatefulWidget {
  const AuthCheckWrapper({super.key});

  @override
  State<AuthCheckWrapper> createState() => _AuthCheckWrapperState();
}

class _AuthCheckWrapperState extends State<AuthCheckWrapper> {
  late final Future<bool> _loginStatusFuture;

  @override
  void initState() {
    super.initState();
    _loginStatusFuture = _checkLoginStatus();
  }

  Future<void> _initFCM() async {
    FirebaseMessaging messaging = FirebaseMessaging.instance;
    NotificationSettings settings = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      print('--- User granted notification permission ---');

      String? fcmToken = await messaging.getToken();
      await sendFCMTokenToBackend(fcmToken);

      await messaging.subscribeToTopic('new_events');
      print("--- Subscribed to 'new_events' topic ---");

    } else {
      print('--- User declined or has not accepted permission ---');
    }
  }

  Future<bool> _checkLoginStatus() async {
    await HttpClient.initialize();

    try {
      final response = await HttpClient.get('/api/status');

      if (response.statusCode == 200) {
        print("--- DEBUG: Sesi Valid. User ID: ${json.decode(response.body)['user_id']} ---");
        final data = json.decode(response.body);
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setInt('user_id', data['user_id']);
        await prefs.setString('user_name', data['name']);
        await prefs.setBool('has_business', data['has_business'] ?? false);

        await _initFCM();

        return true;
      } else {
        print("--- DEBUG: Sesi tidak valid (${response.statusCode}). Mengarahkan ke Login. ---");
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await HttpClient.clearCookies();
        await prefs.clear();
        return false;
      }
    } catch (e) {
      print("--- DEBUG: Error cek status: $e. Mengarahkan ke Login. ---");
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await HttpClient.clearCookies();
      await prefs.clear();
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _loginStatusFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo-okoce.png',
                    width: 150,
                  ),
                  const SizedBox(height: 32),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text("Memeriksa sesi...", style: TextStyle(color: Colors.grey[600])),
                ],
              ),
            ),
          );
        }

        if (snapshot.hasData && snapshot.data == true) {
          return const HomeScreen();
        } else {
          return const LoginScreen();
        }
      },
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp();

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  const AndroidInitializationSettings initializationSettingsAndroid =
  AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings =
  InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  FirebaseMessaging.onMessage.listen((RemoteMessage message) {
    print('--- Got a message whilst in the foreground! ---');
    RemoteNotification? notification = message.notification;
    AndroidNotification? android = message.notification?.android;

    if (notification != null && android != null) {
      flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            icon: android.smallIcon,
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: json.encode(message.data),
      );
    }
  });

  runApp(const MyApp());
}

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("--- Handling a background message: ${message.messageId} ---");
  print("Title: ${message.notification?.title}");
  print("Body: ${message.notification?.body}");
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      theme: ThemeData(
        brightness: Brightness.light,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          primary: Colors.blue[800],
          secondary: Colors.red,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.blue[800],
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        bottomNavigationBarTheme: BottomNavigationBarThemeData(
          selectedItemColor: Colors.blue[800],
          unselectedItemColor: Colors.grey[600],
          backgroundColor: Colors.white,
          showUnselectedLabels: true,
        ),
      ),
      home: const AuthCheckWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}