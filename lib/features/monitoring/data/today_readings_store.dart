import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:prism_app/features/dashboard/presentation/pages/Dashboard_Screen.dart';

// One sensor_readings_seconds document from today.
class TodayReading {
  final DateTime ts;
  final Map<String, dynamic> data;

  const TodayReading(this.ts, this.data);
}

// Today's 10-second readings, shared by the Dashboard and the
// Temperature/Humidity screens. Each reading has both pigBodyTemp and
// ambientHumidity, so it only needs to be downloaded once per app session
// instead of once per screen.
class TodayReadingsStore {
  static String _dayKey = '';
  // Everything after this time (exclusive) is in _readings.
  static DateTime? _coveredFrom;
  static DateTime? _lastTs;
  static final List<TodayReading> _readings = [];
  static DateTime _lastFetchAt = DateTime.fromMillisecondsSinceEpoch(0);
  static Future<void> _lock = Future.value();

  // Calls closer together than this reuse the readings already downloaded,
  // e.g. when switching from the Temperature to the Humidity screen.
  static const Duration _minFetchInterval = Duration(seconds: 5);

  // Returns today's readings newer than [after], oldest first.
  static Future<List<TodayReading>> readingsAfter(DateTime after) {
    final result = _lock.then((_) => _readingsAfter(after));
    _lock = result.then((_) {}, onError: (_) {});
    return result;
  }

  static Future<List<TodayReading>> _readingsAfter(DateTime after) async {
    final todayKey = SensorMemory.todayKey();
    if (_dayKey != todayKey) {
      _dayKey = todayKey;
      _readings.clear();
      _coveredFrom = null;
      _lastTs = null;
      _lastFetchAt = DateTime.fromMillisecondsSinceEpoch(0);
    }

    if (_coveredFrom == null || after.isBefore(_coveredFrom!)) {
      // Asked for older readings than we have: download from [after].
      final fetched = await _fetch(after);
      _readings
        ..clear()
        ..addAll(fetched);
      _coveredFrom = after;
      _lastTs = fetched.isNotEmpty ? fetched.last.ts : after;
      _lastFetchAt = DateTime.now();
    } else if (DateTime.now().difference(_lastFetchAt) >= _minFetchInterval) {
      final fetched = await _fetch(_lastTs ?? _coveredFrom!);
      _readings.addAll(fetched);
      if (fetched.isNotEmpty) _lastTs = fetched.last.ts;
      _lastFetchAt = DateTime.now();
    }

    return _readings.where((r) => r.ts.isAfter(after)).toList();
  }

  // On the same WiFi as the ESP32 the readings come from its SD card
  // (GET /history), which costs no Firestore reads. Anywhere else, or if
  // the ESP32 does not answer properly, they come from Firestore.
  static Future<List<TodayReading>> _fetch(DateTime after) async {
    if (LiveSensorService.isOnLan) {
      final fromEsp32 = await _fetchFromEsp32(after);
      if (fromEsp32 != null) return fromEsp32;
    }
    return _fetchFromFirestore(after);
  }

  // Returns null when the ESP32 cannot give a complete answer.
  static Future<List<TodayReading>?> _fetchFromEsp32(DateTime after) async {
    final out = <TodayReading>[];
    // Slots are whole epoch seconds; the ESP32 sends rows with slot > since.
    var since = after.millisecondsSinceEpoch ~/ 1000;

    try {
      // Each answer holds at most 2000 rows; "more" means ask again.
      for (var page = 0; page < 20; page++) {
        final response = await http
            .get(Uri.parse('http://$esp32Ip/history?since=$since&limit=2000'))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return null;

        final lines = response.body.trim().split('\n');
        final last = lines.isEmpty ? '' : lines.last.trim();
        // No "end"/"more" line: the answer was cut off.
        if (last != 'end' && last != 'more') return null;

        for (final line in lines.take(lines.length - 1)) {
          // slot,pig_skin_c,ambient_c,humidity_pct   (blank = not valid)
          final f = line.trim().split(',');
          if (f.length < 4) continue;
          final slot = int.tryParse(f[0]);
          if (slot == null) continue;

          final ts = DateTime.fromMillisecondsSinceEpoch(slot * 1000);
          final pig = double.tryParse(f[1]);
          final ambient = double.tryParse(f[2]);
          final humidity = double.tryParse(f[3]);
          out.add(TodayReading(ts, {
            'timestamp': Timestamp.fromDate(ts),
            'pigBodyTemp': ?pig,
            'ambientTemp': ?ambient,
            'ambientHumidity': ?humidity,
          }));
          since = slot;
        }

        if (last == 'end') return out;
      }
      return null;
    } catch (e) {
      debugPrint('[TodayReadings] ESP32 /history failed, using Firestore: $e');
      return null;
    }
  }

  static Future<List<TodayReading>> _fetchFromFirestore(DateTime after) async {
    final out = <TodayReading>[];
    QueryDocumentSnapshot<Map<String, dynamic>>? lastPageDocument;

    while (true) {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('sensor_readings_seconds')
          .where('timestamp', isGreaterThan: Timestamp.fromDate(after))
          .orderBy('timestamp', descending: false)
          .limit(1000);

      if (lastPageDocument != null) {
        query = query.startAfterDocument(lastPageDocument);
      }

      final snap = await query.get();

      for (final doc in snap.docs) {
        final d = doc.data();
        final ts = (d['timestamp'] as Timestamp?)?.toDate();
        if (ts == null) continue;
        out.add(TodayReading(ts, d));
      }

      if (snap.docs.isNotEmpty) lastPageDocument = snap.docs.last;
      if (snap.docs.length < 1000) break;
    }

    return out;
  }
}
