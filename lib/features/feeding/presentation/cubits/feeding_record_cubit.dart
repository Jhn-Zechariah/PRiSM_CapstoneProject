import 'dart:async';
import 'dart:ui';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/model/app_feeding_record.dart';
import '../../domain/repo/feeding_record_repo.dart';
import 'feeding_record_states.dart';

class FeedingRecordCubit extends Cubit<FeedingRecordState> {
  final FeedingRecordRepo feedingRepo;
  final VoidCallback? onRecordSaved;

  StreamSubscription? _authSubscription; // 🔹 NEW

  FeedingRecordCubit({
    required this.feedingRepo,
    this.onRecordSaved,
  }) : super(FeedingRecordInitial()) {
    _listenToAuthChanges(); // 🔹 NEW
  }

  final Map<String, AppFeedingRecord?> _latestRecordCache = {};

  // 🔹 NEW
  void _listenToAuthChanges() {
    _authSubscription = FirebaseAuth.instance.userChanges().listen((user) {
      if (user == null) {
        clearLatestCache();
        emit(FeedingRecordInitial());
      }
    });
  }

  AppFeedingRecord? getCachedLatestRecord(String pigId) =>
      _latestRecordCache[pigId];

  void removePigFromCache(String pigId) => _latestRecordCache.remove(pigId);

  void clearLatestCache() => _latestRecordCache.clear();

  Future<void> loadRecordsForPig(String pigId) async {
    try {
      emit(FeedingRecordLoading());
      final records = await feedingRepo.getFeedingRecordsForPig(pigId);
      if (isClosed) return;
      emit(FeedingRecordLoaded(records));
    } catch (e) {
      if (isClosed) return;
      emit(FeedingRecordError('Failed to load records: $e'));
    }
  }

  Future<void> loadLatestRecord(
      String pigId, {
        bool forceRefresh = false,
      }) async {
    if (!forceRefresh && _latestRecordCache.containsKey(pigId)) {
      emit(LatestFeedingRecordLoaded(pigId, _latestRecordCache[pigId]));
      return;
    }

    emit(LatestFeedingRecordLoading(pigId));
    try {
      final record = await feedingRepo.getLatestFeedingRecord(pigId);
      if (isClosed) return;
      _latestRecordCache[pigId] = record;
      emit(LatestFeedingRecordLoaded(pigId, record));
    } catch (e) {
      if (isClosed) return;
      emit(LatestFeedingRecordError(pigId, 'Failed to load latest record: $e'));
    }
  }

  Future<bool> addRecord(AppFeedingRecord record) async {
    try {
      await feedingRepo.addFeedingRecord(record);
      _latestRecordCache[record.pigId] = record;
      if (isClosed) return false;
      emit(LatestFeedingRecordLoaded(record.pigId, record));
      onRecordSaved?.call();
      return true;
    } catch (e) {
      if (isClosed) return false;
      emit(FeedingRecordError('Failed to add feeding record: $e'));
      return false;
    }
  }

  Future<bool> addBatchRecords(List<AppFeedingRecord> records) async {
    try {
      await feedingRepo.addBatchFeedingRecords(records);

      final updates = <String, AppFeedingRecord?>{};
      for (final record in records) {
        _latestRecordCache[record.pigId] = record;
        updates[record.pigId] = record;
      }

      if (isClosed) return false;
      emit(LatestFeedingRecordsBulkUpdated(updates));
      onRecordSaved?.call();
      return true;
    } catch (e) {
      if (isClosed) return false;
      emit(FeedingRecordError('Failed to add batch records: $e'));
      return false;
    }
  }

  @override
  Future<void> close() {
    _authSubscription?.cancel(); // 🔹 NEW
    return super.close();
  }
}