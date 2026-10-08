import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import '../../../../core/services/ml_service.dart';
import '../../../../core/widgets/build_tab_bar.dart';
import 'package:prism_app/features/dashboard/presentation/pages/Dashboard_Screen.dart';

const List<String> kTimeRanges = ['This Month', 'This Week', 'Today', 'Custom'];

String _formatDateTime(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final min = dt.minute.toString().padLeft(2, '0');
  final p = dt.hour < 12 ? 'AM' : 'PM';
  return '$d/$m/${dt.year}  $h:$min $p';
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

String _formatTime(TimeOfDay t) {
  final h = t.hour == 0
      ? 12
      : t.hour > 12
      ? t.hour - 12
      : t.hour;
  final min = t.minute.toString().padLeft(2, '0');
  final p = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '${h.toString().padLeft(2, '0')}:$min $p';
}

DateTimeRange? _resolveTimeRange(
  int index,
  DateTime? customStart,
  DateTime? customEnd,
) {
  final now = DateTime.now();
  switch (index) {
    case 0:
      return DateTimeRange(
        start: DateTime(now.year, now.month, 1),
        end: now, // never the end of the month
      );
    case 1:
      final ws = now.subtract(Duration(days: now.weekday - 1));
      return DateTimeRange(
        start: DateTime(ws.year, ws.month, ws.day), // Monday 12:00 AM
        end: now, // never Sunday
      );
    case 2:
      return DateTimeRange(
        start: DateTime(now.year, now.month, now.day),
        end: now,
      );
    case 3:
      if (customStart == null || customEnd == null) return null;
      return DateTimeRange(start: customStart, end: customEnd);
    default:
      return null;
  }
}

// Chart gap handling: a gap is a stretch with no readings (connection lost).
const double _kTodayGapHours = 15 / 3600.0; // > 15s without data = gap
const double _kTodayBlankHours = 20 / 3600.0; // gap is drawn this wide (60 px)
const int _kTodayTail = 360; // same as rawTailCount on the Today chart

class _Gap {
  final double start;
  final double end;
  const _Gap(this.start, this.end);
}

List<_Gap> _findGaps(
  List<Map<String, double>> data, {
  required double gap,
  required int tailStart,
}) {
  final gaps = <_Gap>[];
  // Older data is stored thinned (one point per 30s), so it needs a looser limit.
  final oldGap = gap > 45 / 3600.0 ? gap : 45 / 3600.0;
  for (int i = 1; i < data.length; i++) {
    final limit = i >= tailStart ? gap : oldGap;
    final a = data[i - 1]['x']!;
    final b = data[i]['x']!;
    if (b - a > limit) gaps.add(_Gap(a, b));
  }
  return gaps;
}

// Converts a real time (hours) to a chart position (hours) where every gap
// longer than [blank] is squeezed down to [blank].
double _compressX(double h, List<_Gap> gaps, double blank) {
  double shift = 0;
  for (final g in gaps) {
    final len = g.end - g.start;
    if (len <= blank) continue;
    if (h >= g.end) {
      shift += len - blank;
    } else if (h > g.start) {
      return g.start - shift + blank * ((h - g.start) / len);
    } else {
      break;
    }
  }
  return h - shift;
}

// ── Temperature Monitoring ────────────────────────────────────────────────────

class TemperatureMonitoring extends StatefulWidget {
  final VoidCallback? onSwitchToHumidity;
  final ValueChanged<double>? onMaxTempChanged;
  const TemperatureMonitoring({
    super.key,
    this.onSwitchToHumidity,
    this.onMaxTempChanged,
  });

  @override
  State<TemperatureMonitoring> createState() => _TemperatureMonitoringState();
}

class _TemperatureMonitoringState extends State<TemperatureMonitoring>
    with WidgetsBindingObserver {
  //added for ML insights
  String? _mlInsight;
  String? _mlRecommendation;
  String? _mlCondition;
  bool _mlLoading = false;

  int _selectedTab = 0;
  int _selectedTimeRange = 2;
  bool _isSprinklerLoading = false;
  bool _isLoading =
      !_todayBufferReady() &&
      (!SensorMemory.tempChartLoaded ||
          SensorMemory.lastTempChartDate != SensorMemory.todayKey());

  String _connectionStatus = LiveSensorService.connectionStatus.value;
  String _sensorStatus = LiveSensorService.sensorStatus.value;

  Timer? _durationTimer;
  DateTime? _sprinklerActivatedAt;

  double? _currentTemp;

  // static: keeps today's collected data across navigating away from and
  // back to this screen — same pattern as the Humidity screen. These used
  // to be per-instance fields, so leaving and returning threw away
  // everything collected so far and started over empty, waiting on a
  // fresh Firestore fetch.
  static final List<Map<String, double>> _minuteBufferToday = [];
  static String _minuteBufferDayKey = '';

  // Tracks whether the full-day Firestore history fetch has completed for
  // today, separately from _minuteBufferDayKey.
  //
  // _minuteBufferDayKey tells us which day the current buffer belongs to.
  // _todayHistoryFetchedDayKey tells us whether the complete history for
  // that day has already been fetched from Firestore.
  static String _todayHistoryFetchedDayKey = '';

  // Exact running stats for Today (independent of chart sampling).
  static double? _statMax;
  static double? _statMin;
  static double _statSum = 0;
  static int _statCount = 0;
  static DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);
  static const String _prefsKey = 'temp_today_v1';
  static DateTime? _lastDocTs; // timestamp of the last document counted
  static bool _syncing = false;

  static void _resetStats() {
    _statMax = null;
    _statMin = null;
    _statSum = 0;
    _statCount = 0;
  }

  static void _addToStats(double t) {
    if (_statMax == null || t > _statMax!) _statMax = t;
    if (_statMin == null || t < _statMin!) _statMin = t;
    _statSum += t;
    _statCount++;
  }

  static Future<void> _persistToday() async {
    try {
      final out = <List<double>>[];
      double lastX = -1;
      // Keep the last hour at full resolution (every 10s reading) so the
      // dotted part of the graph is complete after a restart. Older data
      // is thinned to one point per 30s.
      final fullResFrom = _minuteBufferToday.isEmpty
          ? 0.0
          : _minuteBufferToday.last['x']! - 1.0;
      for (final p in _minuteBufferToday) {
        final x = p['x']!;
        if (x >= fullResFrom || lastX < 0 || x - lastX >= 30 / 3600.0) {
          out.add([x, p['temp']!]);
          lastX = x;
        }
      }
      if (_minuteBufferToday.isNotEmpty &&
          _minuteBufferToday.last['x'] != lastX) {
        out.add([
          _minuteBufferToday.last['x']!,
          _minuteBufferToday.last['temp']!,
        ]);
      }
      final payload = jsonEncode({
        'day': _minuteBufferDayKey,
        'pts': out,
        'max': _statMax,
        'min': _statMin,
        'sum': _statSum,
        'count': _statCount,
        'lastTs': _lastDocTs?.millisecondsSinceEpoch,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, payload);
    } catch (e) {
      debugPrint('[Temp persist] failed: $e');
    }
  }

   static Future<bool> _restoreToday() async {
    if (_minuteBufferToday.isNotEmpty || _syncing) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return false;
      final m = jsonDecode(raw) as Map<String, dynamic>;
      if (m['day'] != SensorMemory.todayKey()) return false;
      final lastTs = (m['lastTs'] as num?)?.toInt();
      if (lastTs == null) return false;
      if (_minuteBufferToday.isNotEmpty || _syncing) return false;
      for (final p in (m['pts'] as List)) {
        _minuteBufferToday.add({
          'x': (p[0] as num).toDouble(),
          'temp': (p[1] as num).toDouble(),
          'avg': (p[1] as num).toDouble(),
          'min': (p[1] as num).toDouble(),
        });
      }
      _statMax = (m['max'] as num?)?.toDouble();
      _statMin = (m['min'] as num?)?.toDouble();
      _statSum = (m['sum'] as num?)?.toDouble() ?? 0;
      _statCount = (m['count'] as num?)?.toInt() ?? 0;
      _lastDocTs = DateTime.fromMillisecondsSinceEpoch(lastTs);
      _minuteBufferDayKey = m['day'] as String;
      return true;
    } catch (e) {
      debugPrint('[Temp restore] failed: $e');
      return false;
    }
  }

  // Minute-level data for Month, Week, and Custom — kept separate from
  // _minuteBufferToday since these cover ranges other than "today" and
  // aren't fed by live readings. Shared across all three (only one is ever
  // the active tab at a time), keyed by range+hour so switching ranges
  // triggers a fresh fetch.
  final List<Map<String, double>> _minuteBufferCustom = [];
  String _minuteCustomRangeKey = '';
  bool _minuteCustomLoading = false;
  bool _rangeLoadFailed = false;
  int _rangeRequestId = 0;

  // Keeps the loaded Week/Month so re-tapping a tab costs no Firestore reads.
  static final Map<int, Map<String, dynamic>> _rangeCache = {};

  // Start of the range that _minuteBufferCustom was loaded for. Used to
  // ignore stale data when a new week/month begins.
  DateTime? _minuteBufferRangeStart;

  static const double _kChartLeftPad = 40;
  static const double _kChartRightPad = 8;

  // Today's graph ends at the current time (hours since 12:00 AM).
  double _todayEndHours() {
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    double end = now.difference(midnight).inMilliseconds / 3600000.0;
    final data = _activeChartData;
    // Tolerate small clock differences between phone and ESP32.
    if (data.isNotEmpty && data.last['x']! > end) end = data.last['x']!;
    return end;
  }

  // Canvas is only as wide as 12:00 AM -> now (after gap compression).
  double _todayCanvasWidth(double endMapped) {
    final w =
        _kChartLeftPad + _kChartRightPad + endMapped * _todayChartPxPerHour;
    final minW = MediaQuery.of(context).size.width - 56;
    return w < minW ? minW : w;
  }

  // Pixel position of the newest reading on Today's canvas.
  double _todayLatestPx() {
    final data = _activeChartData;
    final endHours = _todayEndHours();
    final tailStart = (data.length - _kTodayTail).clamp(0, data.length);
    final gaps = _findGaps(data, gap: _kTodayGapHours, tailStart: tailStart);
    final endMapped = _compressX(endHours, gaps, _kTodayBlankHours);
    final latestX = data.isNotEmpty ? data.last['x']! : endHours;
    final latestMapped = _compressX(latestX, gaps, _kTodayBlankHours);
    final chartWidth =
        _todayCanvasWidth(endMapped) - _kChartLeftPad - _kChartRightPad;
    final frac = endMapped > 0 ? latestMapped / endMapped : 1.0;
    return _kChartLeftPad + frac * chartWidth;
  }

  // Exact statistics for This Month, This Week, and Custom.
  // These are calculated from EVERY Firestore reading in the selected range,
  // not from the compressed graph points.
  double? _rangeStatMax;
  double? _rangeStatMin;
  double _rangeStatSum = 0;
  int _rangeStatCount = 0;

  void _resetRangeStats() {
    _rangeStatMax = null;
    _rangeStatMin = null;
    _rangeStatSum = 0;
    _rangeStatCount = 0;
  }

  static bool _tempCacheIsToday() =>
      SensorMemory.lastTempChartDate == SensorMemory.todayKey();

  // True when today's readings are already in memory (or restored from
  // local storage), so the graph can be shown immediately.
  static bool _todayBufferReady() =>
      _minuteBufferToday.isNotEmpty &&
      _minuteBufferDayKey == SensorMemory.todayKey();

  String get _tempStatus {
    if (_currentTemp == null) return "";
    final t = _currentTemp!;

    if (t < 38.7) return "Low";
    if (t <= 39.8) return "Normal";
    return "High";
  }

  Color _tempStatusColor() {
    if (_currentTemp == null) return Colors.grey;

    final t = _currentTemp!;

    if (t < 38.7) return Colors.blue;
    if (t <= 39.8) return Colors.green;
    return Colors.red;
  }

  final List<Map<String, double>> _chartData = _tempCacheIsToday()
      ? List.of(SensorMemory.lastTempChartData)
      : [];

  List<Map<String, double>> get _activeChartData {
    if (_selectedTimeRange == 2) {
      final now = DateTime.now();
      final midnightMs = DateTime(
        now.year,
        now.month,
        now.day,
      ).millisecondsSinceEpoch;
      // After midnight, hide yesterday's points until the next sync clears them.
      final isStale =
          _minuteBufferDayKey.isNotEmpty &&
          _minuteBufferDayKey != SensorMemory.todayKey();
      final base = isStale ? <Map<String, double>>[] : _minuteBufferToday;
      final live = _livePoints.where((p) => p['ts']! >= midnightMs).toList();
      if (live.isEmpty) return base;
      final lastX = base.isEmpty ? -1.0 : base.last['x']!;
      final extra = live.where((p) => p['x']! > lastX).toList()
        ..sort((a, b) => a['x']!.compareTo(b['x']!));
      if (extra.isEmpty) return base;
      return [...base, ...extra];
    }
    // Week / Month / Custom: ignore data loaded for a previous range
    // (e.g. last week) until the new range has been fetched.
    final r = _resolveTimeRange(_selectedTimeRange, _customStart, _customEnd);
    if (r != null &&
        _minuteBufferRangeStart != null &&
        r.start != _minuteBufferRangeStart) {
      return <Map<String, double>>[];
    }
    return _minuteBufferCustom; // Month, Week, or Custom
  }

  // Average/Lowest/Highest now always come from the granular buffer for
  // every range (Today, Week, Month, Custom), mirroring the Humidity
  // screen. Today uses the exact unbounded running stats; other ranges
  // derive from whatever's in _minuteBufferCustom.
  double? get _activeDisplayMax {
    if (_selectedTimeRange == 2) {
      return _statCount > 0 ? _statMax : null;
    }

    return _rangeStatCount > 0 ? _rangeStatMax : null;
  }

  double? get _activeDisplayMin {
    if (_selectedTimeRange == 2) {
      return _statCount > 0 ? _statMin : null;
    }

    return _rangeStatCount > 0 ? _rangeStatMin : null;
  }

  double? get _activeDisplayAvg {
    if (_selectedTimeRange == 2) {
      return _statCount > 0 ? _statSum / _statCount : null;
    }

    return _rangeStatCount > 0 ? _rangeStatSum / _rangeStatCount : null;
  }

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DateTime? _customStart;
  DateTime? _customEnd;
  Timer? _hourlyRefreshTimer;
  Timer? _todaySyncTimer;

  // Today's chart is drawn on a wide canvas so every 10-second reading
  // gets its own dot. 10800 px/hour = 30 px between readings.
  static const double _todayChartPxPerHour = 10800;
  final ScrollController _todayChartScrollController = ScrollController();
  final ScrollController _customChartScrollController = ScrollController();
  bool _hasScrolledChartToNow = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _seedLivePointFromLatest(); // show the newest reading right away
    _initData();
    _loadSprinklerState();
    tempMaxTodayNotifier.addListener(_onTempMaxNotifierChanged);
    LiveSensorService.latestData.addListener(_onLiveDataChanged);
    LiveSensorService.connectionStatus.addListener(_onSharedStatusChanged);
    LiveSensorService.sensorStatus.addListener(_onSharedStatusChanged);
    // Pull new temperature_second readings into Today's graph every 10s,
    // matching the ESP32's 10s save interval.
    _todaySyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || !_wasTickerEnabled) return;
      if (_selectedTimeRange == 2) unawaited(_syncToday());
    });
    // Every minute: Week/Month check whether a new week/month started or
    // the hourly refresh is due. The range key makes this a no-op otherwise.
    _hourlyRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || _minuteCustomLoading || !_wasTickerEnabled) return;
      if (_selectedTimeRange == 0 || _selectedTimeRange == 1) {
        _loadMinuteChartForRange(_selectedTimeRange);
      }
    });
  }

  void _onSharedStatusChanged() {
    if (!mounted) return;
    setState(() {
      _connectionStatus = LiveSensorService.connectionStatus.value;
      _sensorStatus = LiveSensorService.sensorStatus.value;
      if (_sensorStatus == "Sensor Offline") _currentTemp = null;
    });
  }

  DateTime? _lastMlFetch;

  static final List<Map<String, double>> _livePoints = [];

  // Adds the newest live reading to the graph right away (when the screen
  // opens or the app comes back), instead of waiting for the next sensor
  // update.
  void _seedLivePointFromLatest() {
    if (LiveSensorService.sensorStatus.value == "Sensor Offline") return;
    final data = LiveSensorService.latestData.value;
    if (data == null) return;
    if ((data['ambientTempValid'] as bool? ?? true) == false) return;
    final t = (data['ambientTemp'] as num?)?.toDouble();
    if (t == null || t < 0 || t > 80) return;
    _currentTemp = t;
    _addLivePoint(t, data);
  }

  // When the app comes back from the background while this screen is open,
  // jump straight to "now" and pull in the readings that were missed.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    if (_selectedTimeRange != 2) return;
    _seedLivePointFromLatest();
    setState(() {});
    _scrollToNowSoon();
    unawaited(
      _syncToday().then((_) {
        if (mounted && _selectedTimeRange == 2) _scrollToNowSoon();
      }),
    );
  }

  void _addLivePoint(double temp, Map? data) {
    // Prefer the sensor's own timestamp so the dot lands on the same
    // 10-second slot as its Firestore document. Falls back to phone time.
    DateTime? ts;
    final rawTs = data?['timestamp'];
    if (rawTs is Timestamp) {
      ts = rawTs.toDate();
    } else if (rawTs is String) {
      ts = DateTime.tryParse(rawTs)?.toLocal();
    }
    ts ??= DateTime.now();

    final now = DateTime.now();
    final todayMidnight = DateTime(now.year, now.month, now.day);

    // Drop anything from a previous day.
    _livePoints.removeWhere(
      (p) => p['ts']! < todayMidnight.millisecondsSinceEpoch,
    );
    if (ts.isBefore(todayMidnight)) return;

    // Snap to the 10-second grid (:00, :10, :20 ...).
    final slotSec = (ts.difference(todayMidnight).inSeconds ~/ 10) * 10;
    final slotTime = todayMidnight.add(Duration(seconds: slotSec));
    final slotMs = slotTime.millisecondsSinceEpoch.toDouble();

    // One dot per slot: repeated notifications for the same reading
    // are ignored.
    if (_livePoints.any((p) => p['ts'] == slotMs)) return;

    _livePoints.add({
      'x': slotSec / 3600.0,
      'temp': temp,
      'avg': temp,
      'min': temp,
      'ts': slotMs,
    });
  }

  // Keeps the newest dot in view, but only if the user is already looking
  // near "now" (so it doesn't yank the view while browsing older data).
  void _followLiveIfNear() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _todayChartScrollController;
      if (!mounted || !c.hasClients || _selectedTimeRange != 2) return;

      final data = _activeChartData;
      if (data.isEmpty) return;
      final nowX = _todayLatestPx();
      final viewport = c.position.viewportDimension;

      if (nowX > c.offset + viewport * 0.85 &&
          nowX < c.offset + viewport + 200) {
        final target = (nowX - viewport * 0.6).clamp(
          0.0,
          c.position.maxScrollExtent,
        );
        c.animateTo(
          target,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // Reads every temperature_second document newer than the last one
  // counted, and adds each one to the graph and to the exact stats. Same
  // pattern as the Humidity screen's _syncToday.
  Future<void> _syncToday() async {
    // Prevent multiple Today sync operations from running at the same time.
    if (_syncing) return;

    _syncing = true;

    try {
      final now = DateTime.now();
      final todayKey = SensorMemory.todayKey();

      final midnight = DateTime(now.year, now.month, now.day);

      // ─────────────────────────────────────────────────────────────
      // NEW DAY CHECK
      // ─────────────────────────────────────────────────────────────

      if (_minuteBufferDayKey != todayKey) {
        _minuteBufferToday.clear();
        _livePoints.clear();

        _resetStats();

        _lastDocTs = null;

        _minuteBufferDayKey = todayKey;

        // Complete Firestore history for this new day
        // has not been fetched yet.
        _todayHistoryFetchedDayKey = '';
      }

      // ─────────────────────────────────────────────────────────────
      // CHECK IF COMPLETE TODAY HISTORY IS REQUIRED
      // ─────────────────────────────────────────────────────────────

      final bool needsFullHistory = _todayHistoryFetchedDayKey != todayKey;

      // ─────────────────────────────────────────────────────────────
      // IMPORTANT DUPLICATE-PREVENTION FIX
      //
      // _restoreToday() may have restored:
      //
      //   _minuteBufferToday
      //   _statMax
      //   _statMin
      //   _statSum
      //   _statCount
      //   _lastDocTs
      //
      // If we are going to perform a COMPLETE Firestore scan from
      // midnight, those restored values must first be cleared.
      //
      // Otherwise the restored readings would be counted once from
      // SharedPreferences and then counted again from Firestore.
      // ─────────────────────────────────────────────────────────────

      if (needsFullHistory) {
        _minuteBufferToday.clear();

        _resetStats();

        _lastDocTs = null;
      }

      // Full history:
      // Start immediately before midnight.
      //
      // Incremental update:
      // Start after the last document already counted.
      var cursor = needsFullHistory
          ? midnight.subtract(const Duration(milliseconds: 1))
          : (_lastDocTs ?? midnight.subtract(const Duration(milliseconds: 1)));

      // ─────────────────────────────────────────────────────────────
      // FIRESTORE PAGINATION
      // ─────────────────────────────────────────────────────────────

      while (true) {
        final snap = await _db
            .collection('temperature_second')
            .orderBy('timestamp', descending: false)
            .where('timestamp', isGreaterThan: Timestamp.fromDate(cursor))
            .limit(1000)
            .get();

        for (final doc in snap.docs) {
          final d = doc.data();

          final ts = (d['timestamp'] as Timestamp?)?.toDate();

          if (ts == null) {
            continue;
          }

          cursor = ts;

          final raw = d['ambientTemp'];

          if (raw == null) {
            continue;
          }

          final temp = (raw as num).toDouble();
          if (d['ambientTempValid'] == false || temp < 0 || temp > 80) continue;

          // Exact Today statistics.
          _addToStats(temp);

          // Today chart point.
          _minuteBufferToday.add({
            'x': ts.difference(midnight).inSeconds / 3600.0,
            'temp': temp,
            'avg': temp,
            'min': temp,
          });
        }

        // Remember newest document processed.
        _lastDocTs = cursor;

        // If fewer than 1000 documents were returned,
        // we reached the end.
        if (snap.docs.length < 1000) {
          break;
        }
      }

      // ─────────────────────────────────────────────────────────────
      // FULL HISTORY COMPLETED SUCCESSFULLY
      // ─────────────────────────────────────────────────────────────

      if (needsFullHistory) {
        _todayHistoryFetchedDayKey = todayKey;
      }

      // ─────────────────────────────────────────────────────────────
      // DASHBOARD MAXIMUM
      // ─────────────────────────────────────────────────────────────

      // Always push the exact max to the Dashboard, even if it is lower
      // than a stale/spiky stored value.
      if (_statMax != null && _statMax! != SensorMemory.lastTempMaxToday) {
        SensorMemory.lastTempMaxDate = todayKey;
        SensorMemory.setTempMaxToday(_statMax!);
        SensorMemory.save();
      }

      // Drop live points that Firestore has now delivered, so no reading is
      // drawn twice. The 6s margin covers the small gap between the phone's
      // receive time and the ESP32's document timestamp.
      if (_lastDocTs != null) {
        final lastMs = _lastDocTs!.millisecondsSinceEpoch + 6000;
        _livePoints.removeWhere((p) => p['ts']! <= lastMs);
      }

      // Refresh screen.
      if (mounted) {
        setState(() {});
      }

      // ─────────────────────────────────────────────────────────────
      // LOCAL PERSISTENCE
      // ─────────────────────────────────────────────────────────────

      final persistNow = DateTime.now();

      if (persistNow.difference(_lastPersist) > const Duration(seconds: 30)) {
        _lastPersist = persistNow;

        _persistToday();
      }
    } catch (e) {
      debugPrint('[Temp sync] failed: $e');
    } finally {
      // Always unlock synchronization.
      _syncing = false;
    }
  }

  // Loads persisted per-minute readings for any non-Today range (Month,
  // Week, or Custom). Unlike the Today buffer, these ranges are fixed and
  // never get live updates, so they're simply re-fetched whenever the
  // range actually changes (guarded by _minuteCustomRangeKey, keyed by
  // range + hour so Month/Week re-check once per hour as "now" advances).

  // Loads persisted per-minute readings for any non-Today range (Month,
  // Week, or Custom). Unlike the Today buffer, these ranges are fixed and
  // never get live updates, so they're simply re-fetched whenever the
  // range actually changes (guarded by _minuteCustomRangeKey, keyed by
  // range + hour so Month/Week re-check once per hour as "now" advances).
  //
  // Month/Week can span tens of thousands of minute docs — far too many to
  // fetch or render in one shot — so this always takes the MOST RECENT
  // ~1500 readings within the range (via descending order + limit, then
  // reversed back to chronological order) rather than the oldest, since
  // recent trends are what actually matter for monitoring.
  Future<void> _loadMinuteChartForRange(int rangeIndex) async {
    final range = _resolveTimeRange(rangeIndex, _customStart, _customEnd);

    if (range == null) return;

    final start = range.start;

    final now = DateTime.now();

    // Never request future sensor readings.
    final end = range.end.isAfter(now) ? now : range.end;

    // Custom is fixed to its selected timestamps.
    // Week/Month include the current hour so they refresh as time advances.
    final rangeKey = rangeIndex == 3
        ? '$rangeIndex-${start.millisecondsSinceEpoch}-${end.millisecondsSinceEpoch}'
        : '$rangeIndex-${start.millisecondsSinceEpoch}-${currentHourKey()}';

    if (_minuteCustomRangeKey == rangeKey) {
      return;
    }

    // Already loaded this hour: restore from memory, no Firestore reads.
    final cached = _rangeCache[rangeIndex];
    if (rangeIndex != 3 && cached != null && cached['key'] == rangeKey) {
      if (!mounted) return;
      setState(() {
        _minuteBufferCustom
          ..clear()
          ..addAll(List<Map<String, double>>.from(cached['points'] as List));
        _minuteCustomRangeKey = rangeKey;
        _minuteBufferRangeStart = start;
        _rangeStatMax = cached['max'] as double?;
        _rangeStatMin = cached['min'] as double?;
        _rangeStatSum = cached['sum'] as double;
        _rangeStatCount = cached['count'] as int;
        _minuteCustomLoading = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_customChartScrollController.hasClients) {
          _customChartScrollController.jumpTo(
            _customChartScrollController.position.maxScrollExtent,
          );
        }
      });
      return;
    }

    if (mounted) {
      setState(() {
        _minuteCustomLoading = true;
      });
    }

    final requestId = ++_rangeRequestId;
    _rangeLoadFailed = false;

    try {
      final points = await _fetchCompleteTempRange(start, end, requestId);

      if (!mounted ||
          requestId != _rangeRequestId ||
          _selectedTimeRange != rangeIndex) {
        return;
      }

      // User may have changed Custom while the query was running.
      if (rangeIndex == 3 &&
          (_customStart != start || _customEnd != range.end)) {
        return;
      }

      setState(() {
        _minuteBufferCustom
          ..clear()
          ..addAll(points);

        _minuteCustomRangeKey = rangeKey;
        _minuteBufferRangeStart = start;
        if (rangeIndex != 3) {
          _rangeCache[rangeIndex] = {
            'key': rangeKey,
            'points': List<Map<String, double>>.from(points),
            'max': _rangeStatMax,
            'min': _rangeStatMin,
            'sum': _rangeStatSum,
            'count': _rangeStatCount,
          };
        }
      });

      if (rangeIndex != 3) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_customChartScrollController.hasClients) {
            return;
          }

          _customChartScrollController.jumpTo(
            _customChartScrollController.position.maxScrollExtent,
          );
        });
      }
    } catch (e) {
      debugPrint('[MinuteChart/temp range] query failed: $e');
      if (requestId == _rangeRequestId) _rangeLoadFailed = true;
    } finally {
      if (requestId == _rangeRequestId) _minuteCustomLoading = false;

      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<List<Map<String, double>>> _fetchCompleteTempRange(
    DateTime start,
    DateTime end,
    int requestId,
  ) async {
    if (!end.isAfter(start)) {
      _resetRangeStats();
      return [];
    }
    double? sMax;
    double? sMin;
    double sSum = 0;
    int sCount = 0;

    // Keep the graph lightweight while statistics remain exact.
    const int graphBucketCount = 300;
    const int pageSize = 1000;

    final totalMs = end.difference(start).inMilliseconds;

    final bucketSum = List<double>.filled(graphBucketCount, 0);

    final bucketCount = List<int>.filled(graphBucketCount, 0);

    final bucketMin = List<double?>.filled(graphBucketCount, null);

    final bucketMax = List<double?>.filled(graphBucketCount, null);

    final bucketXSum = List<double>.filled(graphBucketCount, 0);

    DateTime cursor = start.subtract(const Duration(milliseconds: 1));

    while (true) {
      final snapshot = await _db
          .collection('temperature_second')
          .orderBy('timestamp', descending: false)
          .where('timestamp', isGreaterThan: Timestamp.fromDate(cursor))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .limit(pageSize)
          .get()
          .timeout(const Duration(seconds: 20));

      if (requestId != _rangeRequestId) return [];

      if (snapshot.docs.isEmpty) {
        break;
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();

        final raw = data['ambientTemp'];
        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

        if (timestamp == null) {
          continue;
        }

        // Always move the cursor forward even if a sensor value
        // happens to be missing.
        cursor = timestamp;

        if (raw == null) {
          continue;
        }

        if (timestamp.isBefore(start) || timestamp.isAfter(end)) {
          continue;
        }

        final value = (raw as num).toDouble();
        if (data['ambientTempValid'] == false || value < 0 || value > 80)
          continue;

        // -----------------------------------------------
        // EXACT RANGE STATISTICS
        // -----------------------------------------------

        if (sMax == null || value > sMax) sMax = value;
        if (sMin == null || value < sMin) sMin = value;
        sSum += value;
        sCount++;

        // -----------------------------------------------
        // GRAPH AGGREGATION
        // -----------------------------------------------

        final elapsedMs = timestamp.difference(start).inMilliseconds;

        int bucketIndex = ((elapsedMs / totalMs) * graphBucketCount).floor();

        if (bucketIndex < 0) {
          bucketIndex = 0;
        }

        if (bucketIndex >= graphBucketCount) {
          bucketIndex = graphBucketCount - 1;
        }

        final x = timestamp.difference(start).inSeconds / 3600.0;

        bucketSum[bucketIndex] += value;
        bucketCount[bucketIndex]++;
        bucketXSum[bucketIndex] += x;

        final currentMin = bucketMin[bucketIndex];
        final currentMax = bucketMax[bucketIndex];

        if (currentMin == null || value < currentMin) {
          bucketMin[bucketIndex] = value;
        }

        if (currentMax == null || value > currentMax) {
          bucketMax[bucketIndex] = value;
        }
      }

      if (snapshot.docs.length < pageSize) {
        break;
      }
    }

    if (requestId != _rangeRequestId) return [];
    _rangeStatMax = sMax;
    _rangeStatMin = sMin;
    _rangeStatSum = sSum;
    _rangeStatCount = sCount;

    final points = <Map<String, double>>[];

    for (int i = 0; i < graphBucketCount; i++) {
      final count = bucketCount[i];

      if (count == 0) {
        continue;
      }

      final average = bucketSum[i] / count;
      final x = bucketXSum[i] / count;

      points.add({
        'x': x,

        // Keep temp as the average because your existing
        // painter expects this field for the graph.
        'temp': average,

        'avg': average,

        // Preserve actual bucket extremes.
        'min': bucketMin[i]!,
        'max': bucketMax[i]!,
      });
    }

    return points;
  }

  void _onLiveDataChanged() {
    if (!mounted) return;

    // If sensor is offline, remove the live temperature immediately.
    // This also prevents stale latestData from putting the old value back.
    if (LiveSensorService.sensorStatus.value == "Sensor Offline") {
      if (_currentTemp != null) {
        setState(() {
          _currentTemp = null;
        });
      }
      return;
    }

    final data = LiveSensorService.latestData.value;

    if (data == null) {
      if (_currentTemp != null) {
        setState(() {
          _currentTemp = null;
        });
      }
      return;
    }

    final tempValid = data['ambientTempValid'] as bool? ?? true;

    if (!tempValid) {
      debugPrint('[Temperature] Invalid AMG8833 live reading.');

      if (_currentTemp != null) {
        setState(() {
          _currentTemp = null;
        });
      }
      return;
    }

    final tempLive = (data['ambientTemp'] as num?)?.toDouble();

    if (tempLive == null || tempLive < 0 || tempLive > 80) {
      if (_currentTemp != null) {
        setState(() {
          _currentTemp = null;
        });
      }
      return;
    }

    final humLive = (data['humidity'] as num?)?.toDouble();

    setState(() {
      _currentTemp = tempLive;
      _isLoading = false;
      _addLivePoint(tempLive, data);
    });
    _followLiveIfNear();

    SensorMemory.resetIfNewDay();

    if (tempLive > SensorMemory.lastTempMaxToday) {
      SensorMemory.setTempMaxToday(tempLive);
      SensorMemory.save();
    }

    final now = DateTime.now();

    if (_lastMlFetch == null ||
        now.difference(_lastMlFetch!) > const Duration(minutes: 1)) {
      _lastMlFetch = now;

      if (humLive != null) {
        _fetchTemperatureMLInsight(tempLive, humLive);
      }
    }
  }

  void _onTempMaxNotifierChanged() {
    if (!mounted) return;
    final v = tempMaxTodayNotifier.value;
    if (v > 0 && _selectedTimeRange == 2) {
      widget.onMaxTempChanged?.call(v);
      setState(() {}); // rebuild so _activeDisplayMax picks up the new value
    }
  }

  // Keeps "Highest" in sync with the same ratcheted value the Dashboard's
  // Quick Stats card reads — otherwise this screen shows the stale
  // hourly-aggregate max until the next temperature_hourly doc lands.

  Future<void> _loadSprinklerState() async {
    await SprinklerMemory.load();
    if (!mounted) return;
    if (SprinklerMemory.activatedAt != null) {
      _startDurationTimer(SprinklerMemory.activatedAt!);
    }
  }

  void _startDurationTimer(DateTime activatedAt) {
    _durationTimer?.cancel();
    _sprinklerActivatedAt = activatedAt;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final elapsed = DateTime.now().difference(_sprinklerActivatedAt!);
      final mins = elapsed.inMinutes;
      final secs = elapsed.inSeconds % 60;
      final d = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
      SprinklerMemory.duration = d;
    });
  }

  void _stopDurationTimer({bool keepDuration = false}) {
    _durationTimer?.cancel();
    _durationTimer = null;
    if (keepDuration && _sprinklerActivatedAt != null) {
      final elapsed = DateTime.now().difference(_sprinklerActivatedAt!);
      final mins = elapsed.inMinutes;
      final secs = elapsed.inSeconds % 60;
      SprinklerMemory.duration = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    }
    _sprinklerActivatedAt = null;
  }

  Future<void> _initData() async {
    if (_selectedTimeRange != 2) {
      await _loadMinuteChartForRange(_selectedTimeRange);
    } else {
      final restored = await _restoreToday();

      // If today's data is already in memory (previous visit) or was just
      // restored from local storage, show it immediately and only fetch
      // what was missed, instead of waiting on a full reload.
      final todayKey = SensorMemory.todayKey();
      if (restored) _todayHistoryFetchedDayKey = todayKey;
      if (_minuteBufferToday.isNotEmpty && _minuteBufferDayKey == todayKey) {
        _seedLivePointFromLatest();
        if (mounted) setState(() => _isLoading = false);
        _scrollToNowSoon();
      }

      await _syncToday();
      _scrollToNowSoon(); // data is complete now, go to the latest reading
    }
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (LiveSensorService.latestData.value != null) {
      _onLiveDataChanged();
    }
  }

  bool _wasTickerEnabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled = TickerMode.of(context);
    if (enabled && !_wasTickerEnabled) {
      // Screen is visible again after navigating away.
      if (_selectedTimeRange != 2) {
        setState(() {
          _selectedTimeRange = 2; // go back to the Today tab
          _clearStatsForRangeSwitch();
        });
      }
      _seedLivePointFromLatest();
      _scrollToNowSoon();
      unawaited(
        _syncToday().then((_) {
          if (mounted && _selectedTimeRange == 2) _scrollToNowSoon();
        }),
      );
    }
    _wasTickerEnabled = enabled;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _hourlyRefreshTimer?.cancel();
    _todaySyncTimer?.cancel();
    _todayChartScrollController.dispose();
    _customChartScrollController.dispose();
    tempMaxTodayNotifier.removeListener(_onTempMaxNotifierChanged);
    LiveSensorService.latestData.removeListener(_onLiveDataChanged);
    LiveSensorService.connectionStatus.removeListener(_onSharedStatusChanged);
    LiveSensorService.sensorStatus.removeListener(_onSharedStatusChanged);
    super.dispose();
  }

  // Helper that immediately clears stale stats + chart when the user
  // switches tabs, so old values never show under a new range.
  void _clearStatsForRangeSwitch() {
    _chartData.clear();
    _minuteBufferCustom.clear();
    _minuteCustomRangeKey = '';
    _minuteBufferRangeStart = null;

    // Clear exact Week/Month/Custom statistics too.
    _resetRangeStats();
    _rangeRequestId++;
  }

  // ── Sprinkler ───────────────────────────────────────────────────────────────

  Future<void> _toggleSprinkler(bool turnOn) async {
    setState(() => _isSprinklerLoading = true);
    try {
      // Fire the LAN command first — this is what makes the relay flip
      // instantly instead of waiting for the ESP32's 2s Firestore poll.
      unawaited(
        http
            .post(
              Uri.parse('http://$esp32Ip/sprinkler'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'state': turnOn ? 'on' : 'off'}),
            )
            .timeout(const Duration(seconds: 2))
            .then((_) {})
            .catchError((e) {
              debugPrint('[Sprinkler] LAN command failed: $e');
            }),
      );

      await FirebaseFirestore.instance
          .collection('sprinkler_command')
          .doc('pending')
          .set({'state': turnOn ? 'on' : 'off'});

      sprinklerToggledAt = DateTime.now();
      sprinklerNotifier.value = turnOn;
      final now = DateTime.now();

      if (turnOn) {
        final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
        final minute = now.minute.toString().padLeft(2, '0');
        final period = now.hour < 12 ? 'AM' : 'PM';
        final timeStr = '$hour:$minute $period';
        const months = [
          'Jan',
          'Feb',
          'Mar',
          'Apr',
          'May',
          'Jun',
          'Jul',
          'Aug',
          'Sep',
          'Oct',
          'Nov',
          'Dec',
        ];
        final dateStr =
            '${months[now.month - 1]} ${now.day.toString().padLeft(2, '0')}';

        SprinklerMemory.lastActivated = timeStr;
        SprinklerMemory.date = dateStr;
        SprinklerMemory.duration = '0s';
        SprinklerMemory.status = "ON";
        SprinklerMemory.activatedAt = now;
        await SprinklerMemory.save();

        _startDurationTimer(now);
      } else {
        String finalDuration = '--';
        if (_sprinklerActivatedAt != null) {
          final elapsed = now.difference(_sprinklerActivatedAt!);
          final mins = elapsed.inMinutes;
          final secs = elapsed.inSeconds % 60;
          finalDuration = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
        }
        SprinklerMemory.duration = finalDuration;
        SprinklerMemory.status = "OFF";
        SprinklerMemory.activatedAt = null;
        await SprinklerMemory.save();

        _stopDurationTimer(keepDuration: true);
      }
    } catch (_) {
      _showSnackBar("Failed to send sprinkler command");
    } finally {
      if (mounted) setState(() => _isSprinklerLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Color _cardBg(bool isDark) => isDark ? const Color(0xFF1E1E1E) : Colors.white;
  Color _textPrimary(bool isDark) =>
      isDark ? Colors.white : const Color(0xFF1B3A4B);
  Color _textSecondary(bool isDark) =>
      isDark ? Colors.white54 : Colors.grey.shade500;
  Color _dividerColor(bool isDark) =>
      isDark ? Colors.white12 : Colors.grey.shade200;

  BoxDecoration _bentoCard(bool isDark, {Color? accentColor}) => BoxDecoration(
    color: _cardBg(isDark),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(
      color:
          accentColor?.withValues(alpha: 0.2) ??
          (isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.grey.shade200),
      width: 1.2,
    ),
    boxShadow: [
      BoxShadow(
        color:
            accentColor?.withValues(alpha: isDark ? 0.15 : 0.08) ??
            Colors.black.withValues(alpha: isDark ? 0.35 : 0.07),
        blurRadius: 16,
        offset: const Offset(0, 6),
      ),
      if (!isDark)
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.9),
          blurRadius: 1,
          offset: const Offset(0, -1),
        ),
    ],
  );

  Widget _buildConnectionBadge() {
    final Color badgeColor;
    final Color bgColor;
    if (_connectionStatus == "Live") {
      badgeColor = Colors.green;
      bgColor = Colors.green.shade100;
    } else if (_connectionStatus == "Reconnecting..." ||
        _connectionStatus == "Connecting...") {
      badgeColor = Colors.orange;
      bgColor = Colors.orange.shade100;
    } else {
      badgeColor = Colors.red;
      bgColor = Colors.red.shade100;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: badgeColor),
          const SizedBox(width: 4),
          Text(
            _connectionStatus,
            style: TextStyle(fontSize: 11, color: badgeColor),
          ),
        ],
      ),
    );
  }

  bool _isSprinklerDialogOpen = false;

  Future<void> _confirmSprinkler() async {
    if (_isSprinklerLoading || _isSprinklerDialogOpen) return;
    _isSprinklerDialogOpen = true;

    final isOn = sprinklerNotifier.value;

    if (_sensorStatus != "Sensor Online" && !isOn) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.sensors_off, color: Colors.red, size: 20),
              SizedBox(width: 8),
              Text('Sensor Offline'),
            ],
          ),
          content: const Text(
            'Cannot activate the sprinkler while the sensor is offline. Please ensure the sensor is online and try again.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      _isSprinklerDialogOpen = false;
      return;
    }

    final action = isOn ? 'Deactivate' : 'Activate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$action Sprinkler?'),
        content: Text(
          isOn
              ? 'Are you sure you want to turn the sprinkler off?'
              : 'Are you sure you want to turn the sprinkler on?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isOn ? const Color(0xFFD32F2F) : Colors.green,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(action, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    _isSprinklerDialogOpen = false;
    if (!mounted) return;
    if (confirmed == true) await _toggleSprinkler(!isOn);
  }

  // ── Custom range picker ─────────────────────────────────────────────────────

  Future<void> _showCustomRangePicker() async {
    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomRangeSheet(
        initialStart: _customStart,
        initialEnd: _customEnd,
        onApply: (start, end) {
          setState(() {
            _customStart = start;
            _customEnd = end;
            _selectedTimeRange = 3;
            // Clear stale stats when custom range is applied.
            _clearStatsForRangeSwitch();
          });
          _loadMinuteChartForRange(3);
        },
      ),
    );

    if (!mounted) return;

    // If the sheet was dismissed (X button, back gesture, or tap outside)
    // without the user ever applying a range, don't leave the UI parked
    // on an empty Custom tab — fall back to Today.
    final wasApplied = applied == true;
    if (!wasApplied && _customStart != null && _customEnd != null) {
      _loadMinuteChartForRange(3);
    }
    if (!wasApplied && _customStart == null) {
      setState(() {
        _selectedTimeRange = 2;
        _clearStatsForRangeSwitch();
      });
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.all(16), child: AppTopBar()),
          const SizedBox(height: 5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildTitle(),
                const SizedBox(height: 16),
                CustomTabBar(
                  selectedIndex: _selectedTab,
                  tabs: const ['Temperature', 'Humidity'],
                  onTabSelected: (index) {
                    setState(() => _selectedTab = index);
                    if (index == 1) widget.onSwitchToHumidity?.call();
                  },
                ),
                const SizedBox(height: 16),
                _buildStatusCard(isDark),
                const SizedBox(height: 12),
                _buildTimeRangeSelector(isDark),
                if (_selectedTimeRange == 3 &&
                    _customStart != null &&
                    _customEnd != null) ...[
                  const SizedBox(height: 8),
                  _buildCustomRangeBanner(),
                ],
                const SizedBox(height: 16),
                _buildChart(isDark),
                const SizedBox(height: 16),
                _buildTemperatureReview(isDark),
                const SizedBox(height: 16),
                _buildInsights(isDark),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTitle() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark ? Colors.white : Colors.black;
    final sensorOnline = _sensorStatus == "Sensor Online";
    final isNoInternet = _connectionStatus == "No Connection";
    final sensorColor = sensorOnline ? Colors.green : Colors.red;
    // When there's no internet at all, the ESP32 might be perfectly fine —
    // we simply have no way to check it. Saying "Sensor Offline" in that
    // case wrongly implies the device itself is broken. Show the same
    // "No Internet" reason on both badges instead of two conflicting
    // messages.
    final sensorLabel = isNoInternet
        ? "No Internet"
        : (sensorOnline ? "Sensor Online" : "Sensor Offline");

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.thermostat, size: 32, color: color),
            const SizedBox(width: 12),
            Text(
              'Temperature',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildConnectionBadge(),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: sensorColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: sensorColor, width: 1),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    sensorOnline ? Icons.sensors : Icons.sensors_off,
                    size: 12,
                    color: sensorColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    sensorLabel,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: sensorColor,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatusCard(bool isDark) {
    final currentLabel = _currentTemp != null
        ? '${_currentTemp!.toStringAsFixed(1)}°C'
        : '--';

    final statusColor = _tempStatusColor();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: _bentoCard(isDark),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _tempStatus,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              _isLoading
                  ? const CircularProgressIndicator()
                  : Text(
                      currentLabel,
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: _currentTemp == null
                            ? _textPrimary(isDark)
                            : statusColor,
                      ),
                    ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}',
                style: TextStyle(color: _textSecondary(isDark), fontSize: 13),
              ),
              const SizedBox(height: 10),
              ValueListenableBuilder<bool>(
                valueListenable: sprinklerNotifier,
                builder: (context, isActive, _) => GestureDetector(
                  onTap: _isSprinklerLoading ? null : _confirmSprinkler,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: _isSprinklerLoading
                          ? Colors.grey.shade400
                          : isActive
                          ? Colors.green
                          : const Color(0xFFD32F2F),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: _isSprinklerLoading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isActive ? Icons.check_circle : Icons.shower,
                                color: Colors.white,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                isActive ? 'Active' : 'Activate',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTimeRangeSelector(bool isDark) {
    return Row(
      children: List.generate(kTimeRanges.length, (index) {
        final isSelected = _selectedTimeRange == index;
        final isCustom = index == 3;
        return Expanded(
          child: GestureDetector(
            onTap: () async {
              // Clear stale stats immediately on tap so the Temperature
              // Review never shows values from the previous range while
              // the new range's data is loading.
              setState(() {
                _selectedTimeRange = index;
                _clearStatsForRangeSwitch();
              });
              if (isCustom) {
                await _showCustomRangePicker();
              } else if (index == 2) {
                unawaited(_syncToday());
              } else {
                _loadMinuteChartForRange(index);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(
                right: index < kTimeRanges.length - 1 ? 6 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE8622A) : _cardBg(isDark),
                border: Border.all(
                  color: isCustom && !isSelected
                      ? const Color(0xFFE8622A).withValues(alpha: 0.5)
                      : isSelected
                      ? const Color(0xFFE8622A)
                      : _dividerColor(isDark),
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: const Color(0xFFE8622A).withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCustom) ...[
                    Icon(
                      Icons.date_range_outlined,
                      size: 11,
                      color: isSelected
                          ? Colors.white
                          : const Color(0xFFE8622A),
                    ),
                    const SizedBox(width: 3),
                  ],
                  Text(
                    kTimeRanges[index],
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : isCustom
                          ? const Color(0xFFE8622A)
                          : _textSecondary(isDark),
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildCustomRangeBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE8622A).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFE8622A).withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.schedule, size: 14, color: Color(0xFFE8622A)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${_formatDateTime(_customStart!)}  →  ${_formatDateTime(_customEnd!)}',
              style: const TextStyle(
                fontSize: 11,
                color: Color(0xFFE8622A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() {
                _customStart = null;
                _customEnd = null;
                _selectedTimeRange = 2;
                _clearStatsForRangeSwitch();
              });
            },
            child: const Icon(Icons.close, size: 14, color: Color(0xFFE8622A)),
          ),
        ],
      ),
    );
  }

  void _scrollChartToNow() {
    if (!mounted) return;
    final c = _todayChartScrollController;
    if (!c.hasClients) {
      // Chart not mounted yet: allow the next build to try again.
      _hasScrolledChartToNow = false;
      return;
    }

    final latestPx = _todayLatestPx();
    final viewport = c.position.viewportDimension;
    final target = (latestPx - viewport * 0.6).clamp(
      0.0,
      c.position.maxScrollExtent,
    );
    c.jumpTo(target);
  }

  // Jumps to "now" after the next frame has been built.
  void _scrollToNowSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _scrollChartToNow();
    });
  }

  Widget _buildChart(bool isDark) {
    final bool isTodayTab = _selectedTimeRange == 2;
    final bool isCustomTab =
        _selectedTimeRange == 0 ||
        _selectedTimeRange == 1 ||
        (_selectedTimeRange == 3 && _customStart != null && _customEnd != null);
    final DateTimeRange? chartRange = _resolveTimeRange(
      _selectedTimeRange,
      _customStart,
      _customEnd,
    );
    // (line removed: Today's width is now computed from the current time)

    final bool isBusy =
        _isLoading || (_selectedTimeRange != 2 && _minuteCustomLoading);

    // The scroll view is destroyed in these cases, so the next time the Today
    // chart appears it must jump to the latest reading again.
    if (!isTodayTab || isBusy || _activeChartData.isEmpty) {
      _hasScrolledChartToNow = false;
    }

    Widget chartBody;
    if (isBusy) {
      chartBody = const Center(child: CircularProgressIndicator());
    } else if (_activeChartData.isEmpty) {
      chartBody = Center(
        child: Text(
          _selectedTimeRange == 2
              ? "Waiting for live readings..."
              : _rangeLoadFailed
              ? "Could not load data. Tap the range again to retry."
              : "No data for selected range",
          style: TextStyle(color: _textSecondary(isDark)),
        ),
      );
    } else if (isTodayTab) {
      // Center the view on the current time once per load, so opening
      // the tab shows "now" instead of midnight — swipe left to page
      // back through the rest of the day.
      if (!_hasScrolledChartToNow) {
        _hasScrolledChartToNow = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollChartToNow(),
        );
      }
      final todayData = _activeChartData;
      final endHours = _todayEndHours();
      final todayGaps = _findGaps(
        todayData,
        gap: _kTodayGapHours,
        tailStart: (todayData.length - _kTodayTail).clamp(0, todayData.length),
      );
      final endMapped = _compressX(endHours, todayGaps, _kTodayBlankHours);
      final todayWidth = _todayCanvasWidth(endMapped);

      chartBody = Stack(
        children: [
          ClipRect(
            child: SingleChildScrollView(
              controller: _todayChartScrollController,
              scrollDirection: Axis.horizontal,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _TemperatureChartPainter(
                    data: List.from(todayData),
                    isDark: isDark,
                    xDomainMin: 0,
                    xDomainMax: endHours, // 12:00 AM -> now
                    showYAxisLabels: false,
                    rawTailCount: 360, // last hour, every reading
                    dotTailCount: 360, // a dot on each of them
                    gapHours: _kTodayGapHours,
                    gapBlankHours: _kTodayBlankHours,
                  ),
                  child: SizedBox(height: 320, width: todayWidth),
                ),
              ),
            ),
          ),
          // Fixed overlay so the °C labels stay visible on the right
          // edge of the card while the chart itself scrolls.
          Positioned.fill(child: _buildFixedYAxisLabels(isDark)),
        ],
      );
    } else if (isCustomTab) {
      final nowCap = DateTime.now();
      final chartEnd =
          (_selectedTimeRange != 3 && chartRange!.end.isAfter(nowCap))
          ? nowCap
          : chartRange!.end;
      final spanHours = chartEnd.difference(chartRange.start).inMinutes / 60.0;
      final pxPerHour = spanHours <= 72
          ? 60.0
          : (spanHours <= 336 ? 15.0 : 8.0);
      final minWidth = MediaQuery.of(context).size.width - 56;
      final customWidth = (spanHours * pxPerHour)
          .clamp(minWidth < 1300.0 ? 1300.0 : minWidth, 12000.0)
          .toDouble();
      chartBody = Stack(
        children: [
          ClipRect(
            child: SingleChildScrollView(
              controller: _customChartScrollController,
              scrollDirection: Axis.horizontal,
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _TemperatureChartPainter(
                    data: List.from(_activeChartData),
                    isDark: isDark,
                    xDomainMin: 0,
                    xDomainMax: spanHours,
                    rangeStart: chartRange.start,
                    showYAxisLabels: false,

                    gapHours: spanHours / 300 * 2.5,
                    gapBlankHours: double.infinity,
                  ),
                  child: SizedBox(height: 320, width: customWidth),
                ),
              ),
            ),
          ),
          Positioned.fill(child: _buildFixedYAxisLabels(isDark)),
        ],
      );
    } else {
      chartBody = ClipRect(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _TemperatureChartPainter(
              data: List.from(_activeChartData),
              isDark: isDark,
            ),
            child: const SizedBox(height: 320, width: double.infinity),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: _bentoCard(isDark, accentColor: Colors.green),
          padding: const EdgeInsets.all(12),
          child: SizedBox(
            height: 320,
            width: double.infinity,
            child: chartBody,
          ),
        ),
      ],
    );
  }

  // Renders the °C Y-axis labels as a fixed overlay pinned to the right
  // edge of the chart card. Used only for the Today tab, whose chart
  // canvas scrolls horizontally — without this, the labels would scroll
  // away with the rest of the painted content.
  Widget _buildFixedYAxisLabels(bool isDark) {
    const double topPadding = 8;
    const double bottomPadding = 44;
    const double chartHeight = 320 - topPadding - bottomPadding;
    const double yMin = 0.0;
    const double yMax = 50.0;
    final labelStyle = TextStyle(
      color: isDark ? Colors.white54 : Colors.grey.shade500,
      fontSize: 10,
      fontWeight: FontWeight.w500,
    );
    return IgnorePointer(
      child: Stack(
        children: [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50].map((v) {
          final y =
              topPadding +
              chartHeight -
              ((v - yMin) / (yMax - yMin)) * chartHeight;
          return Positioned(
            top: v == 0 ? y - 18 : y - 8,
            left: 0,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: (isDark ? const Color(0xFF1E1E1E) : Colors.white)
                    .withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('$v°C', style: labelStyle),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTemperatureReview(bool isDark) {
    final avgLabel = _activeDisplayAvg != null
        ? '${_activeDisplayAvg!.toStringAsFixed(1)}°C'
        : '--';
    final minLabel = _activeDisplayMin != null
        ? '${_activeDisplayMin!.toStringAsFixed(1)}°C'
        : '--';
    final maxLabel = _activeDisplayMax != null
        ? '${_activeDisplayMax!.toStringAsFixed(1)}°C'
        : '--';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _bentoCard(isDark, accentColor: const Color(0xFF1B3A4B)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1B3A4B).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.thermostat,
                  color: isDark ? Colors.white70 : const Color(0xFF1B3A4B),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Temperature Review',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _textPrimary(isDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              children: [
                _buildReviewStat(
                  'Average',
                  avgLabel,
                  const Color(0xFFE8622A),
                  isDark,
                ),
                VerticalDivider(color: _dividerColor(isDark), thickness: 1),
                _buildReviewStat(
                  'Lowest',
                  minLabel,
                  const Color(0xFF1B3A4B),
                  isDark,
                ),
                VerticalDivider(color: _dividerColor(isDark), thickness: 1),
                _buildReviewStat('Highest', maxLabel, Colors.red, isDark),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _selectedTimeRange == 2
                ? 'Based on $_statCount readings'
                : 'Based on $_rangeStatCount readings',
            style: TextStyle(fontSize: 11, color: _textSecondary(isDark)),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStat(
    String label,
    String value,
    Color valueColor,
    bool isDark,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: valueColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: _textPrimary(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsights(bool isDark) {
    Color conditionColor = const Color(0xFFE8A020); // amber default
    if (_mlCondition == 'Good') conditionColor = Colors.green;
    if (_mlCondition == 'High Risk') conditionColor = Colors.red;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFFE8A020).withValues(alpha: 0.12)
            : const Color(0xFFFFF9C4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(
            0xFFE8A020,
          ).withValues(alpha: isDark ? 0.25 : 0.15),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(
              0xFFE8A020,
            ).withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8A020).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  color: Color(0xFFE8A020),
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Insights',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _textPrimary(isDark),
                ),
              ),
              const Spacer(),
              // Condition badge
              if (_mlCondition != null && !_mlLoading)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: conditionColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: conditionColor, width: 1),
                  ),
                  child: Text(
                    _mlCondition!,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: conditionColor,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // Body
          if (_mlLoading)
            Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: const Color(0xFFE8A020),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Analyzing temperature data...',
                  style: TextStyle(fontSize: 12, color: _textSecondary(isDark)),
                ),
              ],
            )
          else if (_currentTemp == null)
            Text(
              'Connect sensor to receive temperature insights.',
              style: TextStyle(fontSize: 12, color: _textSecondary(isDark)),
            )
          else if (_mlInsight == null)
            Text(
              'Waiting for analysis...',
              style: TextStyle(fontSize: 12, color: _textSecondary(isDark)),
            )
          else ...[
            Text(
              _mlInsight!,
              style: TextStyle(fontSize: 12, color: _textSecondary(isDark)),
            ),
            if (_mlRecommendation != null) ...[
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.arrow_right, size: 16, color: conditionColor),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _mlRecommendation!,
                      style: TextStyle(
                        fontSize: 12,
                        color: _textSecondary(isDark),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ],
      ),
    );
  }

  //ml part
  Future<void> _fetchTemperatureMLInsight(
    double temperature,
    double humidity,
  ) async {
    if (temperature <= 0) return;
    setState(() => _mlLoading = true);
    try {
      final result = await MlService.analyzeFarm(
        temperatureC: temperature,
        humidityPct: humidity, // neutral humidity — not the focus here
        weightChangeKg: 0.0,
        feedIntakeKg: 0.0,
      );
      if (!mounted) return;
      setState(() {
        _mlCondition = result['condition'] as String?;
        _mlInsight = (result['insights'] as List?)?.join(' ');
        _mlRecommendation =
            ((result['recommendations'] as List?)?.isNotEmpty ?? false)
                ? (result['recommendations'] as List).first as String?
                : null;
        _mlLoading = false;
      });
    } catch (e) {
      debugPrint('Temperature ML error: $e');
      if (!mounted) return;
      setState(() => _mlLoading = false);
    }
  }
}

// ── Custom Range Bottom Sheet ─────────────────────────────────────────────────

class _CustomRangeSheet extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final void Function(DateTime start, DateTime end) onApply;

  const _CustomRangeSheet({
    required this.onApply,
    this.initialStart,
    this.initialEnd,
  });

  @override
  State<_CustomRangeSheet> createState() => _CustomRangeSheetState();
}

class _CustomRangeSheetState extends State<_CustomRangeSheet> {
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = widget.initialStart ?? now;
    _startTime = TimeOfDay.fromDateTime(widget.initialStart ?? now);
    _endDate = widget.initialEnd ?? now;
    _endTime = TimeOfDay.fromDateTime(widget.initialEnd ?? now);
  }

  DateTime get _fullStart => DateTime(
    _startDate.year,
    _startDate.month,
    _startDate.day,
    _startTime.hour,
    _startTime.minute,
  );
  DateTime get _fullEnd => DateTime(
    _endDate.year,
    _endDate.month,
    _endDate.day,
    _endTime.hour,
    _endTime.minute,
  );
  bool get _isValid => _fullStart.isBefore(_fullEnd);

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: Color(0xFFE8622A)),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => isStart ? _startDate = picked : _endDate = picked);
  }

  Future<void> _pickTime(bool isStart) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: false),
        child: Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFFE8622A)),
          ),
          child: child!,
        ),
      ),
    );
    if (picked == null) return;
    setState(() => isStart ? _startTime = picked : _endTime = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              const Icon(Icons.date_range, color: Color(0xFFE8622A), size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Custom Date Range',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1B3A4B),
                  ),
                ),
              ),
              GestureDetector(
                // Returning `false` tells the caller this sheet was
                // dismissed without applying a range, so the parent
                // can snap the selected tab back to Today.
                onTap: () => Navigator.pop(context, false),
                child: Icon(Icons.close, color: Colors.grey.shade400, size: 22),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _rowLabel('From'),
          const SizedBox(height: 8),
          Row(
            children: [
              _DateTimeChip(
                icon: Icons.calendar_today_outlined,
                label: _formatDate(_startDate),
                onTap: () => _pickDate(true),
              ),
              const SizedBox(width: 8),
              _DateTimeChip(
                icon: Icons.access_time,
                label: _formatTime(_startTime),
                onTap: () => _pickTime(true),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: Divider(color: Colors.grey.shade200)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Icon(
                  Icons.arrow_downward,
                  size: 16,
                  color: Colors.grey.shade400,
                ),
              ),
              Expanded(child: Divider(color: Colors.grey.shade200)),
            ],
          ),
          const SizedBox(height: 12),
          _rowLabel('To'),
          const SizedBox(height: 8),
          Row(
            children: [
              _DateTimeChip(
                icon: Icons.calendar_today_outlined,
                label: _formatDate(_endDate),
                onTap: () => _pickDate(false),
              ),
              const SizedBox(width: 8),
              _DateTimeChip(
                icon: Icons.access_time,
                label: _formatTime(_endTime),
                onTap: () => _pickTime(false),
              ),
            ],
          ),
          if (!_isValid) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.error_outline, size: 14, color: Colors.red),
                SizedBox(width: 4),
                Text(
                  'Start must be before end.',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isValid
                  ? () {
                      // Returning `true` tells the caller a range was
                      // actually applied, so it should NOT snap back to Today.
                      Navigator.pop(context, true);
                      widget.onApply(_fullStart, _fullEnd);
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE8622A),
                disabledBackgroundColor: Colors.grey.shade300,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Apply Range',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowLabel(String text) => Text(
    text,
    style: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade500,
      letterSpacing: 0.5,
    ),
  );
}

// ── Date/time chip ────────────────────────────────────────────────────────────

class _DateTimeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DateTimeChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFE8622A).withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: const Color(0xFFE8622A).withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 14, color: const Color(0xFFE8622A)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1B3A4B),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Chart painter ─────────────────────────────────────────────────────────────

class _TemperatureChartPainter extends CustomPainter {
  final List<Map<String, double>> data;
  final bool isDark;
  // When set, the chart uses this fixed x-axis range (0–24 for a full
  // day) instead of stretching whatever data exists to fill the canvas.
  final double? xDomainMin;
  final double? xDomainMax;
  // When the chart is drawn on a wide, horizontally-scrollable canvas
  // (Today tab), the Y-axis labels would scroll off-screen along with
  // the rest of the canvas. In that case we skip drawing them here and
  // render them separately as a fixed overlay instead.
  final bool showYAxisLabels;
  // When set, x-axis labels show real date + time counted from this
  // start, instead of plain hour-of-day labels (Custom tab).
  final DateTime? rangeStart;
  // The newest N points are drawn as-is (no averaging).
  final int rawTailCount;
  // How many of the newest points get their own dot.
  final int dotTailCount;
  // Neighbouring points further apart than this (hours) break the line.
  final double? gapHours;
  // A broken stretch is drawn only this wide (hours), however long it lasted.
  final double? gapBlankHours;

  _TemperatureChartPainter({
    required this.data,
    this.isDark = false,
    this.xDomainMin,
    this.xDomainMax,
    this.showYAxisLabels = true,
    this.rangeStart,
    this.rawTailCount = 0,
    this.dotTailCount = 0,
    this.gapHours,
    this.gapBlankHours,
  });

  String _rangeLabel(DateTime dt, bool withTime) {
    final d =
        '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}';
    if (!withTime) return d;
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    return '$d $h:$m${dt.hour < 12 ? 'AM' : 'PM'}';
  }

  // Label with minutes, e.g. "2PM" or "2:10PM" (Today chart, 10-min ticks).
  String _timeLabel(double h) {
    final totalMin = (h * 60).round();
    final hour = (totalMin ~/ 60) % 24;
    final min = totalMin % 60;
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return min == 0
        ? '$displayHour$period'
        : '$displayHour:${min.toString().padLeft(2, '0')}$period';
  }

  // Label with seconds, e.g. "4:44:30PM" (fine ticks on the Today chart).
  String _timeLabelSec(double h) {
    final totalSec = (h * 3600).round();
    final hour = (totalSec ~/ 3600) % 24;
    final min = (totalSec % 3600) ~/ 60;
    final sec = totalSec % 60;
    final period = hour < 12 ? 'AM' : 'PM';
    final displayHour = hour % 12 == 0 ? 12 : hour % 12;
    return '$displayHour:${min.toString().padLeft(2, '0')}:'
        '${sec.toString().padLeft(2, '0')}$period';
  }

  // Draws a label slanted about -35 degrees, with its right end at [x],
  // so many close-together labels never overlap.
  void _drawSlantedLabel(
    Canvas canvas,
    String text,
    double x,
    double y,
    TextStyle style,
  ) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(x, y);
    canvas.rotate(-0.61);
    tp.paint(canvas, Offset(-tp.width, 0));
    canvas.restore();
  }

  List<Map<String, double>> _sampleData(
    List<Map<String, double>> src,
    int maxPts,
    String key,
  ) {
    if (src.length <= maxPts) return src;
    final result = <Map<String, double>>[];
    final step = src.length / maxPts;
    for (int i = 0; i < maxPts; i++) {
      final start = (i * step).floor();
      final end = ((i + 1) * step).floor().clamp(0, src.length);
      if (start >= src.length) break;
      final bucket = src.sublist(start, end);
      final avgVal =
          bucket.map((e) => e[key]!).reduce((a, b) => a + b) / bucket.length;
      final avgX =
          bucket.map((e) => e['x']!).reduce((a, b) => a + b) / bucket.length;
      result.add({'x': avgX, key: avgVal});
    }
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const double leftPadding = 40;
    const double bottomPadding = 44;
    const double topPadding = 8;
    const double rightPadding = 8;

    final double chartWidth = size.width - leftPadding - rightPadding;
    final double chartHeight = size.height - bottomPadding - topPadding;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    const double yMin = 0.0;
    const double yMax = 50.0;

    // Gaps (connection lost) found in the raw data.
    final gapTailStart = data.length - rawTailCount.clamp(0, data.length);
    final gaps = gapHours == null
        ? <_Gap>[]
        : _findGaps(data, gap: gapHours!, tailStart: gapTailStart);
    final blank = gapBlankHours ?? gapHours ?? 0.0;
    double mapH(double h) => _compressX(h, gaps, blank);
    bool inGap(double h) =>
        gaps.any((g) => g.end - g.start > blank && h > g.start && h < g.end);
    final double? mappedDomainMax = xDomainMax == null
        ? null
        : mapH(xDomainMax!);

    var sampled = <Map<String, double>>[];
    double getX(double index, int totalPoints) {
      final minX = xDomainMin ?? sampled.first['x']!;
      final span = (mappedDomainMax ?? sampled.last['x']!) - minX;
      if (span <= 0) {
        return leftPadding +
            (index / (totalPoints > 1 ? totalPoints - 1 : 1)) * chartWidth;
      }
      return leftPadding +
          ((mapH(sampled[index.round()]['x']!) - minX) / span) * chartWidth;
    }

    double getY(double temp) =>
        topPadding +
        chartHeight -
        ((temp.clamp(yMin, yMax) - yMin) / (yMax - yMin)) * chartHeight;

    final gridPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.04)
          : Colors.grey.shade100
      ..strokeWidth = 0.8;

    for (final step in [5, 10, 15, 20, 25, 30, 35, 40, 45]) {
      final y = getY(step.toDouble());
      canvas.drawLine(
        Offset(leftPadding, y),
        Offset(size.width - rightPadding, y),
        gridPaint,
      );
    }

    final baselinePaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.grey.shade300
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(leftPadding, topPadding + chartHeight),
      Offset(size.width - rightPadding, topPadding + chartHeight),
      baselinePaint,
    );

    if (showYAxisLabels) {
      final labelStyle = TextStyle(
        color: isDark ? Colors.white54 : Colors.grey.shade500,
        fontSize: 10,
      );
      for (final v in [0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50]) {
        final tp = TextPainter(
          text: TextSpan(text: '$v°C', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(
          canvas,
          Offset(
            leftPadding - 6 - tp.width,
            getY(v.toDouble()) - tp.height / 2,
          ),
        );
      }
    }

    if (xDomainMin != null && xDomainMax != null) {
      final double domainMin = xDomainMin!;
      final double domainMax = xDomainMax!;
      final double domainSpan = mapH(domainMax) - domainMin;
      if (domainSpan > 0) {
        final vGridPaint = Paint()
          ..color = isDark
              ? Colors.white.withValues(alpha: 0.05)
              : Colors.grey.shade100
          ..strokeWidth = 0.8;
        final hourLabelStyle = TextStyle(
          color: isDark ? Colors.white38 : Colors.grey.shade400,
          fontSize: 9,
        );
        if (rangeStart == null) {
          final pxPerHourToday = chartWidth / domainSpan;
          final bool liveMode = pxPerHourToday >= 8000;

          // Whole-day grid: hourly when the canvas is very wide.
          final double stepH = liveMode
              ? 1.0
              : (pxPerHourToday >= 400 ? 1.0 : 3.0);
          for (double h = domainMin; h <= domainMax + 1e-9; h += stepH) {
            if (inGap(h)) continue;
            final x =
                leftPadding + ((mapH(h) - domainMin) / domainSpan) * chartWidth;
            canvas.drawLine(
              Offset(x, topPadding),
              Offset(x, topPadding + chartHeight),
              vGridPaint,
            );
            if (liveMode) {
              // Slanted like the per-reading labels. Skipped inside the
              // last hour, where the 10-second labels take over.
              final hasTail = rawTailCount > 0 && data.isNotEmpty;
              final tailFromX = hasTail
                  ? data[(data.length - rawTailCount).clamp(
                      0,
                      data.length - 1,
                    )]['x']!
                  : 0.0;
              final tailToX = hasTail ? data.last['x']! : -1.0;
              final insideTail =
                  hasTail && h >= tailFromX - 0.002 && h <= tailToX + 0.002;
              if (!insideTail) {
                _drawSlantedLabel(
                  canvas,
                  _timeLabel(h),
                  x,
                  topPadding + chartHeight + 3,
                  hourLabelStyle,
                );
              }
            } else {
              final tp = TextPainter(
                text: TextSpan(text: _timeLabel(h), style: hourLabelStyle),
                textDirection: TextDirection.ltr,
              )..layout();
              final labelX = (x - tp.width / 2).clamp(
                0.0,
                size.width - tp.width,
              );
              tp.paint(canvas, Offset(labelX, topPadding + chartHeight + 2));
            }
          }
        } else {
          // Custom / Week / Month: unchanged behavior.
          int hourStep = 3;
          final pxPerHour = chartWidth / domainSpan;
          const steps = [1, 2, 3, 6, 12, 24, 48, 72, 168];
          hourStep = steps.firstWhere(
            (s) => s * pxPerHour >= 90,
            orElse: () => 336,
          );
          for (
            int h = domainMin.round();
            h <= domainMax.floor();
            h += hourStep
          ) {
            if (inGap(h.toDouble())) continue;
            final x =
                leftPadding +
                ((mapH(h.toDouble()) - domainMin) / domainSpan) * chartWidth;
            canvas.drawLine(
              Offset(x, topPadding),
              Offset(x, topPadding + chartHeight),
              vGridPaint,
            );
            final label = _rangeLabel(
              rangeStart!.add(Duration(hours: h)),
              hourStep < 24,
            );
            final tp = TextPainter(
              text: TextSpan(text: label, style: hourLabelStyle),
              textDirection: TextDirection.ltr,
            )..layout();
            double labelX = (x - tp.width / 2).clamp(
              0.0,
              size.width - tp.width,
            );
            tp.paint(canvas, Offset(labelX, topPadding + chartHeight + 2));
          }
        }
      }
    }

    if (data.length < 2) return;

    // Roughly one point per 4px of chart width keeps the line smooth.
    final targetPoints = rangeStart != null
        ? 1200 // Week/Month/Custom already hold at most 300 points
        : (chartWidth / 4).clamp(20, 1200).toInt();
    final tail = rawTailCount.clamp(0, data.length);
    final tailStart = data.length - tail;

    // Split the data into segments wherever there is a gap.
    final gapNew = gapHours ?? double.infinity;
    final gapOld = gapHours == null
        ? double.infinity
        : (gapNew > 45 / 3600.0 ? gapNew : 45 / 3600.0);
    final segments = <List<Map<String, double>>>[];
    var currentSeg = <Map<String, double>>[data.first];
    for (int i = 1; i < data.length; i++) {
      final limit = i >= tailStart ? gapNew : gapOld;
      if (data[i]['x']! - data[i - 1]['x']! > limit) {
        segments.add(currentSeg);
        currentSeg = <Map<String, double>>[];
      }
      currentSeg.add(data[i]);
    }
    segments.add(currentSeg);

    // Sample each segment on its own and remember where each one starts.
    sampled = <Map<String, double>>[];
    final segmentStarts = <int>{};
    int offset = 0;
    for (final seg in segments) {
      final tailFrom = (tailStart - offset).clamp(0, seg.length);
      final segHead = seg.sublist(0, tailFrom);
      final segTail = seg.sublist(tailFrom);
      final t = (targetPoints * seg.length / data.length).round();
      final segTarget = t < 2 ? 2 : t;

      segmentStarts.add(sampled.length);
      sampled.addAll([..._sampleData(segHead, segTarget, 'temp'), ...segTail]);
      offset += seg.length;
    }
    final totalPoints = sampled.length;

    final fillPath = Path();
    final linePath = Path();
    final baseY = topPadding + chartHeight;

    void closeFill(int lastIndex) {
      fillPath.lineTo(getX(lastIndex.toDouble(), totalPoints), baseY);
      fillPath.close();
    }

    for (int i = 0; i < sampled.length; i++) {
      final x = getX(i.toDouble(), totalPoints);
      final y = getY(sampled[i]['temp']!);
      if (x.isNaN || y.isNaN) continue;

      if (segmentStarts.contains(i)) {
        // New segment: close the previous area and start fresh, so
        // nothing is drawn across the gap.
        if (i > 0) closeFill(i - 1);
        fillPath.moveTo(x, baseY);
        fillPath.lineTo(x, y);
        linePath.moveTo(x, y);
      } else {
        fillPath.lineTo(x, y);
        linePath.lineTo(x, y);
      }
    }
    closeFill(sampled.length - 1);

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader =
            LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF4CAF50).withValues(alpha: 0.85),
                const Color(0xFF4CAF50).withValues(alpha: 0.15),
              ],
            ).createShader(
              Rect.fromLTWH(leftPadding, topPadding, chartWidth, chartHeight),
            )
        ..style = PaintingStyle.fill,
    );

    final lineColor = isDark
        ? const Color(0xFF66BB6A)
        : const Color(0xFF2E7D32);

    if (rangeStart != null && sampled.isNotEmpty) {
      final bandPaint = Paint()
        ..color = lineColor.withValues(alpha: 0.2)
        ..style = PaintingStyle.fill;
      int s = 0;
      while (s < sampled.length) {
        int e = s + 1;
        while (e < sampled.length && !segmentStarts.contains(e)) {
          e++;
        }
        final band = Path();
        for (int i = s; i < e; i++) {
          final bx = getX(i.toDouble(), totalPoints);
          final by = getY(sampled[i]['max'] ?? sampled[i]['temp']!);
          if (i == s) {
            band.moveTo(bx, by);
          } else {
            band.lineTo(bx, by);
          }
        }
        for (int i = e - 1; i >= s; i--) {
          band.lineTo(
            getX(i.toDouble(), totalPoints),
            getY(sampled[i]['min'] ?? sampled[i]['temp']!),
          );
        }
        band.close();
        canvas.drawPath(band, bandPaint);
        s = e;
      }
    }

    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.4
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

    // Dots: show every point when there are few of them; otherwise show
    // only a single highlighted "latest reading" marker to avoid clutter.
    final dotOuterPaint = Paint()..color = lineColor;
    final dotInnerPaint = Paint()..color = Colors.white;

    // Recent raw readings shown on the Today graph.
    final dots = dotTailCount.clamp(0, tail);

    // Draw a time label below EVERY recent 10-second reading.
    final readingLabelStyle = TextStyle(
      color: isDark ? Colors.white54 : Colors.grey.shade500,
      fontSize: 9,
    );

    if (dots > 0) {
      for (int i = sampled.length - dots; i < sampled.length; i++) {
        final tx = getX(i.toDouble(), totalPoints);
        if (tx.isNaN) continue;

        canvas.drawLine(
          Offset(tx, topPadding + chartHeight),
          Offset(tx, topPadding + chartHeight + 3),
          baselinePaint,
        );

        _drawSlantedLabel(
          canvas,
          _timeLabelSec(sampled[i]['x']!),
          tx,
          topPadding + chartHeight + 3,
          readingLabelStyle,
        );
      }
    }

    // Draw the dots.
    if (sampled.length <= 20) {
      for (int i = 0; i < sampled.length; i++) {
        final dx = getX(i.toDouble(), totalPoints);
        final dy = getY(sampled[i]['temp']!);

        if (dx.isNaN || dy.isNaN) continue;

        canvas.drawCircle(Offset(dx, dy), 3.0, dotOuterPaint);

        canvas.drawCircle(Offset(dx, dy), 1.4, dotInnerPaint);
      }
    } else {
      for (int i = sampled.length - dots; i < sampled.length - 1; i++) {
        final ddx = getX(i.toDouble(), totalPoints);
        final ddy = getY(sampled[i]['temp']!);

        if (ddx.isNaN || ddy.isNaN) continue;

        canvas.drawCircle(Offset(ddx, ddy), 4.0, dotOuterPaint);

        canvas.drawCircle(Offset(ddx, ddy), 1.9, dotInnerPaint);
      }

      // Highlight newest reading.
      final lastIdx = sampled.length - 1;
      final dx = getX(lastIdx.toDouble(), totalPoints);
      final dy = getY(sampled[lastIdx]['temp']!);

      if (!dx.isNaN && !dy.isNaN) {
        canvas.drawCircle(
          Offset(dx, dy),
          11.0,
          Paint()..color = lineColor.withValues(alpha: 0.2),
        );

        canvas.drawCircle(Offset(dx, dy), 6.5, dotOuterPaint);

        canvas.drawCircle(Offset(dx, dy), 3.0, dotInnerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TemperatureChartPainter old) => true;
}
