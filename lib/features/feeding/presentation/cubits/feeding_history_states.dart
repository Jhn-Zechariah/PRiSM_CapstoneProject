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

  const FeedingHistoryLoaded(this.historyRecords, {this.hasMore = false});

  @override
  List<Object?> get props => [historyRecords, hasMore];
}

class FeedingHistoryError extends FeedingHistoryState {
  final String message;

  const FeedingHistoryError(this.message);

  @override
  List<Object?> get props => [message];
}