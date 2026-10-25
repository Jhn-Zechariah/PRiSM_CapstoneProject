import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/services/ml_service.dart' show MlServiceException;
import '../../../pig_management/domain/model/app_pig.dart';
import '../../../pig_management/domain/model/app_weight_history.dart';
import '../../data/assessment_adapters.dart';
import '../../data/firestore_assessment_store.dart';
import '../../domain/growth_request.dart';
import '../../domain/model/assessment.dart';
import '../../domain/model/assessment_ui_config.dart';
import '../../domain/repo/assessment_ports.dart';
import 'assessment_card.dart';

/// Manual pig data (age, weights; labelled as manual entry) and the A1 growth trend.
/// There is no pig-temperature input anywhere in this panel.
class GrowthAssessmentPanel extends StatefulWidget {
  final AppPig pig;
  final List<AppWeightRecord> records;
  final AssessmentApi api;
  final AssessmentStore? store;
  final AssessmentUiConfig? ui;
  final String? Function()? userId;
  final DateTime Function() clock;

  GrowthAssessmentPanel({
    super.key,
    required this.pig,
    required this.records,
    AssessmentApi? api,
    AssessmentStore? store,
    this.ui,
    this.userId,
    DateTime Function()? clock,
  })  : api = api ?? const MlAssessmentApi(),
        store = store ?? FirestoreAssessmentStore(),
        clock = clock ?? DateTime.now;

  @override
  State<GrowthAssessmentPanel> createState() => _GrowthAssessmentPanelState();
}

class _GrowthAssessmentPanelState extends State<GrowthAssessmentPanel> {
  AssessmentUiConfig? _ui;
  Assessment? _result;
  String? _msg;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _ui = widget.ui;
    if (_ui == null) {
      AssessmentUiConfig.load().then((c) {
        if (mounted) setState(() => _ui = c);
      });
    }
    _assess();
  }

  @override
  void didUpdateWidget(GrowthAssessmentPanel old) {
    super.didUpdateWidget(old);
    if (old.pig.pigId != widget.pig.pigId || !identical(old.records, widget.records)) _assess();
  }

  Future<void> _assess() async {
    setState(() => _loading = true);
    Assessment? a;
    String? msg;
    try {
      a = Assessment.fromApi(await widget.api.pigGrowth(growthRequestBody(widget.pig, widget.records)));
      final uid = widget.userId?.call();
      if (uid != null && widget.store != null) {
        unawaited(widget.store!
            .save(a, userId: uid, subjectId: widget.pig.pigId, rawRef: {
              'path': 'pigs/${widget.pig.pigId}/weight_history',
              'docIds': [for (final r in widget.records) r.id],
            })
            .catchError((Object e) => debugPrint('assessment not stored: ${e.runtimeType}')));
      }
    } on MlServiceException catch (e) {
      msg = e.statusCode == 422 ? 'rejected_input' : 'api_unavailable';
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      _result = a;
      _msg = msg;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ui = _ui;
    if (ui == null) return const SizedBox.shrink();
    final manual = ui.t('fields', 'source_manual');
    final latest = widget.records.isEmpty
        ? null
        : widget.records.reduce((a, b) => a.dateRecorded.isAfter(b.dateRecorded) ? a : b);
    final age = widget.clock().difference(widget.pig.birthDate).inDays;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Card(
        key: const Key('manual-pig-data'),
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(ui.t('sections', 'manual_data'), style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('${ui.t('pig', 'age')}: $age ${ui.t('pig', 'days')} ($manual)'),
            Text('${ui.t('pig', 'latest_weight')}: ${latest == null ? '–' : '${latest.weightKg} kg'} ($manual)'),
            Text('${ui.t('pig', 'weighins')}: ${widget.records.length}'),
          ]),
        ),
      ),
      AssessmentCard(
        title: ui.t('sections', 'growth'),
        ui: ui,
        assessment: _result,
        loading: _loading,
        stateMessage: _msg == null ? null : ui.t('states', _msg!),
      ),
    ]);
  }
}
