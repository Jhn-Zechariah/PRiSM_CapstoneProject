import 'package:firebase_messaging/firebase_messaging.dart';
import 'local_notification_service.dart';

class NotificationService {
  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  Future<void> init() async {
    print("📡 REQUESTING NOTIFICATION PERMISSIONS...");

    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    print("📊 PERMISSION STATUS: ${settings.authorizationStatus}");

    String? token = await _fcm.getToken();
    print("Device Token: $token");

    // App open: FCM does NOT show the notification, so we show it
    // ourselves using the user's Sound/Vibrate settings.
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      showAlert(
        message.notification?.title ?? 'PRiSM Alert',
        message.notification?.body ?? '',
        critical: message.data['type'] == 'iot_threshold_alert',
      );
    });
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  /// For testing your Sound/Vibrate settings.
  Future<void> showTestNotification() async {
    await showAlert(
      'PRiSM Test Notification',
      'If you see this, your notification system is working! 🎉',
    );
  }
}

// App in background/closed: Android shows the notification itself,
// using the channel the backend chose (see functions/index.js).
// Don't show it again here or you'll get duplicates.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print("Handling a background message: ${message.messageId}");
}
