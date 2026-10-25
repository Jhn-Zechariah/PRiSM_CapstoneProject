// Test helpers. Every fixture under test/assessment/fixtures is SYNTHETIC: generated
// by the real API code (prism-ml2.0) from synthetic inputs, never real farm data.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/core/services/ml_service.dart';
import 'package:prism_app/features/assessment/domain/model/assessment.dart';
import 'package:prism_app/features/assessment/domain/model/assessment_ui_config.dart';
import 'package:prism_app/features/assessment/domain/repo/assessment_ports.dart';

AssessmentUiConfig loadUi() =>
    AssessmentUiConfig(jsonDecode(File(AssessmentUiConfig.assetPath).readAsStringSync()) as Map<String, dynamic>);

Map<String, dynamic> fixture(String name) =>
    jsonDecode(File('test/assessment/fixtures/$name').readAsStringSync()) as Map<String, dynamic>;

/// Live payload shaped like LiveSensorService.latestData (SYNTHETIC values).
Map<String, dynamic> syntheticLive({String ts = '2026-10-19T05:59:50Z'}) => {
      'timestamp': ts,
      'ambientTemp': 30.0,
      'ambientTempValid': true,
      'ambientHumidity': 80.0,
      'ambientHumidityValid': true,
      'pigBodyTemp': 33.0,
      'pigBodyTempValid': true,
      'sprinkler': false,
      '_synthetic': true,
    };

class FakeApi implements AssessmentApi {
  Map<String, dynamic>? env, growth, thermal, rules, model;
  MlServiceException? error;
  final calls = <String>[];
  final bodies = <String, Map<String, dynamic>>{};

  Future<Map<String, dynamic>> _r(String name, Map<String, dynamic>? v, [Map<String, dynamic>? body]) async {
    calls.add(name);
    if (body != null) bodies[name] = body;
    if (error != null) throw error!;
    if (v == null) throw MlServiceException(null, 'no fake response');
    return v;
  }

  @override
  Future<Map<String, dynamic>> environment(Map<String, dynamic> body) => _r('environment', env, body);
  @override
  Future<Map<String, dynamic>> pigGrowth(Map<String, dynamic> body) => _r('pigGrowth', growth, body);
  @override
  Future<Map<String, dynamic>> penThermal(Map<String, dynamic> body) => _r('penThermal', thermal, body);
  @override
  Future<Map<String, dynamic>> ruleConfig() => _r('ruleConfig', rules);
  @override
  Future<Map<String, dynamic>> activeModel() => _r('activeModel', model);
}

class FakeStore implements AssessmentStore {
  final saved = <Map<String, dynamic>>[];
  @override
  Future<void> save(Assessment a,
      {required String userId, required String subjectId, required Map<String, dynamic> rawRef}) async {
    saved.add({'a': a, 'userId': userId, 'subjectId': subjectId, 'rawRef': rawRef});
  }
}

class FakeCache implements RuleConfigCache {
  Map<String, dynamic>? value;
  FakeCache([this.value]);
  @override
  Future<Map<String, dynamic>?> load() async => value;
  @override
  Future<void> save(Map<String, dynamic> rules) async => value = rules;
}

class FakeRoles implements RoleChecker {
  final bool admin;
  FakeRoles(this.admin);
  @override
  Future<bool> isAdmin() async => admin;
}

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

/// All visible text, for wording checks.
String visibleText(WidgetTester tester) {
  final texts = tester.widgetList<Text>(find.byType(Text));
  return texts.map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join('\n');
}

const bannedWords = ['diagnos', 'fever', 'disease', 'sick', 'illness', 'infection', 'probability'];

/// Simulates a Firestore write failure (e.g. offline quota / permission error).
class ThrowingStore implements AssessmentStore {
  int attempts = 0;
  @override
  Future<void> save(Assessment a,
      {required String userId, required String subjectId, required Map<String, dynamic> rawRef}) async {
    attempts++;
    throw Exception('SYNTHETIC Firestore write failure');
  }
}
