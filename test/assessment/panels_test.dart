// SYNTHETIC fixtures and readings only (see helpers.dart).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/core/services/ml_service.dart';
import 'package:prism_app/features/assessment/presentation/components/environment_panel.dart';
import 'package:prism_app/features/assessment/presentation/components/growth_panel.dart';
import 'package:prism_app/features/assessment/presentation/pages/assessment_screen.dart';
import 'package:prism_app/features/assessment/presentation/pages/model_info_screen.dart';
import 'package:prism_app/features/pig_management/domain/model/app_pig.dart';
import 'package:prism_app/features/pig_management/domain/model/app_weight_history.dart';

import 'helpers.dart';

void main() {
  final ui = loadUi();
  final now = DateTime.utc(2026, 10, 19, 6);

  Future<void> panel(WidgetTester tester, FakeApi api, ValueNotifier<Map<String, dynamic>?> live,
      {FakeStore? store, FakeCache? cache, DateTime Function()? clock}) async {
    await tester.pumpWidget(wrap(EnvironmentPanel(
      liveData: live,
      api: api,
      store: store,
      cache: cache ?? FakeCache(),
      ui: ui,
      userId: () => 'SYN-user',
      clock: clock ?? () => now,
    )));
    await tester.pumpAndSettle();
  }

  group('environment panel', () {
    testWidgets('normal: API result shown and stored with a link to the raw reading', (tester) async {
      final api = FakeApi()
        ..env = fixture('SYNTHETIC_env_no_model.json')
        ..thermal = fixture('SYNTHETIC_thermal_insufficient.json');
      final store = FakeStore();
      await panel(tester, api, ValueNotifier(syntheticLive()), store: store);
      expect(find.text('Heat risk'), findsOneWidget);
      expect(find.textContaining('${ui.t('live', 'air_temp')}: 30.0'), findsOneWidget);
      expect(find.textContaining(ui.t('live', 'pen_surface')), findsOneWidget);
      expect(store.saved.length, 2);
      final s = store.saved.first;
      expect(s['userId'], 'SYN-user');
      expect((s['rawRef'] as Map)['path'], 'live_sensor/latest');
      final body = api.bodies['environment']!['readings'][0] as Map;
      expect(body['dht_temp_c'], 30.0);
      final pen = api.bodies['penThermal']!['current'] as Map;
      expect(pen['amg_summary_c'], 33.0); // pen-level summary, not a per-pig value
      expect(pen.keys.any((k) => k.toString().contains('pig')), isFalse);
    });

    testWidgets('API down with saved rules: phone-computed band, live readings still shown', (tester) async {
      final api = FakeApi()..error = MlServiceException(null, 'down');
      final store = FakeStore();
      await panel(tester, api, ValueNotifier(syntheticLive()),
          store: store, cache: FakeCache(fixture('SYNTHETIC_rules.json')));
      expect(find.byKey(const Key('assessment-local')), findsOneWidget);
      expect(find.text('Heat risk'), findsOneWidget); // synthetic thresholds [74, 79]
      expect(find.byKey(const Key('live-readings')), findsOneWidget);
      expect(find.textContaining('${ui.t('live', 'humidity')}: 80.0'), findsOneWidget);
      expect(store.saved, isEmpty); // phone results are not stored as API results
    });

    testWidgets('API down with no saved rules: clear unavailable state', (tester) async {
      final api = FakeApi()..error = MlServiceException(503, 'down');
      await panel(tester, api, ValueNotifier(syntheticLive()));
      expect(find.textContaining(ui.t('states', 'no_local_rules')), findsOneWidget);
      expect(find.byKey(const Key('live-readings')), findsOneWidget);
    });

    testWidgets('Firestore write failure does not break the display', (tester) async {
      final api = FakeApi()
        ..env = fixture('SYNTHETIC_env_no_model.json')
        ..thermal = fixture('SYNTHETIC_thermal_insufficient.json');
      final store = ThrowingStore();
      await tester.pumpWidget(wrap(EnvironmentPanel(
        liveData: ValueNotifier(syntheticLive()), api: api, store: store, cache: FakeCache(),
        ui: ui, userId: () => 'SYN-user', clock: () => now)));
      await tester.pumpAndSettle();
      expect(store.attempts, 2);
      expect(find.text('Heat risk'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('rejected input (422) and no reading yet', (tester) async {
      final api = FakeApi()..error = MlServiceException(422, 'bad');
      await panel(tester, api, ValueNotifier(syntheticLive()));
      expect(find.text(ui.t('states', 'rejected_input')), findsNWidgets(2));
      await panel(tester, FakeApi(), ValueNotifier(null));
      expect(find.text(ui.t('states', 'no_reading')), findsWidgets);
    });

    testWidgets('device clock not synced: phone time used and noted', (tester) async {
      final api = FakeApi()
        ..env = fixture('SYNTHETIC_env_no_model.json')
        ..thermal = fixture('SYNTHETIC_thermal_insufficient.json');
      await panel(tester, api, ValueNotifier(syntheticLive(ts: '1970-01-01T00:00:00Z')));
      expect(find.text(ui.t('states', 'phone_time')), findsOneWidget);
      expect(api.bodies['environment']!['readings'][0]['timestamp'], now.toIso8601String());
    });

    testWidgets('calls are rate-limited by refresh_seconds', (tester) async {
      final api = FakeApi()
        ..env = fixture('SYNTHETIC_env_no_model.json')
        ..thermal = fixture('SYNTHETIC_thermal_insufficient.json');
      final live = ValueNotifier<Map<String, dynamic>?>(syntheticLive());
      await panel(tester, api, live);
      live.value = syntheticLive(ts: '2026-10-19T05:59:59Z');
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c == 'environment').length, 1);
    });
  });

  group('growth panel', () {
    final pig = AppPig(
        pigId: 'SYN-pig', displayId: 'P-001', userId: 'SYN-user', breed: 'SYN', birthDate: DateTime(2026, 6, 1),
        sex: 'Female', birthWeightKg: 1.4, currentWeightKg: 16.0, notes: '', stage: 'Nursery', status: 'Normal/Healthy');
    final records = [
      for (final (i, d, kg) in [(0, DateTime(2026, 7, 1), 10.0), (1, DateTime(2026, 7, 8), 13.5),
          (2, DateTime(2026, 7, 15), 17.0), (3, DateTime(2026, 7, 22), 16.0)])
        AppWeightRecord(id: 'SYN-w$i', weightKg: kg, dateRecorded: d, notes: ''),
    ];

    testWidgets('manual data labelled as manual, growth result shown and stored', (tester) async {
      final api = FakeApi()..growth = fixture('SYNTHETIC_growth_flags.json');
      final store = FakeStore();
      await tester.pumpWidget(wrap(GrowthAssessmentPanel(
          pig: pig, records: records, api: api, store: store, ui: ui, userId: () => 'SYN-user', clock: () => now)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manual-pig-data')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('manual-pig-data')),
              matching: find.textContaining('(${ui.t('fields', 'source_manual')})')),
          findsNWidgets(2)); // age and latest weight, both labelled manual
      expect(find.textContaining('weight_kg: 16.0 kg (${ui.t('fields', 'source_manual')})'), findsOneWidget);
      expect(find.text('Check growth'), findsOneWidget);
      final body = api.bodies['pigGrowth']!;
      expect((body['weights'] as List).every((w) => w['source'] == 'manual'), isTrue);
      expect(body.toString().toLowerCase().contains('temp'), isFalse); // no pig temperature input
      expect((store.saved.single['rawRef'] as Map)['docIds'], ['SYN-w0', 'SYN-w1', 'SYN-w2', 'SYN-w3']);
    });

    testWidgets('loading then unavailable when the API is down', (tester) async {
      final api = FakeApi()..error = MlServiceException(null, 'down');
      await tester.pumpWidget(wrap(GrowthAssessmentPanel(
          pig: pig, records: records, api: api, store: FakeStore(), ui: ui, clock: () => now)));
      expect(find.byKey(const Key('assessment-loading')), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text(ui.t('states', 'api_unavailable')), findsOneWidget);
      expect(find.byKey(const Key('manual-pig-data')), findsOneWidget); // manual data still shown
    });
  });

  group('role-restricted screens', () {
    testWidgets('non-admin sees "admin required" and the model API is never called', (tester) async {
      final api = FakeApi()..model = fixture('SYNTHETIC_model_active.json');
      await tester.pumpWidget(MaterialApp(home: ModelInfoScreen(api: api, roles: FakeRoles(false), ui: ui)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('admin-required')), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    testWidgets('admin sees read-only model info with no action buttons', (tester) async {
      final api = FakeApi()..model = fixture('SYNTHETIC_model_active.json');
      await tester.pumpWidget(MaterialApp(home: ModelInfoScreen(api: api, roles: FakeRoles(true), ui: ui)));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('model-info')), findsOneWidget);
      expect(find.text('SYN-v1'), findsOneWidget);
      expect(find.byType(ElevatedButton), findsNothing);
      expect(find.byType(TextButton), findsNothing);
    });

    testWidgets('server refusal (403) is shown even if the UI thought the user was admin', (tester) async {
      final api = FakeApi()..error = MlServiceException(403, 'admin role required');
      await tester.pumpWidget(MaterialApp(home: ModelInfoScreen(api: api, roles: FakeRoles(true), ui: ui)));
      await tester.pumpAndSettle();
      expect(find.text(ui.t('states', 'admin_required')), findsOneWidget);
    });

    for (final admin in [false, true]) {
      testWidgets('assessment screen shows the model-info entry only for admin=$admin', (tester) async {
        final api = FakeApi()
          ..env = fixture('SYNTHETIC_env_no_model.json')
          ..thermal = fixture('SYNTHETIC_thermal_insufficient.json');
        await tester.pumpWidget(MaterialApp(
            home: AssessmentScreen(
                api: api, store: FakeStore(), cache: FakeCache(), roles: FakeRoles(admin), ui: ui,
                liveData: ValueNotifier(syntheticLive()), userId: () => 'SYN-user', clock: () => now)));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('open-model-info')), admin ? findsOneWidget : findsNothing);
      });
    }
  });
}
