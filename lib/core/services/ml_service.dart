import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart'; // Handles user validation credentials

class MlService {
  // Switch to 'http://127.0.0.1:8000' if you are using ADB USB port forwarding!
  static const String baseUrl = 'http://127.0.0.1:8000';

  /// Helper to fetch the current active user's JWT ID Token from Firebase Auth
  static Future<String?> _getFirebaseToken() async {
    try {
      User? user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        print("⚠️ Authentication Check Failed: No user logged into Firebase.");
        return null;
      }
      // Force refresh the token to verify it hasn't expired
      return await user.getIdToken(true);
    } catch (e) {
      print("❌ Error fetching active token from Firebase session: $e");
      return null;
    }
  }

  /// Analyze farm-level conditions
  static Future<Map<String, dynamic>> analyzeFarm({
    required double temperatureC,
    required double humidityPct,
    required double weightChangeKg,
    required double feedIntakeKg,
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
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Farm analysis failed: ${response.statusCode} - ${response.body}');
    }
  }

  /// Analyze individual pig weight status
  static Future<Map<String, dynamic>> analyzePig({
    required String pigId,
    required String birthDate, // format: YYYY-MM-DD
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
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Pig analysis failed: ${response.statusCode} - ${response.body}');
    }
  }
}