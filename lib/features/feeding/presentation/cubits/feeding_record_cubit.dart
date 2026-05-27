import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/model/app_feeding_record.dart';
import '../../domain/repo/feeding_record_repo.dart';
import 'feeding_record_states.dart';

class FeedingRecordCubit extends Cubit<FeedingRecordState> {
  final FeedingRecordRepo feedingRepo;

  FeedingRecordCubit({required this.feedingRepo}) : super(FeedingRecordInitial());

  Future<void> loadRecordsForPig(String pigId) async {
    try {
      emit(FeedingRecordLoading());
      final records = await feedingRepo.getFeedingRecordsForPig(pigId);
      emit(FeedingRecordLoaded(records));
    } catch (e) {
      emit(FeedingRecordError("Failed to load records: $e"));
    }
  }

  // 👇 Modified to return Future<bool>
  Future<bool> addRecord(AppFeedingRecord record) async {
    try {
      await feedingRepo.addFeedingRecord(record);
      // Reload records after adding to update UI
      await loadRecordsForPig(record.pigId);
      return true; // Success!
    } catch (e) {
      emit(FeedingRecordError("Failed to add feeding record: $e"));
      return false; // Failed!
    }
  }

  // 👇 Added batch method returning Future<bool>
  Future<bool> addBatchRecords(List<AppFeedingRecord> records) async {
    try {
      await feedingRepo.addBatchFeedingRecords(records);
      // Note: We don't automatically call loadRecordsForPig here because
      // batch records apply to MULTIPLE pigs. The individual pig cards
      // should fetch their own data when expanded.
      return true; // Success!
    } catch (e) {
      emit(FeedingRecordError("Failed to add batch records: $e"));
      return false; // Failed!
    }
  }
}