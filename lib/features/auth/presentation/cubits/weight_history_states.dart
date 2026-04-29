import '../../domain/models/app_weight_history.dart';

abstract class WeightHistoryState {}

class WeightHistoryInitial extends WeightHistoryState {}
class WeightHistoryLoading extends WeightHistoryState {}

class WeightHistoryLoaded extends WeightHistoryState {
  final List<AppWeightRecord> records;
  WeightHistoryLoaded(this.records);
}

class WeightHistoryError extends WeightHistoryState {
  final String message;
  WeightHistoryError(this.message);
}