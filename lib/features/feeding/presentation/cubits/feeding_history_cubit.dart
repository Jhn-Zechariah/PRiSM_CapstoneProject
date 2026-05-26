import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../data/firestore_feeding_record_repo.dart'; // 👈 Points to the combined repo now
import 'feeding_history_states.dart';

class FeedingHistoryCubit extends Cubit<FeedingHistoryState> {
  final FirestoreFeedingRecordRepo _repo; // 👈 Updated class type
  StreamSubscription? _historySubscription;

  FeedingHistoryCubit({required FirestoreFeedingRecordRepo repo})
      : _repo = repo,
        super(FeedingHistoryInitial());

  void loadGlobalFeedingHistory() {
    emit(FeedingHistoryLoading());

    _historySubscription?.cancel();

    _historySubscription = _repo.streamGlobalFeedingHistory().listen(
          (records) {
        emit(FeedingHistoryLoaded(records));
      },
      onError: (error) {
        emit(FeedingHistoryError("Failed to fetch history: ${error.toString()}"));
      },
    );
  }

  @override
  Future<void> close() {
    _historySubscription?.cancel();
    return super.close();
  }
}