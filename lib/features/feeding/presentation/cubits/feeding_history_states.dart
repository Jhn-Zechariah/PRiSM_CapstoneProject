import '../../domain/model/app_feeding_history.dart';

abstract class FeedingHistoryState {
  const FeedingHistoryState();
}

class FeedingHistoryInitial extends FeedingHistoryState {}

class FeedingHistoryLoading extends FeedingHistoryState {}

class FeedingHistoryLoaded extends FeedingHistoryState {
  final List<AppFeedingHistory> historyRecords;

  const FeedingHistoryLoaded(this.historyRecords);
}

class FeedingHistoryError extends FeedingHistoryState {
  final String message;

  const FeedingHistoryError(this.message);
}