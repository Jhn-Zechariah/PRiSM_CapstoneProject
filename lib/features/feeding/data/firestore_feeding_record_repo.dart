import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/model/app_feeding_history.dart';
import '../domain/model/app_feeding_record.dart';
import '../domain/repo/feeding_record_repo.dart';

class FirestoreFeedingRecordRepo implements FeedingRecordRepo {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;



  @override
  Future<void> addFeedingRecord(AppFeedingRecord record) async {
    final docRef = _firestore
        .collection('pigs')
        .doc(record.pigId)
        .collection('feeding_records')
        .doc();

    final data = record.toMap();
    data['id'] = docRef.id;

    await docRef.set(data);
  }

  @override
  Future<void> addBatchFeedingRecords(List<AppFeedingRecord> records) async {
    // Firestore batches max out at 500 writes
    const chunkSize = 500;

    for (var i = 0; i < records.length; i += chunkSize) {
      final chunk = records.sublist(
        i,
        i + chunkSize > records.length ? records.length : i + chunkSize,
      );

      final batch = _firestore.batch();

      for (final record in chunk) {
        final docRef = _firestore
            .collection('pigs')
            .doc(record.pigId)
            .collection('feeding_records')
            .doc();

        // Reuse toMap() so no fields are lost, same as addFeedingRecord
        final data = record.toMap();
        data['id'] = docRef.id;

        batch.set(docRef, data);
      }

      await batch.commit();
    }
  }

  @override
  Future<List<AppFeedingRecord>> getFeedingRecordsForPig(String pigId) async {
    final snapshot = await _firestore
        .collection('pigs')
        .doc(pigId)
        .collection('feeding_records')
        .orderBy('timestamp', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => AppFeedingRecord.fromMap(doc.data()))
        .toList();
  }

  // ── 2. STREAM GLOBAL HISTORY (Merged here) ───────────────────────
  Stream<List<AppFeedingHistory>> streamGlobalFeedingHistory(String userId) {
    return _firestore
        .collectionGroup('feeding_records')
        .where('userId', isEqualTo: userId) // 🔹 CRITICAL Optimization
        .orderBy('timestamp', descending: true)
        .snapshots(includeMetadataChanges: false) // 🔹 Metadata Optimization
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return AppFeedingHistory.fromJson(doc.data(), doc.id);
      }).toList();
    });
  }

}