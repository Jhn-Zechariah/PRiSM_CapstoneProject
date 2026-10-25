import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart'; // Handles user validation credentials

/// Thrown by the assessment calls so screens can tell "rejected input" (422) from
/// "not allowed" (401/403) and "service down" (null status / 5xx).
class MlServiceException implements Exception {
  final int? statusCode;
  final String message;
  MlServiceException(this.statusCode, this.message);

  @override
  String toString() => 'MlServiceException($statusCode): $message';
}

class MlService {
  // Switch to 'http://127.0.0.1:8000' if you are using ADB USB port forwarding!
  // Override without editing code: flutter run --dart-define=PRISM_API_URL=http://<pc-ip>:8000
  static const String baseUrl =
      String.fromEnvironment('PRISM_API_URL', defaultValue: 'http://127.0.0.1:8000');
  static const Duration _timeout = Duration(seconds: 10);

  // Pig results keyed by the inputs that affect them. Futures are cached so
  // cards that rebuild while a request is in flight share it.
  static final Map<String, Future<Map<String, dynamic>>> _pigCache = {};

  /// Helper to fetch the current active user's JWT ID Token from Firebase Auth
  static Future<String?> _getFirebaseToken() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("⚠️ Authentication Check Failed: No user logged into Firebase.");
        return null;
      }
      // Cached token; the SDK refreshes it automatically once it expires
      return await user.getIdToken();
    } catch (e) {
      print("❌ Error fetching active token from Firebase session: $e");
      return null;
    }
  }

  /// Analyze farm-level conditions
  static Future<Map<String, dynamic>> analyzeFarm({
    required double temperatureC,
    required double humidityPct,
    double weightChangeKg = 0.0,
    double feedIntakeKg = 0.0,
    int medicineGiven = 0,
  }) async {
    final url = Uri.parse('$baseUrl/api/farm/analyze');
    final token = await _getFirebaseToken();

    if (token == null) {
      throw Exception('Authentication required to use ML analytics.');
    }

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Attached security badge
      },
      body: jsonEncode({
        'temperature_c': temperatureC,
        'humidity_pct': humidityPct,
        'weight_change_kg': weightChangeKg,
        'feed_intake_kg': feedIntakeKg,
        'medicine_given': medicineGiven,
      }),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'Farm analysis failed: ${response.statusCode} - ${response.body}',
      );
    }
  }

  /// Analyze individual pig weight status
  static Future<Map<String, dynamic>> analyzePig({
    required String pigId,
    required String birthDate, // format: YYYY-MM-DD
    required double currentWeight,
    required double birthWeight,
  }) {
    // Today's date is part of the key because the result depends on the pig's age
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final key = '$pigId|$birthDate|$currentWeight|$birthWeight|$today';
    final cached = _pigCache[key];
    if (cached != null) return cached;

    final request = _analyzePigRequest(
      pigId: pigId,
      birthDate: birthDate,
      currentWeight: currentWeight,
      birthWeight: birthWeight,
    );
    _pigCache[key] = request;
    // Don't keep failures around, so the next attempt retries the server
    request.catchError((_) {
      _pigCache.remove(key);
      return <String, dynamic>{};
    });
    return request;
  }

  static Future<Map<String, dynamic>> _analyzePigRequest({
    required String pigId,
    required String birthDate,
    required double currentWeight,
    required double birthWeight,
  }) async {
    final url = Uri.parse('$baseUrl/api/pig/analyze');
    final token = await _getFirebaseToken();

    if (token == null) {
      throw Exception('Authentication required to use ML analytics.');
    }

    final response = await http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token', // Attached security badge
      },
      body: jsonEncode({
        'pig_id': pigId,
        'birth_date': birthDate,
        'current_weight': currentWeight,
        'birth_weight': birthWeight,
      }),
    ).timeout(_timeout);

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception(
        'Pig analysis failed: ${response.statusCode} - ${response.body}',
      );
    }
  }

  // ── Assessment API (prism-ml2.0/app/routes.py). Read-only: no route sends commands. ──

  static Future<Map<String, dynamic>> _authed(String method, String path,
      [Map<String, dynamic>? body]) async {
    final token = await _getFirebaseToken();
    if (token == null) {
      throw MlServiceException(401, 'Authentication required to use ML analytics.');
    }
    final uri = Uri.parse('$baseUrl$path');
    final headers = {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'};
    final http.Response res;
    try {
      res = method == 'GET'
          ? await http.get(uri, headers: headers).timeout(_timeout)
          : await http.post(uri, headers: headers, body: jsonEncode(body ?? const {})).timeout(_timeout);
    } catch (e) {
      throw MlServiceException(null, 'Assessment service unreachable');
    }
    if (res.statusCode != 200) {
      throw MlServiceException(res.statusCode, 'Assessment request failed (${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> assessEnvironment(Map<String, dynamic> body) =>
      _authed('POST', '/assess/environment', body);

  static Future<Map<String, dynamic>> assessPigGrowth(Map<String, dynamic> body) =>
      _authed('POST', '/assess/pig-growth', body);

  static Future<Map<String, dynamic>> assessPenThermal(Map<String, dynamic> body) =>
      _authed('POST', '/assess/pen-thermal', body);

  static Future<Map<String, dynamic>> fetchRuleConfig() => _authed('GET', '/config/rules');

  /// Admin-only on the server; the app only displays the result.
  static Future<Map<String, dynamic>> fetchActiveModel() => _authed('GET', '/models/active');
}
