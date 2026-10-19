import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/core/services/ml_service.dart';

/// Contract tests between the Flutter client and the PRISM ML API v1. The
/// JSON files are shared with the Python test suite (ml/tests/contract/).
void main() {
  Map<String, dynamic> load(String name) =>
      jsonDecode(File('ml/tests/contract/$name').readAsStringSync())
          as Map<String, dynamic>;

  group('requestFromSensorData', () {
    final sensor = <String, dynamic>{
      'timestamp': '2026-10-12T04:00:00Z',
      'ambientTemp': 30.1, // DHT22 air temperature (deployed firmware)
      'ambientTempValid': true,
      'pigBodyTemp': 35.4, // AMG8833 max pixel: must NOT be used as air temperature
      'ambientHumidity': 81.0,
      'ambientHumidityValid': true,
      'thermalPixels': List<num>.generate(64, (i) => 29 + i * 0.05),
      'thermalValid': true,
      'waterPct': 55,
      'waterValid': true,
    };

    test('produces exactly the v1 request fields', () {
      final body = MlService.requestFromSensorData(sensor);
      final example = load('assessment_request_example.json');
      expect(body.keys.toSet(), example.keys.toSet());
      expect(body['schema_version'], '1');
      expect(body['air_temp_c'], 30.1);
      expect((body['thermal_pixels_c'] as List).length, 64);
      expect(body['observed_at'], '2026-10-12T04:00:00.000Z');
    });

    test('never substitutes placeholder values', () {
      final body = MlService.requestFromSensorData({
        'timestamp': '2026-10-12T04:00:00Z',
        'pigBodyTemp': 35.4,
      });
      expect(body['air_temp_c'], isNull); // surface reading never used as air temperature
      expect(body['relative_humidity_pct'], isNull);
      expect(body['thermal_pixels_c'], isNull);
      expect(body['air_temp_valid'], isNull);
    });

    test('accepts the older humidity field names', () {
      final body = MlService.requestFromSensorData({
        'timestamp': '2026-10-12T04:00:00Z',
        'humidity': 70.0,
        'humidityValid': true,
      });
      expect(body['relative_humidity_pct'], 70.0);
      expect(body['humidity_valid'], true);
    });
  });

  test('deployed firmware /sensor JSON maps to a complete v1 request', () {
    final fw = load('firmware_sensor_example.json');
    final body = MlService.requestFromSensorData(fw);
    expect(body.keys.toSet(), load('assessment_request_example.json').keys.toSet());
    expect(body['air_temp_c'], fw['ambientTemp']);
    expect(body['relative_humidity_pct'], fw['ambientHumidity']);
    expect(body['thermal_pixels_c'], hasLength(64));
    expect(body.values.where((v) => v == null), isEmpty);
  });

  group('AssessmentResult.fromJson', () {
    test('parses a real API response', () {
      final r = AssessmentResult.fromJson(load('assessment_response_example.json'));
      expect(r.status, 'Classification Unavailable');
      expect(r.isThermalStatus, isFalse);
      expect(r.insights, isNotEmpty);
      expect(r.insights.every((i) => i.text.isNotEmpty), isTrue);
      expect(r.disclaimer, isNotEmpty);
    });

    test('reads every field listed in the contract', () {
      final keys = load('assessment_response_keys.json');
      final example = load('assessment_response_example.json');
      for (final k in keys['top_level'] as List) {
        expect(example.containsKey(k), isTrue, reason: 'missing $k');
      }
    });

    test('thermal status only when status_kind is thermal', () {
      final r = AssessmentResult.fromJson({
        'status': 'Good',
        'status_kind': 'thermal',
        'confidence': 0.91,
        'insights': [
          {'text': 'x.', 'kind': 'status', 'references': []},
        ],
        'data_quality': {'issues': []},
        'disclaimer': 'd',
      });
      expect(r.isThermalStatus, isTrue);
      expect(r.confidence, 0.91);
    });

    test('collects data-quality messages', () {
      final r = AssessmentResult.fromJson({
        'status': 'Sensor Check Required',
        'status_kind': 'operational',
        'insights': [],
        'data_quality': {
          'issues': [
            {'message': 'The device marked the thermal camera frame as invalid.'},
          ],
        },
      });
      expect(r.dataQualityMessages, hasLength(1));
      expect(r.isThermalStatus, isFalse);
    });

    test('no reading gives Insufficient Data, never Good', () async {
      final r = await MlService.assess(null);
      expect(r.status, 'Insufficient Data');
      expect(r.isThermalStatus, isFalse);
    });
  });

  test('pig growth analysis fails fast without a network call', () {
    expect(
      MlService.analyzePig(pigId: 'p', birthDate: '2026-01-01', currentWeight: 50, birthWeight: 1.5),
      throwsA(isA<MlUnavailable>()),
    );
  });
}
