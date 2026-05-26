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

    final newRecord = AppFeedingRecord(
      id: docRef.id,
      pigId: record.pigId,
      feedType: record.feedType,
      amount: record.amount,
      timestamp: record.timestamp,
    );

    await docRef.set(newRecord.toMap());
  }

  // Implement the batch function
  @override
  Future<void> addBatchFeedingRecords(List<AppFeedingRecord> records) async {
    final batch = _firestore.batch();

    for (final record in records) {
      final docRef = _firestore
          .collection('pigs')
          .doc(record.pigId)
          .collection('feeding_records')
          .doc();

      final newRecord = AppFeedingRecord(
        id: docRef.id,
        pigId: record.pigId,
        feedType: record.feedType,
        amount: record.amount,
        timestamp: record.timestamp,
      );

      batch.set(docRef, newRecord.toMap());
    }

    // Commit all records to Firestore in a single network request
    await batch.commit();
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
  Stream<List<AppFeedingHistory>> streamGlobalFeedingHistory() {
    return _firestore
        .collectionGroup('feeding_records') // Targets all subcollections across all pigs
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return AppFeedingHistory.fromJson(doc.data(), doc.id);
      }).toList();
    });
  }

}