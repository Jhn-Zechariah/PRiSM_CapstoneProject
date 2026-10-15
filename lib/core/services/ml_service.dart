import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart'; // Handles user validation credentials

class MlService {
  // Switch to 'http://127.0.0.1:8000' if you are using ADB USB port forwarding!
  static const String baseUrl = 'http://192.168.1.130:8000';
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
}
