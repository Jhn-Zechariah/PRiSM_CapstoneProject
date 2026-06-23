import 'package:cloud_firestore/cloud_firestore.dart';
import '../model/app_feeding_history.dart';
import '../model/app_feeding_record.dart';

/// Result wrapper for paginated global history queries.
///
/// Carries the raw [DocumentSnapshot] cursor alongside the parsed records
/// so callers can pass it back as [startAfter] on the next page request.
///
/// Named [FeedingHistoryQueryResult] (not FeedingHistoryPage) to avoid
/// clashing with the presentation-layer widget of the same name.
class FeedingHistoryQueryResult {
  final List<AppFeedingHistory> records;
  final DocumentSnapshot? lastDoc;

  const FeedingHistoryQueryResult({
    required this.records,
    required this.lastDoc,
  });
}

abstract class FeedingRecordRepo {
  Future<void> addFeedingRecord(AppFeedingRecord record);

  Future<void> addBatchFeedingRecords(List<AppFeedingRecord> records);

  Future<List<AppFeedingRecord>> getFeedingRecordsForPig(
      String pigId, {
        int limit = 50,
      });

  Future<AppFeedingRecord?> getLatestFeedingRecord(String pigId);

  Future<FeedingHistoryQueryResult> getGlobalFeedingHistory(
      String userId, {
        DocumentSnapshot? startAfter,
        int limit,
      });
}