import 'package:audioplayers/audioplayers.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> firebaseBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  print("🔥 BACKGROUND HANDLER CALLED");
  print("🔥 DATA: ${message.data}");
  if (message.data['type'] == 'fire_alert') {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pending_fire_alert', true);
    print("🔥 PENDING SET TO TRUE");
  }
}

void triggerEmergency() {
  WakelockPlus.enable();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  WidgetsBinding.instance.addPostFrameCallback((_) {
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/alert', (route) => false,
    );
  });
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseBackgroundHandler);
  await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
    alert: false,
    badge: false,
    sound: false,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => const HomeScreen(),
        '/alert': (context) => const AlertScreen(),
      },
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {

  static const _channel = MethodChannel('com.example.alert_app/alert');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkNativeLaunch();
    _setupFCM();
    _checkPendingAlert();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPendingAlert();
      _checkNativeLaunch();
    }
  }

  Future<void> _checkNativeLaunch() async {
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      final bool? hasAlert = await _channel.invokeMethod('checkFireAlert');
      print("🔥 checkFireAlert result: $hasAlert");
      if (hasAlert == true) {
        triggerEmergency();
      }
    } catch (e) {
      print("🔥 MethodChannel error: $e");
    }
  }

  Future<void> _checkPendingAlert() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getBool('pending_fire_alert') ?? false;
    if (pending) {
      await prefs.remove('pending_fire_alert');
      await Future.delayed(const Duration(milliseconds: 300));
      triggerEmergency();
    }
  }

  Future<void> _setupFCM() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      sound: true,
      badge: true,
    );

    await FirebaseMessaging.instance.subscribeToTopic("alerts");

    final token = await FirebaseMessaging.instance.getToken();
    debugPrint("==FCM TOKEN== $token ==FCM TOKEN==");

    FirebaseMessaging.onMessage.listen((message) async {
      debugPrint("📩 [FOREGROUND] ${message.data}");
      if (message.data['type'] == 'fire_alert') {
        triggerEmergency();
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) async {
      debugPrint("📩 [OPENED] ${message.data}");
      if (message.data['type'] == 'fire_alert') {
        triggerEmergency();
      }
    });

    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null &&
        initialMessage.data['type'] == 'fire_alert') {
      await Future.delayed(const Duration(milliseconds: 500));
      triggerEmergency();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.local_fire_department, color: Colors.red, size: 100),
            SizedBox(height: 20),
            Text("Campus Safety Monitor",
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 10),
            Text("Monitoring campus cameras...",
                style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}

class AlertScreen extends StatefulWidget {
  const AlertScreen({super.key});

  @override
  State<AlertScreen> createState() => _AlertScreenState();
}

class _AlertScreenState extends State<AlertScreen>
    with TickerProviderStateMixin {
  final AudioPlayer player = AudioPlayer();
  final String emergencyNumber = "16";

  late AnimationController _flashController;
  late Animation<Color?> _flashAnimation;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();

    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    )..repeat(reverse: true);

    _flashAnimation = ColorTween(
      begin: const Color(0xFFCC0000),
      end: const Color(0xFFFF2200),
    ).animate(_flashController);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    startAlarm();
  }

  Future<void> startAlarm() async {
    await WakelockPlus.enable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await player.setReleaseMode(ReleaseMode.loop);
    await player.play(AssetSource("raw/fire_alarm.mp3"), volume: 1.0);
  }

  Future<void> stopAlarm() async {
   try {
      await player.stop();
    } catch (e) {}
    await WakelockPlus.disable();
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  
   if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    _pulseController.dispose();
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,  // changed from false to true
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) stopAlarm();
      },
      child: AnimatedBuilder(
        animation: _flashAnimation,
        builder: (context, child) {
          return Scaffold(
            backgroundColor: _flashAnimation.value,
            body: SafeArea(
              child: SizedBox.expand(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ScaleTransition(
                      scale: _pulseAnimation,
                      child: Container(
                        width: 160,
                        height: 160,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white.withOpacity(0.15),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.4), width: 3),
                        ),
                        child: const Icon(Icons.local_fire_department,
                            size: 100, color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 32),
                    const Text("FIRE\nEMERGENCY",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 52,
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            height: 1.1)),
                    const SizedBox(height: 8),
                    const Text("Emergency alert from campus camera",
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.white70)),
                    const SizedBox(height: 48),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: ElevatedButton.icon(
                          onPressed: () async {
                            final uri = Uri(scheme: 'tel', path: emergencyNumber);
                            await launchUrl(uri,
                                mode: LaunchMode.externalApplication);
                          },
                          icon: const Icon(Icons.phone,
                              color: Color(0xFFCC0000), size: 22),
                          label: Text("CALL FIRE BRIGADE ($emergencyNumber)",
                              style: const TextStyle(
                                  color: Color(0xFFCC0000),
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: SizedBox(
                        width: double.infinity,
                        height: 58,
                        child: OutlinedButton(
                          onPressed: stopAlarm,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(
                                color: Colors.white70, width: 1.5),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text("DISMISS ALERT",
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}