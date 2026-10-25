// SYNTHETIC fixtures only (see helpers.dart).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/features/assessment/data/firestore_assessment_store.dart';
import 'package:prism_app/features/assessment/domain/live_reading.dart';
import 'package:prism_app/features/assessment/domain/model/assessment.dart';
import 'package:prism_app/features/assessment/domain/rule_fallback.dart';

import 'helpers.dart';

void main() {
  final ui = loadUi();
  final now = DateTime.utc(2026, 10, 19, 6);

  test('every API fixture parses into the Dart model', () {
    for (final f in Directory('test/assessment/fixtures').listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.startsWith('SYNTHETIC_') || name.contains('rules') || name.contains('model_active')) continue;
      final a = Assessment.fromApi(fixture(name));
      expect(a.statusLabel, isNotEmpty, reason: name);
      expect(a.inputs.every((i) => i.source == 'sensor' || i.source == 'manual'), isTrue);
    }
  });

  test('THI formula evaluation matches the hand-computed value', () {
    const expr = '(1.8*T + 32) - (0.55 - 0.0055*RH) * (1.8*T - 26)';
    expect(evalFormula(expr, {'T': 30, 'RH': 80}), closeTo(82.92, 1e-9)); // 86 - 0.11*28
    expect(evalFormula(expr, {'T': 20, 'RH': 100}), closeTo(68.0, 1e-9));
    expect(evalFormula('2 ** 3 * -1', {}), -8.0);
    expect(() => evalFormula('X + 1', {}), throwsFormatException);
    expect(() => evalFormula('T; 1', {'T': 1}), throwsFormatException);
  });

  test('phone fallback uses the cached rule config and is never ML', () {
    final rules = fixture('SYNTHETIC_rules.json');
    final a = localThiBand(rules, 30, 80, ui: ui, now: now);
    expect(a.status, 'heat_risk');
    expect(a.method, 'rule');
    expect(a.origin, 'phone');
    expect(a.forecast, isNull);
    expect(localThiBand(rules, 30, 130, ui: ui, now: now).dataQualityStatus, 'invalid');
    expect(localThiBand(rules, null, 80, ui: ui, now: now).dataQualityStatus, 'insufficient');
    (rules['thi']['categories']['Grower'] as Map)['thresholds'] = null;
    expect(localThiBand(rules, 30, 80, ui: ui, now: now).status, 'not_configured');
  });

  test('live reading mapping: invalid values are not sent, NTP failure uses phone time', () {
    final r = LiveReading.fromLive({...syntheticLive(ts: '1970-01-01T00:00:00Z'), 'ambientTempValid': false}, now)!;
    expect(r.phoneTime, isTrue);
    expect(r.time, now);
    final env = r.environmentBody()['readings'][0] as Map;
    expect(env['dht_temp_c'], isNull);
    expect(env['dht_temp_valid'], isFalse);
    expect((r.penThermalBody()['current'] as Map)['dht_temp_c__state'], 'sensor_offline');
  });

  test('stored result document: separate collection, deterministic id, links the raw data', () {
    final a = Assessment.fromApi(fixture('SYNTHETIC_env_forecast.json'));
    final doc = FirestoreAssessmentStore.buildDoc(a,
        userId: 'SYN-user', subjectId: 'pen', rawRef: {'path': 'live_sensor/latest', 'docId': null});
    expect(FirestoreAssessmentStore.collection, 'assessment_results');
    for (final k in ['modelVersion', 'method', 'inputSummary', 'assessedAt', 'observedAt', 'rawRef', 'userId']) {
      expect(doc.containsKey(k), isTrue, reason: k);
    }
    expect(doc['modelVersion'], 'SYN-v1');
    expect(doc['method'], 'rule+ML');
    final id1 = FirestoreAssessmentStore.docId('thi_band', 'pen', a.observedAt);
    expect(id1, FirestoreAssessmentStore.docId('thi_band', 'pen', a.observedAt));
    expect(id1, isNot(contains('/')));
  });
}
