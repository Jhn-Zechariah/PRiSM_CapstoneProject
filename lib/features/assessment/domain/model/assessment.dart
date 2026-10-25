/// One assessment result as returned by the PRISM API (prism-ml2.0/app/schemas.py
/// AssessmentOut), or computed on the phone by the rule fallback (origin = 'phone').
class AssessmentInput {
  final String name;
  final dynamic value;
  final String? unit;
  final String source; // 'sensor' | 'manual'
  final DateTime? observedAt;

  AssessmentInput({required this.name, this.value, this.unit, required this.source, this.observedAt});

  factory AssessmentInput.fromJson(Map<String, dynamic> j) => AssessmentInput(
        name: j['name'] as String,
        value: j['value'],
        unit: j['unit'] as String?,
        source: j['source'] as String,
        observedAt: j['observed_at'] == null ? null : DateTime.tryParse(j['observed_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'value': value,
        'unit': unit,
        'source': source,
        'observedAt': observedAt?.toUtc().toIso8601String(),
      };
}

class AssessmentForecast {
  final String target;
  final int horizonMinutes;
  final double value;
  final String? projectedBand;
  final String modelVersion;
  final String note;

  AssessmentForecast({required this.target, required this.horizonMinutes, required this.value,
      this.projectedBand, required this.modelVersion, required this.note});

  factory AssessmentForecast.fromJson(Map<String, dynamic> j) => AssessmentForecast(
        target: j['target'] as String,
        horizonMinutes: (j['horizon_minutes'] as num).toInt(),
        value: (j['value'] as num).toDouble(),
        projectedBand: j['projected_band'] as String?,
        modelVersion: j['model_version'] as String,
        note: j['note'] as String,
      );

  Map<String, dynamic> toJson() => {
        'target': target,
        'horizonMinutes': horizonMinutes,
        'value': value,
        'projectedBand': projectedBand,
        'modelVersion': modelVersion,
      };
}

class Assessment {
  final String component; // thi_band | growth_trend | pen_thermal
  final String status;
  final String statusLabel;
  final String method; // rule | statistical | rule+ML
  final List<String> reasons;
  final List<AssessmentInput> inputs;
  final String dataQualityStatus; // ok | warning | stale | offline | invalid | insufficient
  final List<String> warnings;
  final List<String> configWarnings;
  final String configVersion;
  final String? modelVersion;
  final AssessmentForecast? forecast;
  final DateTime? timestamp;
  final String disclaimer;
  final Map<String, dynamic> details;
  final String origin; // 'api' | 'phone'

  Assessment({
    required this.component,
    required this.status,
    required this.statusLabel,
    required this.method,
    required this.reasons,
    required this.inputs,
    required this.dataQualityStatus,
    required this.warnings,
    required this.configWarnings,
    required this.configVersion,
    this.modelVersion,
    this.forecast,
    this.timestamp,
    required this.disclaimer,
    this.details = const {},
    this.origin = 'api',
  });

  factory Assessment.fromApi(Map<String, dynamic> j) {
    final out = j['output'] as Map<String, dynamic>;
    return Assessment(
      component: out['component'] as String,
      status: out['status'] as String,
      statusLabel: out['status_label'] as String,
      method: j['method'] as String,
      reasons: List<String>.from(j['reasons'] as List),
      inputs: (j['inputs_summary'] as List)
          .map((e) => AssessmentInput.fromJson(e as Map<String, dynamic>))
          .toList(),
      dataQualityStatus: j['data_quality_status'] as String,
      warnings: List<String>.from(j['data_quality_warnings'] as List),
      configWarnings: List<String>.from(j['config_warnings'] as List? ?? const []),
      configVersion: j['config_version'] as String,
      modelVersion: j['model_version'] as String?,
      forecast: j['forecast'] == null
          ? null
          : AssessmentForecast.fromJson(j['forecast'] as Map<String, dynamic>),
      timestamp: DateTime.tryParse(j['timestamp'] as String),
      disclaimer: j['disclaimer'] as String,
      details: Map<String, dynamic>.from(out['details'] as Map? ?? const {}),
    );
  }

  /// When the underlying reading was taken (first input that has a time).
  DateTime? get observedAt {
    for (final i in inputs) {
      if (i.observedAt != null) return i.observedAt;
    }
    return null;
  }
}
