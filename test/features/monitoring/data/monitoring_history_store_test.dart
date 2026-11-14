import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_app/features/monitoring/data/monitoring_history_store.dart';

void main() {
  final start = DateTime(2026, 11, 1);
  DateTime hour(int offset) => start.add(Duration(hours: offset));
  HourlySummaries summaries(DateTime from, DateTime until) => {
    for (var h = from; h.isBefore(until); h = h.add(const Duration(hours: 1)))
      h.millisecondsSinceEpoch: {'sum': 100.0, 'count': 4},
  };

  test('overlapping pages and expanding ranges fetch only uncovered hours', () async {
    final calls = <List<DateTime>>[];
    final cache = HourlySummaryCache((from, until) async {
      calls.add([from, until]);
      return summaries(from, until);
    }, clock: () => DateTime(2026, 11, 14));

    expect(await cache.read(start, hour(24)), hasLength(24));
    expect(await cache.read(hour(5), hour(12)), hasLength(7));
    expect(await cache.read(start, hour(25)), hasLength(25));
    expect(calls, [[start, hour(24)], [hour(24), hour(25)]]);
  });

  test('missing hours are cached briefly then checked for late summaries', () async {
    var now = DateTime(2026, 11, 14);
    var calls = 0;
    final cache = HourlySummaryCache((from, until) async {
      calls++;
      return calls == 1 ? {} : summaries(from, until);
    }, clock: () => now);

    expect(await cache.read(start, hour(24)), isEmpty);
    expect(await cache.read(start, hour(24)), isEmpty);
    expect(calls, 1);
    now = now.add(const Duration(minutes: 5));
    expect(await cache.read(start, hour(24)), hasLength(24));
    expect(calls, 2);
  });

  test('recent hours refresh without redownloading old history', () async {
    var now = hour(24);
    final calls = <List<DateTime>>[];
    final cache = HourlySummaryCache((from, until) async {
      calls.add([from, until]);
      return summaries(from, until);
    }, clock: () => now);

    await cache.read(start, hour(24));
    now = now.add(const Duration(minutes: 1));
    await cache.read(start, hour(24));
    expect(calls, [[start, hour(24)], [hour(23), hour(24)]]);
  });

  test('simultaneous requests share one download', () async {
    final gate = Completer<HourlySummaries>();
    var calls = 0;
    final cache = HourlySummaryCache((from, until) {
      calls++;
      return gate.future;
    }, clock: () => DateTime(2026, 11, 14));

    final first = cache.read(start, hour(24));
    final second = cache.read(start, hour(24));
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    gate.complete(summaries(start, hour(24)));
    expect(await first, hasLength(24));
    expect(await second, hasLength(24));
    expect(calls, 1);
  });

  test('a failed download can be retried without poisoning coverage', () async {
    var calls = 0;
    final cache = HourlySummaryCache((from, until) async {
      if (++calls == 1) throw StateError('offline');
      return summaries(from, until);
    }, clock: () => DateTime(2026, 11, 14));

    await expectLater(cache.read(start, hour(24)), throwsStateError);
    expect(await cache.read(start, hour(24)), hasLength(24));
    expect(calls, 2);
  });

  test('custom range rejects future dates and anything over exactly 31 days', () {
    final end = start.add(const Duration(days: 31));
    final now = end.add(const Duration(days: 1));
    expect(MonitoringHistoryStore.isValidCustomRange(start, end, now), isTrue);
    expect(MonitoringHistoryStore.isValidCustomRange(
      start, end.add(const Duration(minutes: 1)), now,
    ), isFalse);
    expect(MonitoringHistoryStore.isValidCustomRange(start, start, now), isFalse);
    expect(MonitoringHistoryStore.isValidCustomRange(end, start, now), isFalse);
    expect(MonitoringHistoryStore.isValidCustomRange(start, end, start), isFalse);
  });
}
