import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/services/ml_service.dart' show MlServiceException;
import '../../domain/live_reading.dart';
import '../../domain/model/assessment.dart';
import '../../domain/model/assessment_ui_config.dart';
import '../../domain/repo/assessment_ports.dart';
import '../../domain/rule_fallback.dart';
import 'assessment_card.dart';

/// Live readings (always shown, straight from the sensor feed) plus the THI band /
/// forecast and the pen thermal check from the API. If the API is down, the THI band
/// is computed on the phone from the last saved rule config. Never sends commands.
class EnvironmentPanel extends StatefulWidget {
  final ValueListenable<Map<String, dynamic>?> liveData;
  final AssessmentApi api;
  final AssessmentStore? store;
  final RuleConfigCache cache;
  final AssessmentUiConfig ui;
  final String? Function() userId;
  final DateTime Function() clock;

  const EnvironmentPanel({
    super.key,
    required this.liveData,
    required this.api,
    required this.cache,
    required this.ui,
    required this.userId,
    required this.clock,
    this.store,
  });

  @override
  State<EnvironmentPanel> createState() => _EnvironmentPanelState();
}

class _EnvironmentPanelState extends State<EnvironmentPanel> {
  LiveReading? _reading;
  Assessment? _env, _thermal;
  String? _envMsg, _thermalMsg;
  bool _loading = false;
  DateTime? _lastCall;

  @override
  void initState() {
    super.initState();
    widget.liveData.addListener(_onData);
    widget.api.ruleConfig().then(widget.cache.save).catchError((_) {}); // refresh offline copy
    _onData();
  }

  @override
  void didUpdateWidget(EnvironmentPanel old) {
    super.didUpdateWidget(old);
    if (!identical(old.liveData, widget.liveData)) {
      old.liveData.removeListener(_onData);
      widget.liveData.addListener(_onData);
      _lastCall = null;
      _env = _thermal = null;
      _envMsg = _thermalMsg = null;
      _onData();
    }
  }

  @override
  void dispose() {
    widget.liveData.removeListener(_onData);
    super.dispose();
  }

  void _onData() {
    final r = LiveReading.fromLive(widget.liveData.value, widget.clock());
    if (!mounted) return;
    setState(() => _reading = r);
    if (r == null) return;
    final now = widget.clock();
    if (_lastCall != null && now.difference(_lastCall!).inSeconds < widget.ui.refreshSeconds) return;
    _lastCall = now;
    _assess(r);
  }

  Future<void> _assess(LiveReading r) async {
    setState(() => _loading = true);
    Assessment? env, thermal;
    String? envMsg, thermalMsg;
    try {
      env = Assessment.fromApi(await widget.api.environment(r.environmentBody()));
      _store(env, r);
    } on MlServiceException catch (e) {
      if (e.statusCode == 422) {
        envMsg = widget.ui.t('states', 'rejected_input');
      } else {
        final rules = await widget.cache.load();
        if (rules != null) {
          env = localThiBand(rules, r.usableAirTemp, r.usableHumidity,
              observedAt: r.time, ui: widget.ui, now: widget.clock());
        } else {
          envMsg = '${widget.ui.t('states', 'api_unavailable')} ${widget.ui.t('states', 'no_local_rules')}';
        }
      }
    }
    try {
      thermal = Assessment.fromApi(await widget.api.penThermal(r.penThermalBody()));
      _store(thermal, r);
    } on MlServiceException catch (e) {
      thermalMsg = e.statusCode == 422 ? widget.ui.t('states', 'rejected_input') : widget.ui.t('states', 'api_unavailable');
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _env = env;
      _envMsg = envMsg;
      _thermal = thermal;
      _thermalMsg = thermalMsg;
    });
  }

  void _store(Assessment a, LiveReading r) {
    final uid = widget.userId();
    if (uid == null || widget.store == null) return;
    unawaited(widget.store!
        .save(a, userId: uid, subjectId: 'pen', rawRef: r.rawRef())
        .catchError((Object e) => debugPrint('assessment not stored: ${e.runtimeType}')));
  }

  @override
  Widget build(BuildContext context) {
    final ui = widget.ui;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _live(ui),
      AssessmentCard(
        title: ui.t('sections', 'environment'),
        ui: ui,
        assessment: _env,
        loading: _loading && _env == null,
        stateMessage: _reading == null ? ui.t('states', 'no_reading') : _envMsg,
        showForecast: true,
      ),
      AssessmentCard(
        title: ui.t('sections', 'thermal'),
        ui: ui,
        assessment: _thermal,
        loading: _loading && _thermal == null,
        stateMessage: _reading == null ? ui.t('states', 'no_reading') : _thermalMsg,
      ),
    ]);
  }

  Widget _live(AssessmentUiConfig ui) {
    final r = _reading;
    String v(double? x, bool? valid, String unit) =>
        valid == false || x == null ? '–' : '${x.toStringAsFixed(1)} $unit';
    return Card(
      key: const Key('live-readings'),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(ui.t('sections', 'live'), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          if (r == null)
            Text(ui.t('states', 'no_reading'))
          else ...[
            Text('${ui.t('live', 'air_temp')}: ${v(r.airTempC, r.airTempValid, ui.t('live', 'unit_c'))}'),
            Text('${ui.t('live', 'humidity')}: ${v(r.humidityPct, r.humidityValid, ui.t('live', 'unit_pct'))}'),
            Text('${ui.t('live', 'pen_surface')}: ${v(r.penSurfaceC, r.penSurfaceValid, ui.t('live', 'unit_c'))}'),
            Text('${ui.t('fields', 'source')}: ${ui.t('fields', 'source_sensor')}'),
            if (r.phoneTime) Text(ui.t('states', 'phone_time'), style: const TextStyle(fontSize: 12)),
          ],
        ]),
      ),
    );
  }
}
