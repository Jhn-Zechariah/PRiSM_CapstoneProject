import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/model/assessment.dart';
import '../domain/repo/assessment_ports.dart';

/// Stores assessment results in `assessment_results`, a collection separate from every
/// raw-observation collection. Documents are create-only (see firestore.rules): the
/// deterministic id means a retry for the same reading never makes a second copy, and
/// raw observations are only referenced (rawRef), never written.
class FirestoreAssessmentStore implements AssessmentStore {
  static const collection = 'assessment_results';
  final FirebaseFirestore? _db;

  FirestoreAssessmentStore([this._db]);

  static String docId(String component, String subjectId, DateTime? observedAt) {
    final key = observedAt?.toUtc().millisecondsSinceEpoch.toString() ?? 'unknown';
    return '${component}_${subjectId}_$key'.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '-');
  }

  /// Pure: the stored document (Firestore types are applied in [save]).
  static Map<String, dynamic> buildDoc(Assessment a,
      {required String userId, required String subjectId, required Map<String, dynamic> rawRef}) {
    return {
      'schemaVersion': 1,
      'userId': userId,
      'component': a.component,
      'subjectId': subjectId,
      'status': a.status,
      'statusLabel': a.statusLabel,
      'method': a.method,
      'modelVersion': a.modelVersion,
      'configVersion': a.configVersion,
      'dataQualityStatus': a.dataQualityStatus,
      'dataQualityWarnings': a.warnings,
      'inputSummary': a.inputs.map((i) => i.toJson()).toList(),
      'forecast': a.forecast?.toJson(),
      'assessedAt': a.timestamp?.toUtc().toIso8601String(),
      'observedAt': a.observedAt?.toUtc().toIso8601String(),
      'rawRef': rawRef,
      'origin': a.origin,
    };
  }

  @override
  Future<void> save(Assessment a,
      {required String userId, required String subjectId, required Map<String, dynamic> rawRef}) async {
    if (a.origin != 'api') return; // only results returned by the API are stored
    final db = _db ?? FirebaseFirestore.instance;
    final doc = buildDoc(a, userId: userId, subjectId: subjectId, rawRef: rawRef)
      ..['assessedAt'] = a.timestamp == null ? null : Timestamp.fromDate(a.timestamp!)
      ..['observedAt'] = a.observedAt == null ? null : Timestamp.fromDate(a.observedAt!)
      ..['createdAt'] = FieldValue.serverTimestamp();
    try {
      await db.collection(collection).doc(docId(a.component, subjectId, a.observedAt)).set(doc);
    } on FirebaseException catch (e) {
      // permission-denied here means the document already exists (rules forbid updates)
      if (e.code != 'permission-denied') rethrow;
    }
  }
}
