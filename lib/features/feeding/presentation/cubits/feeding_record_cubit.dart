import 'dart:ui';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/model/app_feeding_record.dart';
import '../../domain/repo/feeding_record_repo.dart';
import 'feeding_record_states.dart';

class FeedingRecordCubit extends Cubit<FeedingRecordState> {
  final FeedingRecordRepo feedingRepo;

  // Optional callback invoked after any successful write so callers
  // (e.g. the screen that also holds a FeedingHistoryCubit) can bust
  // the history cache without the two cubits being directly coupled.
  final VoidCallback? onRecordSaved;

  FeedingRecordCubit({
    required this.feedingRepo,
    this.onRecordSaved,
  }) : super(FeedingRecordInitial());

  final Map<String, AppFeedingRecord?> _latestRecordCache = {};

  // ── Cache helpers ──────────────────────────────────────────────────────────

  AppFeedingRecord? getCachedLatestRecord(String pigId) =>
      _latestRecordCache[pigId];

  /// Evict a single pig's latest-record entry (e.g. after it is sold/removed).
  void removePigFromCache(String pigId) => _latestRecordCache.remove(pigId);

  /// Evict ALL cached latest records (e.g. on logout or full refresh).
  void clearLatestCache() => _latestRecordCache.clear();

  // ── Full record list for a pig ─────────────────────────────────────────────

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

  // ── Latest single record ───────────────────────────────────────────────────

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

  // ── Single add ────────────────────────────────────────────────────────────
  //
  // FIX (Critical): Removed the loadRecordsForPig() call that previously ran
  // after every save. That triggered a full Firestore read of the pig's entire
  // feeding history on each add — O(n) reads that grew with the pig's lifetime.
  //
  // The latest-record cache is updated in-memory immediately, so the UI card
  // refreshes without any extra read. Call loadRecordsForPig() explicitly only
  // when you actually need the full list (e.g. navigating to the detail page).

  Future<bool> addRecord(AppFeedingRecord record) async {
    try {
      await feedingRepo.addFeedingRecord(record);

      // Update the in-memory cache and emit — no extra Firestore read needed.
      _latestRecordCache[record.pigId] = record;
      if (isClosed) return false;
      emit(LatestFeedingRecordLoaded(record.pigId, record));

      // Notify sibling cubits (e.g. FeedingHistoryCubit) to bust their cache.
      onRecordSaved?.call();

      return true;
    } catch (e) {
      if (isClosed) return false;
      emit(FeedingRecordError('Failed to add feeding record: $e'));
      return false;
    }
  }

  // ── Batch add ─────────────────────────────────────────────────────────────

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

      // Notify sibling cubits to bust their cache.
      onRecordSaved?.call();

      return true;
    } catch (e) {
      if (isClosed) return false;
      emit(FeedingRecordError('Failed to add batch records: $e'));
      return false;
    }
  }
}