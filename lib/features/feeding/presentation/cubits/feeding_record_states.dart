import 'package:equatable/equatable.dart';
import '../../domain/model/app_feeding_record.dart';

abstract class FeedingRecordState extends Equatable {
  const FeedingRecordState();

  @override
  List<Object?> get props => [];
}

class FeedingRecordInitial extends FeedingRecordState {}

class FeedingRecordLoading extends FeedingRecordState {}

class FeedingRecordLoaded extends FeedingRecordState {
  final List<AppFeedingRecord> records;

  const FeedingRecordLoaded(this.records);

  @override
  List<Object?> get props => [records];
}

class FeedingRecordError extends FeedingRecordState {
  final String message;

  const FeedingRecordError(this.message);

  @override
  List<Object?> get props => [message];
}

class LatestFeedingRecordLoading extends FeedingRecordState {
  final String pigId;

  const LatestFeedingRecordLoading(this.pigId);

  @override
  List<Object?> get props => [pigId];
}

class LatestFeedingRecordLoaded extends FeedingRecordState {
  final String pigId;
  final AppFeedingRecord? record;

  const LatestFeedingRecordLoaded(this.pigId, this.record);

  @override
  List<Object?> get props => [pigId, record];
}

class LatestFeedingRecordError extends FeedingRecordState {
  final String pigId;
  final String message;

  const LatestFeedingRecordError(this.pigId, this.message);

  @override
  List<Object?> get props => [pigId, message];
}

/// FIX #4: New state for batch updates. Carries the pigId -> record map for
/// every pig affected by a batch save, so multiple expanded cards can all
/// refresh from a single emission instead of N separate state changes.
class LatestFeedingRecordsBulkUpdated extends FeedingRecordState {
  final Map<String, AppFeedingRecord?> updates;

  const LatestFeedingRecordsBulkUpdated(this.updates);

  @override
  List<Object?> get props => [updates];
}