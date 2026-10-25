import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../domain/model/assessment.dart';
import '../../domain/model/assessment_ui_config.dart';

/// Shows one assessment in plain language: status, reasons, method, model version,
/// time, inputs with their source, data-quality notes and (optionally) the forecast.
/// Also renders the loading / unavailable states. All wording comes from config or the API.
class AssessmentCard extends StatelessWidget {
  final String title;
  final AssessmentUiConfig ui;
  final Assessment? assessment;
  final bool loading;
  final String? stateMessage;
  final bool showForecast;

  const AssessmentCard({
    super.key,
    required this.title,
    required this.ui,
    this.assessment,
    this.loading = false,
    this.stateMessage,
    this.showForecast = false,
  });

  static final _fmt = DateFormat('yyyy-MM-dd HH:mm');

  String _time(DateTime? t) => t == null ? '–' : _fmt.format(t.toLocal());

  Color _dqColor(String dq) => switch (dq) {
        'ok' => Colors.green.shade700,
        'warning' => Colors.orange.shade800,
        _ => Colors.red.shade700,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (loading)
              Row(children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(ui.t('states', 'loading'), key: const Key('assessment-loading')),
              ])
            else if (assessment == null)
              Text(stateMessage ?? ui.t('states', 'api_unavailable'), key: const Key('assessment-state'))
            else
              ..._body(context, assessment!),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, Assessment a) {
    final small = Theme.of(context).textTheme.bodySmall;
    String src(String s) => s == 'manual' ? ui.t('fields', 'source_manual') : ui.t('fields', 'source_sensor');
    return [
      Row(children: [
        Expanded(
          child: Text(a.statusLabel, key: const Key('assessment-status'),
              style: Theme.of(context).textTheme.headlineSmall),
        ),
        if (a.dataQualityStatus != 'ok')
          Container(
            key: const Key('assessment-dq'),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _dqColor(a.dataQualityStatus).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(ui.t('data_quality', a.dataQualityStatus),
                style: TextStyle(color: _dqColor(a.dataQualityStatus), fontWeight: FontWeight.w600)),
          ),
      ]),
      if (a.origin == 'phone')
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(ui.t('states', 'local_fallback'), key: const Key('assessment-local'), style: small),
        ),
      const SizedBox(height: 8),
      Text(ui.t('fields', 'reasons'), style: const TextStyle(fontWeight: FontWeight.w600)),
      for (final r in a.reasons) Text('• $r'),
      const SizedBox(height: 8),
      _row(ui.t('fields', 'method'), ui.t('methods', a.method), const Key('assessment-method')),
      _row(ui.t('fields', 'model_version'), a.modelVersion ?? ui.t('fields', 'no_model'),
          const Key('assessment-model')),
      _row(ui.t('fields', 'observed_at'), _time(a.observedAt), null),
      _row(ui.t('fields', 'assessed_at'), _time(a.timestamp), null),
      if (a.inputs.isNotEmpty) ...[
        const SizedBox(height: 6),
        Text(ui.t('fields', 'inputs'), style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final i in a.inputs)
          Text('${i.name}: ${i.value ?? '–'}${i.unit == null ? '' : ' ${i.unit}'} (${src(i.source)})', style: small),
      ],
      if (showForecast) ...[
        const SizedBox(height: 8),
        Text(ui.t('sections', 'forecast'), style: const TextStyle(fontWeight: FontWeight.w600)),
        if (a.forecast == null)
          Text(ui.t('states', 'forecast_none'), key: const Key('assessment-forecast-none'))
        else
          Text(
            '${a.forecast!.target.toUpperCase()} in ${a.forecast!.horizonMinutes} min: '
            '${a.forecast!.value.toStringAsFixed(1)}'
            '${a.forecast!.projectedBand == null ? '' : ' (${a.forecast!.projectedBand})'}\n${a.forecast!.note}',
            key: const Key('assessment-forecast'),
          ),
      ],
      if (a.warnings.isNotEmpty || a.configWarnings.isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(ui.t('fields', 'warnings'), style: const TextStyle(fontWeight: FontWeight.w600)),
        for (final w in [...a.warnings, ...a.configWarnings]) Text('• $w', style: small),
      ],
      const SizedBox(height: 8),
      Text(a.disclaimer, style: small?.copyWith(fontStyle: FontStyle.italic)),
    ];
  }

  Widget _row(String label, String value, Key? key) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Row(children: [
          SizedBox(width: 110, child: Text(label)),
          Expanded(child: Text(value, key: key)),
        ]),
      );
}
