import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prism_app/core/services/account_cache_policy.dart';

typedef HourlySummaries = Map<int, Map<String, dynamic>>;
typedef HourlyLoader = Future<HourlySummaries> Function(
  DateTime start,
  DateTime end,
);

/// Session-only cache shared by the monitoring pages. Coverage includes missing
/// hours so revisiting a range does not repeatedly issue empty queries.
class HourlySummaryCache {
  HourlySummaryCache(this.load, {DateTime Function()? clock})
      : clock = clock ?? DateTime.now;

  final HourlyLoader load;
  final DateTime Function() clock;
  final HourlySummaries _hours = {};
  final Map<int, DateTime> _expires = {};
  Future<void> _pending = Future.value();

  Future<HourlySummaries> read(DateTime start, DateTime end) {
    final result = _pending.then((_) => _read(start, end));
    _pending = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<HourlySummaries> _read(DateTime start, DateTime end) async {
    if (!end.isAfter(start)) return {};
    final now = clock();
    final first = DateTime(start.year, start.month, start.day, start.hour);
    final keys = <int>[];
    for (var hour = first; hour.isBefore(end);
        hour = hour.add(const Duration(hours: 1))) {
      keys.add(hour.millisecondsSinceEpoch);
    }

    // Bound memory even when users browse many different custom ranges.
    _expires.removeWhere((key, expiry) {
      final expired = !expiry.isAfter(now);
      if (expired) _hours.remove(key);
      return expired;
    });
    if (_expires.length + keys.length > 1600) {
      final keep = keys.toSet();
      _expires.removeWhere((key, _) => !keep.contains(key));
      _hours.removeWhere((key, _) => !keep.contains(key));
    }

    var i = 0;
    while (i < keys.length) {
      if (_expires.containsKey(keys[i])) {
        i++;
        continue;
      }
      final begin = i;
      while (i < keys.length && !_expires.containsKey(keys[i])) {
        i++;
      }
      final from = DateTime.fromMillisecondsSinceEpoch(keys[begin]);
      final until = DateTime.fromMillisecondsSinceEpoch(keys[i - 1])
          .add(const Duration(hours: 1));
      // One query per contiguous uncovered interval, never one per hour.
      final fetched = await load(from, until);
      for (var j = begin; j < i; j++) {
        final key = keys[j];
        final value = fetched[key];
        if (value == null) {
          _hours.remove(key);
        } else {
          _hours[key] = Map<String, dynamic>.unmodifiable(value);
        }
        final hour = DateTime.fromMillisecondsSinceEpoch(key);
        final recent = now.difference(hour) < const Duration(hours: 2);
        _expires[key] = now.add(
          recent ? const Duration(minutes: 1)
              : value == null ? const Duration(minutes: 5)
              : const Duration(hours: 6),
        );
      }
    }
    return {
      for (final key in keys)
        if (_hours.containsKey(key)) key: _hours[key]!,
    };
  }
}

class MonitoringHistoryStore {
  static String? _owner;
  static HourlySummaryCache? _cache;

  static bool isValidCustomRange(
    DateTime start,
    DateTime end,
    DateTime now,
  ) => start.isBefore(end) &&
      !end.isAfter(now) &&
      end.difference(start) <= const Duration(days: 31);

  static Future<HourlySummaries> hourly(DateTime start, DateTime end) async {
    final uid = AccountCachePolicy.currentUid;
    if (_owner != uid) {
      _owner = uid;
      _cache = null;
    }
    // Preserve the explicit server-only policy for other accounts.
    if (!AccountCachePolicy.canUseCache) {
      _cache = null;
      return _loadHourly(start, end);
    }
    final cache = _cache ??= HourlySummaryCache(_loadHourly);
    final result = await cache.read(start, end);
    AccountCachePolicy.checkSession(uid);
    return result;
  }

  static Future<HourlySummaries> _loadHourly(
    DateTime start,
    DateTime end,
  ) async {
    final snap = await FirebaseFirestore.instance
        .collection('sensor_readings_hourly')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('timestamp', isLessThan: Timestamp.fromDate(end))
        .orderBy('timestamp')
        .getForAccount()
        .timeout(const Duration(seconds: 30));
    return {
      for (final doc in snap.docs)
        if (doc.data()['timestamp'] is Timestamp)
          (doc.data()['timestamp'] as Timestamp).millisecondsSinceEpoch:
              doc.data(),
    };
  }
}
