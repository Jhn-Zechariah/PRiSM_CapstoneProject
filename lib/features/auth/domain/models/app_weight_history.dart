import 'package:cloud_firestore/cloud_firestore.dart';

class AppWeightRecord {
  final String id;
  final double weightKg;
  final DateTime dateRecorded;
  final String notes;

  AppWeightRecord({
    required this.id,
    required this.weightKg,
    required this.dateRecorded,
    required this.notes,
  });

  factory AppWeightRecord.fromJson(Map<String, dynamic> json, String documentId) {
    return AppWeightRecord(
      id: documentId,
      weightKg: (json['weightKg'] ?? 0).toDouble(),
      dateRecorded: (json['dateRecorded'] as Timestamp?)?.toDate() ?? DateTime.now(),
      notes: json['notes'] ?? '',
    );
  }
}