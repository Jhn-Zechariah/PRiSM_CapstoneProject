// pubspec.yaml ->  dependencies:  http: ^1.2.0
import 'dart:convert';
import 'package:http/http.dart' as http;

class MlService {
  static const _base = 'https://YOUR-APP.up.railway.app'; // your Railway domain (https)
  static const _apiKey = ''; // optional: same value as PRISM_API_KEY on Railway

  static Future<Map<String, dynamic>> _post(String path, Map<String, dynamic> body) async {
    final res = await http
        .post(Uri.parse('$_base$path'),
            headers: {
              'Content-Type': 'application/json',
              if (_apiKey.isNotEmpty) 'x-api-key': _apiKey,
            },
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 25)); // first request after idle can be slow
    if (res.statusCode != 200) {
      throw Exception('Analysis unavailable (${res.statusCode})');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Farm-level environment analysis.
  static Future<Map<String, dynamic>> analyzeFarm({
    required double bodyTemp,
    required double ambientTemp,
    required double humidity,
  }) =>
      _post('/predict/farm', {
        'body_temp': bodyTemp,
        'ambient_temp': ambientTemp,
        'humidity': humidity,
      });

  /// Per-pig growth analysis. Needs the latest TWO weigh-ins.
  static Future<Map<String, dynamic>> analyzePigGrowth({
    required int ageDays,
    required double currentWeightKg,
    required double previousWeightKg,
    required int daysBetween,
  }) =>
      _post('/predict/pig-growth', {
        'age_days': ageDays,
        'current_weight_kg': currentWeightKg,
        'previous_weight_kg': previousWeightKg,
        'days_between': daysBetween,
      });
}

// Usage idea (pig screen):
//   final ageDays     = DateTime.now().difference(pig.birthDate).inDays;
//   final daysBetween = latest.date.difference(previous.date).inDays;   // must be >= 1
//   if (history.length < 2) -> show "At least two weight records are needed for growth analysis."
//   final r = await MlService.analyzePigGrowth(...);
//   show r['status'], r['growth_ratio_pct'], r['recommendations'], and ALWAYS r['disclaimer'].
