import 'dart:convert';
import 'package:http/http.dart' as http;

class MlService {
  // For Android emulator on the same PC:
  static const String baseUrl = 'http://192.168.1.235:8000';
  // For physical Android phone (same Wi-Fi), change to your PC's IP:
  // static const String baseUrl = 'http://192.168.1.x:8000';

  /// Analyze farm-level conditions
  static Future<Map<String, dynamic>> analyzeFarm({
    required double temperatureC,
    required double humidityPct,
    required double weightChangeKg,
    required double feedIntakeKg,
    int medicineGiven = 0,
  }) async {
    final url = Uri.parse('$baseUrl/api/farm/analyze');

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
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
      throw Exception('Farm analysis failed: ${response.statusCode}');
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

    final response = await http.post(
      url,
      headers: {'Content-Type': 'application/json'},
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
      throw Exception('Pig analysis failed: ${response.statusCode}');
    }
  }
}
