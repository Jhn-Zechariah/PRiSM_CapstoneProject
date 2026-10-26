import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

// ─────────────────────────────────────────────
// SensorHistoryStore — on-phone copy of sensor_readings_seconds.
//
// Every 10-second reading is downloaded once per phone and kept in SQLite,
// so charts and stats re-read it locally instead of paying a Firestore read
// each time a screen opens or a range is re-loaded.
//
// Where readings come from (sync):
//   1. The ESP32's SD card over the LAN (GET /history) — free, works on
//      the home WiFi.
//   2. Otherwise Firestore, only the documents newer than the last one
//      already stored.
//
// Coverage: the local copy is complete from `coverageStart` up to the
// newest synced reading. The first sync starts at today's 12:00 AM. If the
// phone was away for days and the ESP32 can't be reached over LAN, the
// gap is NOT backfilled from Firestore (that would cost 8,640 reads per
// missed day); coverage restarts at today's 12:00 AM instead.
//
// readings() serves a range from SQLite when it lies inside the coverage,
// and falls back to the same Firestore query the screens used before when
// it doesn't (older days, or SQLite unavailable on this platform).
//
// Firestore keeps raw readings for only 7 days (TTL on `expireAt`, set by
// the ESP32), so the local copy keeps them longer — see _localRetention.
// ─────────────────────────────────────────────
class SensorHistoryStore {
  /// Returns the ESP32's current LAN address. Set by LiveSensorService,
  /// which follows the address the ESP32 reports.
  static String Function()? lanHost;

  static const String _table = 'readings';
  static const String _prefsCoverageStart = 'sensor_history_coverage_start';
  static const String _prefsCursor = 'sensor_history_cursor';

  /// Local readings older than this are deleted.
  static const Duration _localRetention = Duration(days: 30);

  /// Calls closer together than this reuse the previous sync.
  static const Duration _minSyncGap = Duration(seconds: 5);

  /// After a failed LAN attempt, go straight to Firestore for this long.
  static const Duration _lanRetryGap = Duration(seconds: 60);

  static const int _lanPageSize = 2000;
  static const int _firestorePageSize = 1000;

  static Database? _db;
  static bool _openFailed = false;
  static Future<Database?>? _opening;

  static int? _coverageStartSlot; // epoch seconds
  static int? _cursorSlot; // newest slot stored (epoch seconds)

  static Future<void>? _syncing;
  static DateTime _lastSyncAt = DateTime.fromMillisecondsSinceEpoch(0);
  static DateTime _lastLanFailAt = DateTime.fromMillisecondsSinceEpoch(0);
  static bool _prunedThisSession = false;

  // ── Public API ───────────────────────────────

  /// Brings the local copy up to date. Cheap to call often: concurrent
  /// callers share one run, and calls within [_minSyncGap] are skipped.
  static Future<void> sync() {
    return _syncing ??= _doSync().whenComplete(() => _syncing = null);
  }

  /// Readings in the given range, oldest first, as maps shaped like the
  /// Firestore documents: {'timestamp': Timestamp, 'pigBodyTemp': num?,
  /// 'ambientTemp': num?, 'ambientHumidity': num?}. A missing key means
  /// that sensor value was not valid.
  ///
  /// Served from the phone when the range is covered locally; otherwise
  /// read from Firestore with the same query the screens used before.
  static Future<List<Map<String, dynamic>>> readings({
    required DateTime from,
    bool fromInclusive = false,
    DateTime? to,
    bool toInclusive = false,
  }) async {
    await sync();

    final db = _db;
    final coverageStart = _coverageStartSlot;
    if (db != null &&
        coverageStart != null &&
        _firstSlot(from, fromInclusive) >= coverageStart) {
      try {
        return await _readLocal(db, from, fromInclusive, to, toInclusive);
      } catch (e) {
        debugPrint('[SensorHistory] local read failed, using Firestore: $e');
      }
    }
    return _readFirestore(from, fromInclusive, to, toInclusive);
  }

  // ── Database ─────────────────────────────────

  static Future<Database?> _open() async {
    if (_db != null || _openFailed) return _db;
    return _opening ??= () async {
      try {
        final path = '${await getDatabasesPath()}/sensor_history.db';
        _db = await openDatabase(
          path,
          version: 1,
          onCreate: (db, _) => db.execute(
            'CREATE TABLE $_table ('
            'slot INTEGER PRIMARY KEY, '
            'pigBodyTemp REAL, '
            'ambientTemp REAL, '
            'ambientHumidity REAL)',
          ),
        );
        final prefs = await SharedPreferences.getInstance();
        _coverageStartSlot = prefs.getInt(_prefsCoverageStart);
        _cursorSlot = prefs.getInt(_prefsCursor);
      } catch (e) {
        // e.g. a platform without sqflite: every read goes to Firestore.
        debugPrint('[SensorHistory] SQLite unavailable: $e');
        _openFailed = true;
      }
      return _db;
    }();
  }

  static Future<void> _saveMeta() async {
    final prefs = await SharedPreferences.getInstance();
    if (_coverageStartSlot != null) {
      await prefs.setInt(_prefsCoverageStart, _coverageStartSlot!);
    }
    if (_cursorSlot != null) await prefs.setInt(_prefsCursor, _cursorSlot!);
  }

  static Future<void> _insertRows(
    Database db,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return;
    final batch = db.batch();
    for (final r in rows) {
      batch.insert(_table, r, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  // ── Sync ─────────────────────────────────────

  static Future<void> _doSync() async {
    if (DateTime.now().difference(_lastSyncAt) < _minSyncGap) return;

    final db = await _open();
    if (db == null) return;

    final now = DateTime.now();
    final midnightSlot =
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch ~/ 1000;

    if (_coverageStartSlot == null || _cursorSlot == null) {
      _coverageStartSlot = midnightSlot;
      _cursorSlot = midnightSlot - 1;
    }

    try {
      final lanComplete = await _syncFromLan(db);

      if (!lanComplete) {
        if (_cursorSlot! < midnightSlot - 1) {
          // Gap from an earlier day that only the ESP32 SD card could fill
          // for free. Start coverage at today's 12:00 AM instead.
          _coverageStartSlot = midnightSlot;
          _cursorSlot = midnightSlot - 1;
        }
        await _syncFromFirestore(db);
      }

      _lastSyncAt = DateTime.now();

      if (!_prunedThisSession) {
        _prunedThisSession = true;
        final cutoff =
            now.subtract(_localRetention).millisecondsSinceEpoch ~/ 1000;
        await db.delete(_table, where: 'slot < ?', whereArgs: [cutoff]);
        if (_coverageStartSlot! < cutoff) _coverageStartSlot = cutoff;
      }
    } catch (e) {
      debugPrint('[SensorHistory] sync failed: $e');
    } finally {
      await _saveMeta();
    }
  }

  /// Downloads new rows from the ESP32's SD card. Returns true when the
  /// ESP32 confirmed there is nothing newer ("end").
  static Future<bool> _syncFromLan(Database db) async {
    final host = lanHost?.call();
    if (host == null || host.isEmpty) return false;
    if (DateTime.now().difference(_lastLanFailAt) < _lanRetryGap) {
      return false;
    }

    try {
      while (true) {
        final uri = Uri.parse(
          'http://$host/history?since=$_cursorSlot&limit=$_lanPageSize',
        );
        final response = await http.get(uri).timeout(
              const Duration(seconds: 5),
            );
        if (response.statusCode != 200) {
          throw Exception('HTTP ${response.statusCode}');
        }

        final lines = response.body.trimRight().split('\n');
        final last = lines.isEmpty ? '' : lines.last.trim();
        if (last != 'end' && last != 'more') {
          throw Exception('incomplete /history response');
        }

        final rows = <Map<String, Object?>>[];
        int newest = _cursorSlot!;
        for (final line in lines.take(lines.length - 1)) {
          final f = line.trim().split(',');
          if (f.length < 4) continue;
          final slot = int.tryParse(f[0]);
          if (slot == null || slot <= _cursorSlot!) continue;
          rows.add({
            'slot': slot,
            'pigBodyTemp': double.tryParse(f[1]),
            'ambientTemp': double.tryParse(f[2]),
            'ambientHumidity': double.tryParse(f[3]),
          });
          if (slot > newest) newest = slot;
        }

        await _insertRows(db, rows);
        _cursorSlot = newest;

        if (last == 'end') return true;
        if (rows.isEmpty) return true; // "more" without progress: stop
      }
    } catch (e) {
      debugPrint('[SensorHistory] LAN /history failed: $e');
      _lastLanFailAt = DateTime.now();
      return false;
    }
  }

  /// Downloads only the Firestore readings newer than the local cursor.
  static Future<void> _syncFromFirestore(Database db) async {
    while (true) {
      final after = Timestamp.fromMillisecondsSinceEpoch(_cursorSlot! * 1000);
      final snap = await FirebaseFirestore.instance
          .collection('sensor_readings_seconds')
          .where('timestamp', isGreaterThan: after)
          .orderBy('timestamp')
          .limit(_firestorePageSize)
          .get()
          .timeout(const Duration(seconds: 30));

      final rows = <Map<String, Object?>>[];
      int newest = _cursorSlot!;
      for (final doc in snap.docs) {
        final d = doc.data();
        final ts = d['timestamp'] as Timestamp?;
        if (ts == null) continue;
        final slot = ts.seconds;
        rows.add({
          'slot': slot,
          'pigBodyTemp': d['pigBodyTempValid'] == false
              ? null
              : (d['pigBodyTemp'] as num?)?.toDouble(),
          'ambientTemp': d['ambientTempValid'] == false
              ? null
              : (d['ambientTemp'] as num?)?.toDouble(),
          'ambientHumidity': d['ambientHumidityValid'] == false
              ? null
              : (d['ambientHumidity'] as num?)?.toDouble(),
        });
        if (slot > newest) newest = slot;
      }

      await _insertRows(db, rows);
      _cursorSlot = newest;

      if (snap.docs.length < _firestorePageSize) return;
    }
  }

  // ── Reads ────────────────────────────────────

  /// Earliest whole-second slot a range starting at [from] can include.
  /// e.g. "after 11:59:59.999 PM" starts at the 12:00:00 AM slot.
  static int _firstSlot(DateTime from, bool inclusive) {
    final ms = from.millisecondsSinceEpoch;
    return inclusive ? (ms + 999) ~/ 1000 : ms ~/ 1000 + 1;
  }

  static Future<List<Map<String, dynamic>>> _readLocal(
    Database db,
    DateTime from,
    bool fromInclusive,
    DateTime? to,
    bool toInclusive,
  ) async {
    // Slots are whole seconds; convert the millisecond bounds exactly.
    final where = <String>['slot >= ?'];
    final args = <Object>[_firstSlot(from, fromInclusive)];
    if (to != null) {
      final toMs = to.millisecondsSinceEpoch;
      if (toInclusive) {
        where.add('slot <= ?');
        args.add(toMs ~/ 1000);
      } else {
        where.add('slot < ?');
        args.add((toMs + 999) ~/ 1000);
      }
    }

    final rows = await db.query(
      _table,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'slot ASC',
    );

    return [
      for (final r in rows)
        {
          'timestamp': Timestamp((r['slot'] as int), 0),
          if (r['pigBodyTemp'] != null) 'pigBodyTemp': r['pigBodyTemp'],
          if (r['ambientTemp'] != null) 'ambientTemp': r['ambientTemp'],
          if (r['ambientHumidity'] != null)
            'ambientHumidity': r['ambientHumidity'],
        },
    ];
  }

  static Future<List<Map<String, dynamic>>> _readFirestore(
    DateTime from,
    bool fromInclusive,
    DateTime? to,
    bool toInclusive,
  ) async {
    final out = <Map<String, dynamic>>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? lastDocument;

    while (true) {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('sensor_readings_seconds');
      final fromTs = Timestamp.fromDate(from);
      query = fromInclusive
          ? query.where('timestamp', isGreaterThanOrEqualTo: fromTs)
          : query.where('timestamp', isGreaterThan: fromTs);
      if (to != null) {
        final toTs = Timestamp.fromDate(to);
        query = toInclusive
            ? query.where('timestamp', isLessThanOrEqualTo: toTs)
            : query.where('timestamp', isLessThan: toTs);
      }
      query = query.orderBy('timestamp').limit(_firestorePageSize);
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final snap = await query.get().timeout(const Duration(seconds: 30));
      for (final doc in snap.docs) {
        final d = doc.data();
        out.add({
          'timestamp': d['timestamp'],
          if (d['pigBodyTempValid'] != false && d['pigBodyTemp'] != null)
            'pigBodyTemp': d['pigBodyTemp'],
          if (d['ambientTempValid'] != false && d['ambientTemp'] != null)
            'ambientTemp': d['ambientTemp'],
          if (d['ambientHumidityValid'] != false &&
              d['ambientHumidity'] != null)
            'ambientHumidity': d['ambientHumidity'],
        });
      }

      if (snap.docs.length < _firestorePageSize) return out;
      lastDocument = snap.docs.last;
    }
  }
}
