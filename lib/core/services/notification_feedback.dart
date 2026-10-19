import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:vibration/vibration.dart';

class NotificationFeedback {
  static Future<void> vibrate() async {
    if (await Vibration.hasVibrator()) {
      Vibration.vibrate(duration: 400);
    }
  }

  static Future<void> playSound() async {
    await FlutterRingtonePlayer().playNotification();
  }
}
