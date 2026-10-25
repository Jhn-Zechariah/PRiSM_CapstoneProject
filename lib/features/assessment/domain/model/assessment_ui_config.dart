import 'dart:convert';

import 'package:flutter/services.dart';

/// Wording and UI settings from assets/config/assessment_ui.json.
class AssessmentUiConfig {
  static const assetPath = 'assets/config/assessment_ui.json';
  final Map<String, dynamic> raw;

  AssessmentUiConfig(this.raw);

  static Future<AssessmentUiConfig>? _cached;

  /// Loaded once and shared (pig cards build one per pig).
  static Future<AssessmentUiConfig> cached() => _cached ??= load();

  static Future<AssessmentUiConfig> load([AssetBundle? bundle]) async {
    final text = await (bundle ?? rootBundle).loadString(assetPath);
    return AssessmentUiConfig(jsonDecode(text) as Map<String, dynamic>);
  }

  /// Text for [section].[key]; shows the key itself if the config lacks it.
  String t(String section, String key) {
    final s = raw[section];
    if (s is Map && s[key] != null) return s[key].toString();
    return '$section.$key';
  }

  int get refreshSeconds => (raw['refresh_seconds'] as num).toInt();
  String get adminClaim => raw['role']['admin_claim'] as String;
  String get adminValue => raw['role']['admin_value'] as String;
}
