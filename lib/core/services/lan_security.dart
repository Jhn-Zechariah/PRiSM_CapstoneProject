/// Shared key for the ESP32's local web server (POST /sprinkler).
///
/// The ESP32 rejects sprinkler commands without it, so other devices on the
/// same WiFi cannot switch the sprinkler. Build the app with the same value
/// as LAN_KEY in the ESP32's secrets.h:
///   flutter run --dart-define=PRISM_LAN_KEY=SAME_VALUE_AS_LAN_KEY
///
/// Without it the LAN shortcut is refused (HTTP 401) and the command still
/// reaches the ESP32 through Firestore within ~15 s.
class LanSecurity {
  static const String key = String.fromEnvironment('PRISM_LAN_KEY');

  static Map<String, String> get jsonHeaders => {
        'Content-Type': 'application/json',
        if (key.isNotEmpty) 'X-PRISM-Key': key,
      };
}
