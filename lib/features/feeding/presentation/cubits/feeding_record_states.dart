import '../../domain/model/app_feeding_record.dart';

abstract class FeedingRecordState {}

class FeedingRecordInitial extends FeedingRecordState {}

class FeedingRecordLoading extends FeedingRecordState {}

class FeedingRecordLoaded extends FeedingRecordState {
  final List<AppFeedingRecord> records;
  FeedingRecordLoaded(this.records);
}

class FeedingRecordError extends FeedingRecordState {
  final String message;
  FeedingRecordError(this.message);
}