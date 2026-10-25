// SYNTHETIC fixtures only (see helpers.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/features/assessment/domain/model/assessment.dart';
import 'package:prism_app/features/assessment/presentation/components/assessment_card.dart';

import 'helpers.dart';

void main() {
  final ui = loadUi();

  Future<void> show(WidgetTester tester, {Assessment? a, bool loading = false, String? msg, bool forecast = true}) =>
      tester.pumpWidget(wrap(AssessmentCard(
          title: 'T', ui: ui, assessment: a, loading: loading, stateMessage: msg, showForecast: forecast)));

  testWidgets('loading state', (tester) async {
    await show(tester, loading: true);
    expect(find.byKey(const Key('assessment-loading')), findsOneWidget);
    expect(find.text(ui.t('states', 'loading')), findsOneWidget);
  });

  testWidgets('unavailable state when there is no result', (tester) async {
    await show(tester);
    expect(find.text(ui.t('states', 'api_unavailable')), findsOneWidget);
  });

  testWidgets('normal rule-based result without a model', (tester) async {
    await show(tester, a: Assessment.fromApi(fixture('SYNTHETIC_env_no_model.json')));
    expect(find.byKey(const Key('assessment-status')), findsOneWidget);
    expect(find.text('Heat risk'), findsOneWidget);
    expect(find.text(ui.t('methods', 'rule')), findsOneWidget);
    expect(find.text(ui.t('fields', 'no_model')), findsOneWidget);
    expect(find.byKey(const Key('assessment-forecast-none')), findsOneWidget);
    expect(find.byKey(const Key('assessment-dq')), findsNothing); // data OK -> no badge
    expect(find.textContaining('THI 82.9'), findsOneWidget); // reason from the API
  });

  testWidgets('forecast with model version when a model is active', (tester) async {
    await show(tester, a: Assessment.fromApi(fixture('SYNTHETIC_env_forecast.json')));
    expect(find.text(ui.t('methods', 'rule+ML')), findsOneWidget);
    expect(find.text('SYN-v1'), findsOneWidget);
    expect(find.byKey(const Key('assessment-forecast')), findsOneWidget);
    expect(find.textContaining('84.4'), findsOneWidget);
    expect(find.textContaining('not a probability'), findsOneWidget);
  });

  testWidgets('stale reading: badge, no forecast', (tester) async {
    await show(tester, a: Assessment.fromApi(fixture('SYNTHETIC_env_stale.json')));
    expect(find.text(ui.t('data_quality', 'stale')), findsOneWidget);
    expect(find.byKey(const Key('assessment-forecast-none')), findsOneWidget);
    expect(find.textContaining('s old (limit'), findsOneWidget);
  });

  testWidgets('insufficient data for the pen thermal check', (tester) async {
    await show(tester, a: Assessment.fromApi(fixture('SYNTHETIC_thermal_insufficient.json')), forecast: false);
    expect(find.text(ui.t('data_quality', 'insufficient')), findsOneWidget);
    expect(find.text(ui.t('methods', 'statistical')), findsOneWidget);
    expect(find.textContaining('needs 30'), findsOneWidget);
  });

  testWidgets('wording never reads as a diagnosis', (tester) async {
    for (final f in ['SYNTHETIC_env_no_model.json', 'SYNTHETIC_env_stale.json',
        'SYNTHETIC_thermal_insufficient.json', 'SYNTHETIC_growth_flags.json']) {
      await show(tester, a: Assessment.fromApi(fixture(f)));
      final text = visibleText(tester).toLowerCase().replaceAll('not a veterinary diagnosis', '');
      for (final w in bannedWords) {
        expect(text.contains(w), isFalse, reason: '$f contains "$w"');
      }
    }
  });
}
