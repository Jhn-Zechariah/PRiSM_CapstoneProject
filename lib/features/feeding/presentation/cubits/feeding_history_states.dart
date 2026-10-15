import 'package:equatable/equatable.dart';
import '../../domain/model/app_feeding_history.dart';

abstract class FeedingHistoryState extends Equatable {
  const FeedingHistoryState();

  @override
  List<Object?> get props => [];
}

class FeedingHistoryInitial extends FeedingHistoryState {
  const FeedingHistoryInitial();
}

class FeedingHistoryLoading extends FeedingHistoryState {
  const FeedingHistoryLoading();
}

/// Emitted while an additional page is being fetched so the UI can keep
/// showing the existing list rather than a full-screen spinner.
class FeedingHistoryLoadingMore extends FeedingHistoryState {
  final List<AppFeedingHistory> currentRecords;

  const FeedingHistoryLoadingMore(this.currentRecords);

  @override
  List<Object?> get props => [currentRecords];
}

class FeedingHistoryLoaded extends FeedingHistoryState {
  final List<AppFeedingHistory> historyRecords;

  /// True when Firestore returned a full page, meaning more pages may exist.
  final bool hasMore;

  /// Set when fetching the next page failed. The loaded records stay visible
  /// and the list offers a retry instead of being replaced by an error.
  final bool loadMoreFailed;

  const FeedingHistoryLoaded(
    this.historyRecords, {
    this.hasMore = false,
    this.loadMoreFailed = false,
  });

  @override
  List<Object?> get props => [historyRecords, hasMore, loadMoreFailed];
}

class FeedingHistoryError extends FeedingHistoryState {
  final String message;

  const FeedingHistoryError(this.message);

  @override
  List<Object?> get props => [message];
}