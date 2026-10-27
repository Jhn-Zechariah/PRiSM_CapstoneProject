import 'dart:convert';
import 'package:http/http.dart' as http;

/// Client for the PRISM forecast API (prism-ml/api.py).
///
/// The server reads the latest sensor data from Firestore itself, so the app
/// only asks for the forecast. Configure at build/run time:
///   flutter run --dart-define=PRISM_ML_URL=http://192.168.1.130:8000 \
///               --dart-define=PRISM_API_KEY=YOUR_KEY   (same value as on the server)
class MlService {
  // Switch to 'http://127.0.0.1:8000' if you are using ADB USB port forwarding!
  static const String baseUrl = String.fromEnvironment(
    'PRISM_ML_URL',
    defaultValue: 'http://192.168.1.130:8000',
  );
  static const String _apiKey = String.fromEnvironment('PRISM_API_KEY');
  static const Duration _timeout = Duration(seconds: 10);

  /// Latest pig surface temperature forecast (+15 / +30 min) and risk level.
  ///
  /// Always check `status` first: only "ok" carries a forecast. Other values
  /// ("insufficient_data", "stale_data", "out_of_training_range",
  /// "model_unavailable", "firestore_error") come with a `message` to show.
  static Future<Map<String, dynamic>> fetchForecast() async {
    if (_apiKey.isEmpty) {
      throw Exception('ML API key not set (build with --dart-define=PRISM_API_KEY=...).');
    }

    final response = await http
        .get(Uri.parse('$baseUrl/predict'), headers: {'X-API-Key': _apiKey})
        .timeout(_timeout);

    if (response.statusCode == 401) {
      throw Exception('ML API key was rejected by the server.');
    }
    // 200 = forecast or a data status; 503 = server-side problem, still a JSON body with a message
    if (response.statusCode == 200 || response.statusCode == 503) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Forecast failed: ${response.statusCode}');
  }
}
