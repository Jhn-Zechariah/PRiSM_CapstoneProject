import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/model/app_feeding_history.dart';
import '../../domain/repo/feeding_record_repo.dart';
import 'feeding_history_states.dart';

/// Pagination state for one history view (all pigs, or a single pig).
class _HistoryCacheEntry {
  List<AppFeedingHistory> records;
  DocumentSnapshot? lastDoc;
  bool hasMore;
  DateTime fetchedAt;

  _HistoryCacheEntry({
    required this.records,
    required this.lastDoc,
    required this.hasMore,
    required this.fetchedAt,
  });
}

/// Provided app-wide (see main.dart) so the cache survives between visits to
/// the history page. FeedingRecordCubit's onRecordSaved calls
/// [invalidateCache] so new records show up immediately.
class FeedingHistoryCubit extends Cubit<FeedingHistoryState> {
  final FeedingRecordRepo _repo;

  // Keyed by '$userId|$pigId' ('All' when no pig is selected), so switching
  // between pigs and back doesn't refetch pages already loaded.
  final Map<String, _HistoryCacheEntry> _cache = {};

  String? _userId;
  String? _pigId;

  /// Prevents concurrent loadMoreHistory calls while a page request is
  /// already in flight (e.g. rapid scroll events).
  bool _isRequestingMore = false;

  /// Bumped on every new view so responses for a pig the user has already
  /// switched away from are dropped instead of overwriting the current view.
  int _requestToken = 0;

  static const _cacheDuration = Duration(seconds: 60);
  static const _pageSize = 50;

  FeedingHistoryCubit({required FeedingRecordRepo repo})
      : _repo = repo,
        super(const FeedingHistoryInitial());

  String get _currentKey => '$_userId|${_pigId ?? 'All'}';

  /// Busts the cache so the next load fetches fresh data from Firestore.
  void invalidateCache() {
    _cache.clear();
    _isRequestingMore = false;
  }

  // ── Load first page ────────────────────────────────────────────────────────

  /// Loads history for [userId], limited to [pigId] when given.
  Future<void> loadGlobalFeedingHistory(
      String userId, {
        String? pigId,
        bool forceRefresh = false,
      }) async {
    _userId = userId;
    _pigId = pigId;
    _isRequestingMore = false;
    final key = _currentKey;
    final token = ++_requestToken;

    final cached = _cache[key];
    if (!forceRefresh &&
        cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _cacheDuration) {
      emit(FeedingHistoryLoaded(cached.records, hasMore: cached.hasMore));
      return;
    }

    emit(const FeedingHistoryLoading());

    try {
      final result = await _repo.getGlobalFeedingHistory(
        userId,
        pigId: pigId,
        limit: _pageSize,
      );

      if (isClosed || token != _requestToken) return;

      // A partial page means Firestore has no more documents — stop paging.
      final entry = _HistoryCacheEntry(
        records: result.records,
        lastDoc: result.lastDoc,
        hasMore: result.records.length == _pageSize,
        fetchedAt: DateTime.now(),
      );
      _cache[key] = entry;

      emit(FeedingHistoryLoaded(entry.records, hasMore: entry.hasMore));
    } catch (e) {
      if (isClosed || token != _requestToken) return;
      emit(FeedingHistoryError('Failed to fetch history: $e'));
    }
  }

  // ── Load next page ─────────────────────────────────────────────────────────

  Future<void> loadMoreHistory() async {
    final userId = _userId;
    if (userId == null || _isRequestingMore) return;

    final entry = _cache[_currentKey];
    if (entry == null || !entry.hasMore) return;

    final token = _requestToken;
    _isRequestingMore = true;
    emit(FeedingHistoryLoadingMore(entry.records));

    try {
      final result = await _repo.getGlobalFeedingHistory(
        userId,
        pigId: _pigId,
        startAfter: entry.lastDoc,
        limit: _pageSize,
      );

      if (isClosed || token != _requestToken) return;

      entry.hasMore = result.records.length == _pageSize;

      // Only advance the cursor when the response contained a document;
      // keeps the previous cursor valid on an empty/partial last page.
      if (result.lastDoc != null) entry.lastDoc = result.lastDoc;

      entry.records = [...entry.records, ...result.records];
      entry.fetchedAt = DateTime.now();

      emit(FeedingHistoryLoaded(entry.records, hasMore: entry.hasMore));
    } catch (e) {
      if (isClosed || token != _requestToken) return;
      // Keep the list on screen and let the user retry the next page.
      emit(FeedingHistoryLoaded(
        entry.records,
        hasMore: entry.hasMore,
        loadMoreFailed: true,
      ));
    } finally {
      if (token == _requestToken) _isRequestingMore = false;
    }
  }
}
