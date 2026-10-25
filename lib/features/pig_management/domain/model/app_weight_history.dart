import 'package:cloud_firestore/cloud_firestore.dart';

class AppWeightRecord {
  final String id;
  final double weightKg;
  final DateTime dateRecorded;
  final String notes;

  /// 'manual' or 'sensor'. Weights are entered by hand, so documents without a
  /// `source` field (all existing ones) are manual; [sourceInferred] says so.
  final String source;
  final bool sourceInferred;

  AppWeightRecord({
    required this.id,
    required this.weightKg,
    required this.dateRecorded,
    required this.notes,
    this.source = 'manual',
    this.sourceInferred = true,
  });

  factory AppWeightRecord.fromJson(Map<String, dynamic> json, String documentId) {
    return AppWeightRecord(
      id: documentId,
      weightKg: (json['weightKg'] ?? 0).toDouble(),
      dateRecorded: (json['dateRecorded'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: json['notes'] ?? '',
      source: json['source'] as String? ?? 'manual',
      sourceInferred: json['source'] == null,
    );
  }
}
