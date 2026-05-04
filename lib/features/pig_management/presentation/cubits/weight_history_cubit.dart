import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/pig_management/presentation/cubits/weight_history_states.dart';
import '../../domain/repo/pig_repo.dart';

class WeightHistoryCubit extends Cubit<WeightHistoryState> {
  final PigRepo _pigRepo;
  StreamSubscription? _subscription;

  WeightHistoryCubit({required PigRepo pigRepo}) : _pigRepo = pigRepo, super(WeightHistoryInitial());

  void loadHistoryForPig(String pigId) {
    // Cancel any previous stream if the user switches pigs in the dropdown
    _subscription?.cancel();
    emit(WeightHistoryLoading());

    _subscription = _pigRepo.streamWeightHistory(pigId).listen(
          (records) {
        emit(WeightHistoryLoaded(records));
      },
      onError: (error) {
        emit(WeightHistoryError("Failed to load history: $error"));
      },
    );
  }

  @override
  Future<void> close() {
    _subscription?.cancel();
    return super.close();
  }
}