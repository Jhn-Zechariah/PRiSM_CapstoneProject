import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:prism_app/features/dashboard/presentation/pages/Dashboard_Screen.dart';
import 'package:prism_app/features/monitoring/data/today_readings_store.dart';

// Today's highest pig body temperature and humidity, kept in one shared
// document (sensor_memory/today_max) together with how far through today's
// sensor_readings_seconds it has been counted. Every phone continues from
// that point, so each reading is downloaded for this once in total instead
// of once per phone per app launch. The value then goes into SensorMemory,
// which the Dashboard and the Temperature/Humidity screens all display.
class TodayMaxService {
  static final DocumentReference<Map<String, dynamic>> _doc = FirebaseFirestore
      .instance
      .collection('sensor_memory')
      .doc('today_max');

  static const Duration _minSyncInterval = Duration(minutes: 1);
  static const Duration _autoSyncInterval = Duration(minutes: 5);

  static Timer? _timer;
  static bool _running = false;
  static DateTime _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  static String _appliedDayKey = '';

  // Syncs now and then every few minutes while the app is running. Safe to
  // call on every Dashboard mount.
  static void start() {
    unawaited(sync());
    _timer ??= Timer.periodic(_autoSyncInterval, (_) => sync());
  }

  static Future<void> sync() async {
    if (_running) return;
    if (DateTime.now().difference(_lastSyncAt) < _minSyncInterval) return;
    _running = true;
    _lastSyncAt = DateTime.now();

    try {
      final todayKey = SensorMemory.todayKey();
      final now = DateTime.now();
      final beforeMidnight = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(milliseconds: 1));

      final snap = await _doc.get(const GetOptions(source: Source.server));
      final d = snap.data();
      final sameDay = d?['date'] == todayKey;
      final docCursor = sameDay
          ? (d!['scannedUpTo'] as Timestamp?)?.toDate()
          : null;
      final double storedTemp = sameDay
          ? (d!['tempMax'] as num?)?.toDouble() ?? 0
          : 0;
      final double storedHum = sameDay
          ? (d!['humMax'] as num?)?.toDouble() ?? 0
          : 0;
      double tempMax = storedTemp;
      double humMax = storedHum;

      // Only readings that no phone has counted yet.
      final from = docCursor ?? beforeMidnight;
      final readings = await TodayReadingsStore.readingsAfter(from);

      if (readings.isNotEmpty) {
        for (final r in readings) {
          final t = (r.data['pigBodyTemp'] as num?)?.toDouble();
          if (r.data['pigBodyTempValid'] != false &&
              t != null &&
              t >= 0 &&
              t <= 80 &&
              t > tempMax) {
            tempMax = t;
          }

          final h = (r.data['ambientHumidity'] as num?)?.toDouble();
          if (r.data['ambientHumidityValid'] != false &&
              h != null &&
              h > 0 &&
              h <= 100 &&
              h > humMax) {
            humMax = h;
          }
        }
        final cursor = readings.last.ts;

        // Writes count toward Firestore's daily write limit (the ESP32
        // already uses most of it), so only write when the max went up,
        // or once an hour to save how far the readings have been counted.
        final needsWrite =
            !sameDay ||
            tempMax > storedTemp ||
            humMax > storedHum ||
            docCursor == null ||
            cursor.difference(docCursor).inMinutes >= 60;

        if (needsWrite) {
          (tempMax, humMax) = await _mergeIntoDoc(
            todayKey,
            docCursor,
            cursor,
            tempMax,
            humMax,
          );
        }
      }

      _apply(todayKey, tempMax, humMax);
    } catch (e) {
      // Try again on the next call instead of waiting the full interval.
      _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
      debugPrint('[TodayMax] sync failed: $e');
    } finally {
      _running = false;
    }
  }

  // Another phone may have counted further in the meantime, so merge with
  // whatever is stored now instead of overwriting it. Returns the merged
  // maximums.
  static Future<(double, double)> _mergeIntoDoc(
    String todayKey,
    DateTime? docCursor,
    DateTime cursor,
    double tempMax,
    double humMax,
  ) {
    return FirebaseFirestore.instance.runTransaction((tx) async {
      final cur = (await tx.get(_doc)).data();
      final curSameDay = cur?['date'] == todayKey;
      // The day rolled over while this sync was running.
      if (!curSameDay && docCursor != null) return (tempMax, humMax);

      final curCursor = curSameDay
          ? (cur!['scannedUpTo'] as Timestamp?)?.toDate()
          : null;
      final curTemp = curSameDay
          ? (cur!['tempMax'] as num?)?.toDouble() ?? 0
          : 0.0;
      final curHum = curSameDay
          ? (cur!['humMax'] as num?)?.toDouble() ?? 0
          : 0.0;

      final mergedTemp = curTemp > tempMax ? curTemp : tempMax;
      final mergedHum = curHum > humMax ? curHum : humMax;

      tx.set(_doc, {
        'date': todayKey,
        'tempMax': mergedTemp,
        'humMax': mergedHum,
        'scannedUpTo': Timestamp.fromDate(
          curCursor != null && curCursor.isAfter(cursor) ? curCursor : cursor,
        ),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return (mergedTemp, mergedHum);
    });
  }

  static void _apply(String todayKey, double tempMax, double humMax) {
    SensorMemory.resetIfNewDay();
    // First result of the day replaces whatever was stored before (it may
    // be stale or come from another source). After that the max only goes
    // up, so live readings counted in between are kept.
    final firstToday = _appliedDayKey != todayKey;
    _appliedDayKey = todayKey;

    var changed = false;
    if (firstToday ? tempMax != SensorMemory.lastTempMaxToday
                   : tempMax > SensorMemory.lastTempMaxToday) {
      SensorMemory.lastTempMaxDate = todayKey;
      SensorMemory.setTempMaxToday(tempMax);
      changed = true;
    }
    if (firstToday ? humMax != SensorMemory.lastHumidityMaxToday
                   : humMax > SensorMemory.lastHumidityMaxToday) {
      SensorMemory.lastHumidityMaxDate = todayKey;
      SensorMemory.setHumidityMaxToday(humMax);
      changed = true;
    }
    if (changed) SensorMemory.save();
  }
}
