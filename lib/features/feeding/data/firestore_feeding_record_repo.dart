import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/model/app_feeding_history.dart';
import '../domain/model/app_feeding_record.dart';
import '../domain/repo/feeding_record_repo.dart';

// ── Required Firestore composite index ──────────────────────────────────────
//
// The getGlobalFeedingHistory query uses collectionGroup + where + orderBy.
// Firestore REQUIRES a composite index for this combination or the query
// will throw in production with a link to create it.
//
// Add to firestore.indexes.json:
//
// {
//   "indexes": [
//     {
//       "collectionGroup": "feeding_records",
//       "queryScope": "COLLECTION_GROUP",
//       "fields": [
//         { "fieldPath": "userId",    "order": "ASCENDING"  },
//         { "fieldPath": "timestamp", "order": "DESCENDING" }
//       ]
//     }
//   ]
// }
//
// Then deploy with: firebase deploy --only firestore:indexes
// ────────────────────────────────────────────────────────────────────────────

class FirestoreFeedingRecordRepo implements FeedingRecordRepo {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ── Single record ──────────────────────────────────────────────────────────

  @override
  Future<void> addFeedingRecord(AppFeedingRecord record) async {
    final docRef = _firestore
        .collection('pigs')
        .doc(record.pigId)
        .collection('feeding_records')
        .doc();

    await docRef.set({...record.toMap(), 'id': docRef.id});
  }

  // ── Batch records ──────────────────────────────────────────────────────────

  @override
  Future<void> addBatchFeedingRecords(List<AppFeedingRecord> records) async {
    const chunkSize = 500;

    for (var i = 0; i < records.length; i += chunkSize) {
      final end = (i + chunkSize).clamp(0, records.length);
      final chunk = records.sublist(i, end);
      final batch = _firestore.batch();

      for (final record in chunk) {
        final docRef = _firestore
            .collection('pigs')
            .doc(record.pigId)
            .collection('feeding_records')
            .doc();

        batch.set(docRef, {...record.toMap(), 'id': docRef.id});
      }

      await batch.commit();
    }
  }

  // ── Read records for a pig (LIMITED) ──────────────────────────────────────
  //
  // Uses a [limit] (default 50) to prevent unbounded reads.
  // For older records, add a startAfter cursor for pagination.

  @override
  Future<List<AppFeedingRecord>> getFeedingRecordsForPig(
      String pigId, {
        int limit = 50,
      }) async {
    final snapshot = await _firestore
        .collection('pigs')
        .doc(pigId)
        .collection('feeding_records')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map((doc) => AppFeedingRecord.fromMap(doc.data()))
        .toList();
  }

  // ── Latest single record ───────────────────────────────────────────────────

  @override
  Future<AppFeedingRecord?> getLatestFeedingRecord(String pigId) async {
    final snapshot = await _firestore
        .collection('pigs')
        .doc(pigId)
        .collection('feeding_records')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) return null;

    try {
      return AppFeedingRecord.fromMap(snapshot.docs.first.data());
    } catch (_) {
      return null;
    }
  }

  // ── Global history (paginated) ─────────────────────────────────────────────
  //
  // Returns a [FeedingHistoryQueryResult] carrying the raw DocumentSnapshot
  // cursor alongside the parsed records so callers can paginate correctly.
  //
  // Ordered by timestamp DESCENDING so the latest records always appear first.
  //
  // NOTE: Requires the composite index documented at the top of this file.

  @override
  Future<FeedingHistoryQueryResult> getGlobalFeedingHistory(
      String userId, {
        DocumentSnapshot? startAfter,
        int limit = 50,
      }) async {
    var query = _firestore
        .collectionGroup('feeding_records')
        .where('userId', isEqualTo: userId)
        .orderBy('timestamp', descending: true) // latest first
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snapshot = await query.get();

    final records = snapshot.docs
        .map((doc) => AppFeedingHistory.fromJson(doc.data(), doc.id))
        .toList();

    return FeedingHistoryQueryResult(
      records: records,
      lastDoc: snapshot.docs.isNotEmpty ? snapshot.docs.last : null,
    );
  }
}