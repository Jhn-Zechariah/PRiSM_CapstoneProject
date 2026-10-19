import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();

/// Must match channelFor() in functions/index.js.
/// critical + sound ON -> "critical_*" channel (plays at ALARM volume,
/// so it is heard even when the phone is in vibrate mode).
String _channelId(bool sound, bool vibrate, {bool critical = false}) {
  final prefix = critical && sound ? 'critical' : 'alerts';
  return '${prefix}_${sound ? 's' : 'x'}${vibrate ? 'v' : 'x'}';
}

/// Call once in main(), and also in your background handler.
Future<void> initLocalNotifications() async {
  const initSettings = InitializationSettings(
    android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    iOS: DarwinInitializationSettings(),
  );
  await _plugin.initialize(initSettings);

  final android = _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
  await android?.requestNotificationsPermission(); // Android 13+

  // Normal alerts: follow the phone's notification volume / ringer mode.
  for (final sound in [true, false]) {
    for (final vibrate in [true, false]) {
      await android?.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId(sound, vibrate),
          'Alerts (${sound ? "sound" : "no sound"}, ${vibrate ? "vibrate" : "no vibrate"})',
          importance: Importance.high,
          playSound: sound,
          enableVibration: vibrate,
        ),
      );
    }
  }

  // Critical IoT alerts (high temperature / high humidity):
  // sound plays through the ALARM stream.
  for (final vibrate in [true, false]) {
    await android?.createNotificationChannel(
      AndroidNotificationChannel(
        _channelId(true, vibrate, critical: true),
        'Critical IoT alerts (${vibrate ? "vibrate" : "no vibrate"})',
        description: 'High temperature and high humidity alerts',
        importance: Importance.max,
        playSound: true,
        enableVibration: vibrate,
        audioAttributesUsage: AudioAttributesUsage.alarm,
      ),
    );
  }
}

/// Call this whenever your app needs to show an alert.
/// Set [critical] to true for high temperature / high humidity alerts.
Future<void> showAlert(
  String title,
  String body, {
  bool critical = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  if (!(prefs.getBool('isNotifEnabled') ?? true)) return;
  // Critical alerts (high temp / humidity) ALWAYS play sound.
  final sound = critical || (prefs.getBool('isSoundOn') ?? true);
  final vibrate = prefs.getBool('isVibrateOn') ?? true;
  final useAlarm = critical && sound;
  final id = _channelId(sound, vibrate, critical: critical);

  await _plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        id,
        id,
        importance: useAlarm ? Importance.max : Importance.high,
        priority: useAlarm ? Priority.max : Priority.high,
        playSound: sound,
        enableVibration: vibrate,
        audioAttributesUsage: useAlarm
            ? AudioAttributesUsage.alarm
            : AudioAttributesUsage.notification,
      ),
      iOS: DarwinNotificationDetails(presentSound: sound),
    ),
  );
}
