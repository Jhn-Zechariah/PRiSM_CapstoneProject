import '../model/app_feeding_record.dart';

abstract class FeedingRecordRepo {
  Future<void> addFeedingRecord(AppFeedingRecord record);
  Future<void> addBatchFeedingRecords(List<AppFeedingRecord> records);
  Future<List<AppFeedingRecord>> getFeedingRecordsForPig(String pigId);
}