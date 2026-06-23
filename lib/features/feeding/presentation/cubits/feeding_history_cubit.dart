import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/model/app_feeding_history.dart';
import '../../domain/repo/feeding_record_repo.dart';
import 'feeding_history_states.dart';

class FeedingHistoryCubit extends Cubit<FeedingHistoryState> {
  final FeedingRecordRepo _repo;

  List<AppFeedingHistory>? _cachedRecords;
  String? _cachedUserId;
  DateTime? _cachedAt;

  DocumentSnapshot? _lastDocument;
  bool _hasMore = true;

  /// Prevents concurrent loadMoreHistory calls while a page request is
  /// already in flight (e.g. rapid scroll events).
  bool _isRequestingMore = false;

  static const _cacheDuration = Duration(seconds: 60);
  static const _pageSize = 50;

  FeedingHistoryCubit({required FeedingRecordRepo repo})
      : _repo = repo,
        super(const FeedingHistoryInitial());

  // ── Cache helpers ──────────────────────────────────────────────────────────

  bool _isCacheValid(String userId) {
    if (_cachedRecords == null || _cachedAt == null) return false;
    if (_cachedUserId != userId) return false;
    return DateTime.now().difference(_cachedAt!) < _cacheDuration;
  }

  /// Busts the cache so the next load fetches fresh data from Firestore.
  ///
  /// Call this whenever a record is saved (e.g. via FeedingRecordCubit's
  /// onRecordSaved callback) so history reflects new writes immediately
  /// rather than waiting for the 60-second TTL to expire.
  void invalidateCache() {
    _cachedRecords = null;
    _cachedAt = null;
    _cachedUserId = null;
    _lastDocument = null;
    _hasMore = true;
    _isRequestingMore = false;
  }

  // ── Load first page ────────────────────────────────────────────────────────

  Future<void> loadGlobalFeedingHistory(
      String userId, {
        bool forceRefresh = false,
      }) async {
    if (!forceRefresh && _isCacheValid(userId)) {
      emit(FeedingHistoryLoaded(_cachedRecords!, hasMore: _hasMore));
      return;
    }

    // Reset pagination state before the fresh fetch.
    _lastDocument = null;
    _hasMore = true;
    _isRequestingMore = false;

    emit(const FeedingHistoryLoading());

    try {
      final result = await _repo.getGlobalFeedingHistory(
        userId,
        limit: _pageSize,
      );

      if (isClosed) return;

      _cachedRecords = result.records;
      _cachedUserId = userId;
      _cachedAt = DateTime.now();
      _lastDocument = result.lastDoc;

      // A partial page means Firestore has no more documents — stop paging.
      _hasMore = result.records.length == _pageSize;

      emit(FeedingHistoryLoaded(result.records, hasMore: _hasMore));
    } catch (e) {
      if (isClosed) return;
      emit(FeedingHistoryError('Failed to fetch history: $e'));
    }
  }

  // ── Load next page ─────────────────────────────────────────────────────────

  Future<void> loadMoreHistory(String userId) async {
    if (!_hasMore || _isRequestingMore) return;
    if (state is FeedingHistoryLoadingMore) return;

    final current = _cachedRecords;
    if (current == null) {
      await loadGlobalFeedingHistory(userId);
      return;
    }

    _isRequestingMore = true;
    emit(FeedingHistoryLoadingMore(current));

    try {
      final result = await _repo.getGlobalFeedingHistory(
        userId,
        startAfter: _lastDocument,
        limit: _pageSize,
      );

      if (isClosed) return;

      _hasMore = result.records.length == _pageSize;

      // Only advance the cursor when the response contained a document;
      // keeps the previous cursor valid on an empty/partial last page.
      if (result.lastDoc != null) _lastDocument = result.lastDoc;

      final merged = [...current, ...result.records];
      _cachedRecords = merged;
      _cachedAt = DateTime.now();

      emit(FeedingHistoryLoaded(merged, hasMore: _hasMore));
    } catch (e) {
      if (isClosed) return;
      // Restore the previous loaded state so the list doesn't blank out on
      // a transient network failure, then surface the error.
      emit(FeedingHistoryLoaded(current, hasMore: _hasMore));
      emit(FeedingHistoryError('Failed to load more: $e'));
    } finally {
      _isRequestingMore = false;
    }
  }
}