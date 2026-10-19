import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'ml_http_client_stub.dart'
    if (dart.library.io) 'ml_http_client_io.dart';

/// Thrown when the ML API cannot be used (not configured, offline, auth or
/// server problem). [message] is safe to show to farmers.
class MlUnavailable implements Exception {
  final String message;
  const MlUnavailable(this.message);
  @override
  String toString() => message;
}

/// One sentence of actionable guidance returned by the API.
class InsightSentence {
  final String text;
  final String kind; // status, observation, evidence, why, action, safety, data_quality, ...
  final List<String> references;
  const InsightSentence(this.text, this.kind, this.references);

  factory InsightSentence.fromJson(Map<String, dynamic> j) => InsightSentence(
    j['text'] as String? ?? '',
    j['kind'] as String? ?? '',
    List<String>.from(j['references'] as List? ?? const []),
  );
}

/// Parsed response of POST /v1/assessments (API contract v1, see
/// docs/API_REFERENCE.md). Field names are checked by
/// ml/tests/contract/assessment_response_keys.json.
class AssessmentResult {
  /// Good / Needs Attention / High Risk (only from the trained model), or an
  /// operational state: Insufficient Data / Sensor Check Required /
  /// Classification Unavailable / Uncertain.
  final String status;

  /// "thermal" when the status comes from the approved model, otherwise
  /// "operational".
  final String statusKind;
  final String? reason;
  final DateTime? observedAt;
  final double? confidence;
  final List<InsightSentence> insights;
  final List<String> dataQualityMessages;
  final String disclaimer;

  const AssessmentResult({
    required this.status,
    required this.statusKind,
    required this.reason,
    required this.observedAt,
    required this.confidence,
    required this.insights,
    required this.dataQualityMessages,
    required this.disclaimer,
  });

  bool get isThermalStatus => statusKind == 'thermal';

  List<String> get insightTexts => insights.map((i) => i.text).toList();

  factory AssessmentResult.fromJson(Map<String, dynamic> j) {
    final dq = (j['data_quality'] as Map?)?.cast<String, dynamic>() ?? {};
    final issues = (dq['issues'] as List? ?? const [])
        .whereType<Map>()
        .map((i) => i['message'] as String? ?? '')
        .where((m) => m.isNotEmpty)
        .toList();
    return AssessmentResult(
      status: j['status'] as String? ?? 'Classification Unavailable',
      statusKind: j['status_kind'] as String? ?? 'operational',
      reason: j['reason'] as String?,
      observedAt: DateTime.tryParse(j['observed_at'] as String? ?? '')?.toLocal(),
      confidence: (j['confidence'] as num?)?.toDouble(),
      insights: (j['insights'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => InsightSentence.fromJson(e.cast<String, dynamic>()))
          .toList(),
      dataQualityMessages: issues,
      disclaimer: j['disclaimer'] as String? ?? '',
    );
  }

  /// Local operational result used when there is no reading to send at all.
  factory AssessmentResult.noReading() => const AssessmentResult(
    status: 'Insufficient Data',
    statusKind: 'operational',
    reason: 'no_reading',
    observedAt: null,
    confidence: null,
    insights: [
      InsightSentence(
        'No sensor reading has been received yet, so PRISM cannot assess the '
        "pigs' thermal condition. Check the device and observe the pigs in person.",
        'status',
        [],
      ),
    ],
    dataQualityMessages: [],
    disclaimer: '',
  );
}

class MlService {
  /// API base URL, injected at build time:
  ///   flutter run --dart-define=PRISM_API_BASE_URL=https://api.example.org
  /// Release builds require https. Plain http is accepted only in debug
  /// builds (e.g. a laptop on the same LAN during development). For a free
  /// self-hosted server, also pass PRISM_API_CA_PEM_B64 (see below).
  static const String baseUrl = String.fromEnvironment('PRISM_API_BASE_URL');

  /// Optional base64 PEM of the project's own CA for a self-hosted API
  /// (see ml/scripts/make_local_tls.sh). Public certificate, not a secret.
  static const String _caPemBase64 = String.fromEnvironment('PRISM_API_CA_PEM_B64');

  static const Duration _timeout = Duration(seconds: 8);

  static Uri _endpoint(String path) {
    if (baseUrl.isEmpty) {
      throw const MlUnavailable(
        'The PRISM analysis service is not configured in this build.',
      );
    }
    final uri = Uri.parse('$baseUrl$path');
    if (uri.scheme != 'https' && !kDebugMode) {
      throw const MlUnavailable(
        'The PRISM analysis service must use a secure (https) connection.',
      );
    }
    return uri;
  }

  static Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const MlUnavailable('Please sign in to view PRISM analysis.');
    }
    final token = await user.getIdToken();
    if (token == null) {
      throw const MlUnavailable('Please sign in again to view PRISM analysis.');
    }
    return token;
  }

  static double? _num(dynamic v) => v is num ? v.toDouble() : null;
  static bool? _bool(dynamic v) => v is bool ? v : null;

  static String? _timestamp(dynamic ts) {
    DateTime? t;
    if (ts is Timestamp) t = ts.toDate();
    if (ts is String) t = DateTime.tryParse(ts);
    return t?.toUtc().toIso8601String();
  }

  /// Builds the v1 request body from the live sensor map published by
  /// LiveSensorService (ESP32 LAN `/sensor` JSON or Firestore
  /// `live_sensor/latest`). Values are passed through unchanged: missing or
  /// invalid readings are sent as missing so the server's data-quality layer
  /// can report them. Nothing is substituted with placeholder values.
  ///
  /// Field mapping for the deployed firmware (prismoct12, 2026-10-12):
  /// `ambientTemp`/`ambientTempValid` = DHT22 air temperature,
  /// `ambientHumidity`/`ambientHumidityValid` = DHT22 humidity,
  /// `thermalPixels`/`thermalValid` = AMG8833 frame. `pigBodyTemp` (the
  /// AMG8833 maximum pixel) is NOT sent: the server derives thermal features
  /// from the full frame. An older firmware (prismarduino, 2026-10-10) put the
  /// AMG8833 maximum into `ambientTemp`; it must not be used with this app.
  static Map<String, dynamic> requestFromSensorData(Map<String, dynamic> d) {
    final pixels = d['thermalPixels'];
    return {
      'schema_version': '1',
      'observed_at': _timestamp(d['timestamp']),
      'air_temp_c': _num(d['ambientTemp']),
      'air_temp_valid': _bool(d['ambientTempValid']),
      'relative_humidity_pct': _num(d['ambientHumidity'] ?? d['humidity']),
      'humidity_valid': _bool(d['ambientHumidityValid'] ?? d['humidityValid']),
      'thermal_pixels_c': pixels is List
          ? pixels.map((p) => (p as num).toDouble()).toList()
          : null,
      'thermal_valid': _bool(d['thermalValid']),
      'water_level_pct': _num(d['waterPct']),
      'water_valid': _bool(d['waterValid']),
      // Sensor calibration profile set in the firmware (CALIBRATION_PROFILE);
      // must match the profile the approved model was trained with.
      'calibration_profile': d['calibrationProfile'] is String
          ? d['calibrationProfile'] as String
          : null,
    };
  }

  /// Current thermal-status assessment for the latest live reading.
  static Future<AssessmentResult> assess(Map<String, dynamic>? sensorData) async {
    if (sensorData == null) return AssessmentResult.noReading();
    final body = requestFromSensorData(sensorData);
    if (body['observed_at'] == null) return AssessmentResult.noReading();

    final uri = _endpoint('/v1/assessments');
    final token = await _idToken();
    final client = createMlHttpClient(_caPemBase64);
    final http.Response response;
    try {
      response = await client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const MlUnavailable('The PRISM analysis service did not respond.');
    } catch (_) {
      throw const MlUnavailable(
        'Cannot reach the PRISM analysis service. Check the connection.',
      );
    } finally {
      client.close();
    }

    switch (response.statusCode) {
      case 200:
        return AssessmentResult.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      case 401:
        throw const MlUnavailable('Please sign in again to view PRISM analysis.');
      case 429:
        throw const MlUnavailable('Too many requests. PRISM will retry shortly.');
      default:
        debugPrint('[MlService] HTTP ${response.statusCode}');
        throw const MlUnavailable(
          'The PRISM analysis service is temporarily unavailable.',
        );
    }
  }

  /// Individual pig weight/growth analysis. There is no validated growth
  /// model or backend endpoint (the previous one was trained on synthetic,
  /// rule-labelled data), so this fails fast with an explanation instead of
  /// calling a non-existent endpoint.
  static Future<Map<String, dynamic>> analyzePig({
    required String pigId,
    required String birthDate,
    required double currentWeight,
    required double birthWeight,
  }) async {
    throw const MlUnavailable(
      'Weight analysis is not available yet: PRISM has no validated growth model.',
    );
  }
}
