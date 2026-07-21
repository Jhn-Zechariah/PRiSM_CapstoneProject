import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import '../../../../core/services/ml_service.dart';
import '../../../../core/widgets/build_tab_bar.dart';
import 'package:prism_app/features/dashboard/presentation/pages/Dashboard_Screen.dart';

const List<String> kHumidityTimeRanges = [
  'This Month',
  'This Week',
  'Today',
  'Custom',
];

String _humFormatDateTime(DateTime dt) {
  final d = dt.day.toString().padLeft(2, '0');
  final m = dt.month.toString().padLeft(2, '0');
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final min = dt.minute.toString().padLeft(2, '0');
  final p = dt.hour < 12 ? 'AM' : 'PM';
  return '$d/$m/${dt.year}  $h:$min $p';
}

String _humFormatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

String _humFormatTime(TimeOfDay t) {
  final h = t.hour == 0
      ? 12
      : t.hour > 12
      ? t.hour - 12
      : t.hour;
  final min = t.minute.toString().padLeft(2, '0');
  final p = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '${h.toString().padLeft(2, '0')}:$min $p';
}

DateTimeRange? _humResolveTimeRange(
  int index,
  DateTime? customStart,
  DateTime? customEnd,
) {
  final now = DateTime.now();
  switch (index) {
    case 0:
      return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
    case 1:
      final ws = now.subtract(Duration(days: now.weekday - 1));
      return DateTimeRange(
        start: DateTime(ws.year, ws.month, ws.day),
        end: now,
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

// ── Humidity Monitoring ───────────────────────────────────────────────────────

class HumidityMonitoring extends StatefulWidget {
  final VoidCallback? onSwitchToTemperature;
  final ValueChanged<double>? onMaxHumidityChanged;

  const HumidityMonitoring({
    super.key,
    this.onSwitchToTemperature,
    this.onMaxHumidityChanged,
  });

  @override
  State<HumidityMonitoring> createState() => _HumidityMonitoringState();
}

class _HumidityMonitoringState extends State<HumidityMonitoring> {
  //ml part
  String? _mlInsight;
  String? _mlRecommendation;
  String? _mlCondition;
  bool _mlInsightLoading = false;
  DateTime? _lastMlFetch; // ← add this

  int _selectedTab = 1;
  int _selectedTimeRange = 2;
  bool _isSprinklerLoading = false;

  bool _isLoading =
      !SensorMemory.humidityChartLoaded ||
      SensorMemory.lastHumidityChartDate != SensorMemory.todayKey();

  String _connectionStatus = LiveSensorService.connectionStatus.value;
  String _sensorStatus = LiveSensorService.sensorStatus.value;

  Timer? _durationTimer;
  DateTime? _sprinklerActivatedAt;

  double? _currentHumidity;
  DateTime? _lastAppliedTimestamp;

  // Granularity toggle for the Today AND Custom tabs: 0 = Hour (existing
  // hourly docs), 1 = Minute (live buffer for Today, a one-off range query
  // for Custom).
  int _todayGranularity = 0;
  final List<Map<String, double>> _minuteBufferToday = [];
  String _minuteBufferDayKey = '';
  bool _minuteChartLoading = false;
  // Tracks which day we've pulled persisted humidity_minute history for —
  // deliberately separate from _minuteBufferDayKey, which gets stamped by
  // live data arriving in the background (via _appendMinuteBufferPoint)
  // before the user ever opens the Minute tab. Reusing that field as the
  // "already loaded" guard meant the Firestore fetch below was skipped
  // every time, because live data had already set it first.
  String _minuteHistoryLoadedDayKey = '';

  // Minute-level data for the Custom range tab — kept separate from
  // _minuteBufferToday since it covers an arbitrary user-picked range
  // instead of "today", and isn't fed by live readings.
  final List<Map<String, double>> _minuteBufferCustom = [];
  String _minuteCustomRangeKey = '';
  bool _minuteCustomLoading = false;

  static bool _humidityCacheIsToday() =>
      SensorMemory.lastHumidityChartDate == SensorMemory.todayKey();

  double? _displayMax = _humidityCacheIsToday()
      ? SensorMemory.lastHumidityDisplayMax
      : null;
  double? _displayAvg = _humidityCacheIsToday()
      ? SensorMemory.lastHumidityDisplayAvg
      : null;
  double? _displayMin = _humidityCacheIsToday()
      ? SensorMemory.lastHumidityDisplayMin
      : null;

  // Per-session cache for This Week (index 1) and This Month (index 0).
  static List<Map<String, double>> _cachedWeekData = [];
  static double? _cachedWeekMax;
  static double? _cachedWeekMin;
  static double? _cachedWeekAvg;
  static String _cachedWeekHourKey = '';

  static List<Map<String, double>> _cachedMonthData = [];
  static double? _cachedMonthMax;
  static double? _cachedMonthMin;
  static double? _cachedMonthAvg;
  static String _cachedMonthHourKey = '';

  String get _humidityStatus {
    if (_currentHumidity == null) return "";
    final h = _currentHumidity!;
    if (h > 70) return "High";
    if (h < 60) return "Low";
    return "Normal";
  }

  final List<Map<String, double>> _chartData = _humidityCacheIsToday()
      ? List.of(SensorMemory.lastHumidityChartData)
      : [];

  List<Map<String, double>> get _activeChartData {
    if (_todayGranularity != 1) return _chartData;
    if (_selectedTimeRange == 2) return _minuteBufferToday;
    return _minuteBufferCustom; // Month, Week, or Custom
  }

  bool get _isMinuteViewActive => _todayGranularity == 1;

  // Stat cards recompute from the raw minute-level buffer when Minute view
  // is selected, instead of always showing the hourly rollup — otherwise
  // switching to Minute only changed the line chart while Highest/Lowest/
  // Average kept showing the coarser hourly-based numbers.
  double? get _activeDisplayMax {
    if (!_isMinuteViewActive) return _displayMax;
    if (_activeChartData.isEmpty) return null;
    return _activeChartData
        .map((p) => p['humidity']!)
        .reduce((a, b) => a > b ? a : b);
  }

  double? get _activeDisplayMin {
    if (!_isMinuteViewActive) return _displayMin;
    if (_activeChartData.isEmpty) return null;
    return _activeChartData
        .map((p) => p['humidity']!)
        .reduce((a, b) => a < b ? a : b);
  }

  double? get _activeDisplayAvg {
    if (!_isMinuteViewActive) return _displayAvg;
    if (_activeChartData.isEmpty) return null;
    final values = _activeChartData.map((p) => p['humidity']!);
    return values.reduce((a, b) => a + b) / _activeChartData.length;
  }

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DateTime? _customStart;
  DateTime? _customEnd;
  Timer? _hourlyRefreshTimer;

  @override
  void initState() {
    super.initState();
    _initData();
    _loadSprinklerState();
    humidityMaxTodayNotifier.addListener(_onHumidityMaxNotifierChanged);
    LiveSensorService.latestData.addListener(_onLiveDataChanged);
    LiveSensorService.connectionStatus.addListener(_onSharedStatusChanged);
    LiveSensorService.sensorStatus.addListener(_onSharedStatusChanged);
    _hourlyRefreshTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _loadChartFromFirestore();
      if (_todayGranularity == 1 && _selectedTimeRange != 2) {
        _loadMinuteChartForRange(_selectedTimeRange);
      }
    });
  }

  void _onSharedStatusChanged() {
    if (!mounted) return;
    setState(() {
      _connectionStatus = LiveSensorService.connectionStatus.value;
      _sensorStatus = LiveSensorService.sensorStatus.value;
      if (_sensorStatus == "Sensor Offline") _currentHumidity = null;
    });
  }

  void _appendMinuteBufferPoint(double hum, DateTime ts) {
    final todayKey = SensorMemory.todayKey();
    if (_minuteBufferDayKey != todayKey) {
      _minuteBufferToday.clear();
      _minuteBufferDayKey = todayKey;
    }
    final midnight = DateTime(ts.year, ts.month, ts.day);
    final hoursFromMidnight = ts.difference(midnight).inSeconds / 3600.0;

    if (_minuteBufferToday.isNotEmpty) {
      final lastX = _minuteBufferToday.last['x']!;
      if ((hoursFromMidnight - lastX) < (1 / 60.0) * 0.9) return; // same minute, skip
    }
    _minuteBufferToday.add({'x': hoursFromMidnight, 'humidity': hum});
    if (_minuteBufferToday.length > 1440) {
      _minuteBufferToday.removeAt(0); // cap at 24h of minute points
    }
  }

  // Loads today's persisted per-minute readings from the ESP32's
  // humidity_minute collection so the Minute view has real history
  // instead of only whatever arrived live while this screen happened to
  // be open. Runs once per day (guarded by _minuteBufferDayKey) — after
  // that, _appendMinuteBufferPoint keeps it current as live data arrives.
  Future<void> _loadMinuteChartFromFirestore() async {
    final todayKey = SensorMemory.todayKey();
    if (_minuteHistoryLoadedDayKey == todayKey) {
      return;
    }
    if (_minuteChartLoading) return;
    _minuteChartLoading = true;

    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    try {
      final snapshot = await _db
          .collection('humidity_minute')
          .orderBy('timestamp', descending: false)
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(midnight),
          )
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(now))
          .limit(1500)
          .get();

      if (!mounted) return;

      debugPrint(
        '[MinuteChart/humidity] query range ${midnight.toIso8601String()} .. '
        '${now.toIso8601String()}, got ${snapshot.docs.length} docs',
      );

      final points = <Map<String, double>>[];
      int skippedNoHum = 0;
      int skippedNoTs = 0;
      for (final doc in snapshot.docs) {
        final d = doc.data();
        final rawHum = d['humidity'];
        final ts = (d['timestamp'] as Timestamp?)?.toDate();
        if (rawHum == null) {
          skippedNoHum++;
          continue;
        }
        if (ts == null) {
          skippedNoTs++;
          continue;
        }
        final hoursFromMidnight = ts.difference(midnight).inSeconds / 3600.0;
        points.add({
          'x': hoursFromMidnight,
          'humidity': (rawHum as num).toDouble(),
        });
      }
      debugPrint(
        '[MinuteChart/humidity] usable points=${points.length}, '
        'skippedNoHum=$skippedNoHum, skippedNoTs=$skippedNoTs',
      );

      setState(() {
        // Merge with whatever is already buffered instead of overwriting —
        // if the ESP32 hasn't written any humidity_minute docs yet today
        // (not reflashed, or hasn't hit the 60s mark), the Firestore query
        // legitimately returns nothing. Blowing away the points already
        // accumulated from live data in that case would leave too few
        // points to draw a visible line, making the chart look empty.
        final byMinute = <int, Map<String, double>>{};
        for (final p in _minuteBufferToday) {
          byMinute[(p['x']! * 60).round()] = p;
        }
        for (final p in points) {
          byMinute[(p['x']! * 60).round()] = p;
        }
        final sortedKeys = byMinute.keys.toList()..sort();

        _minuteBufferToday
          ..clear()
          ..addAll([for (final k in sortedKeys) byMinute[k]!]);
        _minuteBufferDayKey = todayKey;
        _minuteHistoryLoadedDayKey = todayKey;

        // Fold in the most recent live reading too, in case it's newer
        // than the last persisted minute doc.
        final live = LiveSensorService.latestData.value;
        final liveHum = (live?['humidity'] as num?)?.toDouble();
        if (liveHum != null && liveHum >= 0) {
          _appendMinuteBufferPoint(
            liveHum,
            _lastAppliedTimestamp ?? DateTime.now(),
          );
        }
      });
    } catch (e) {
      // Leave whatever was already buffered in place on failure.
      debugPrint('[MinuteChart/humidity] query failed: $e');
    } finally {
      _minuteChartLoading = false;
    }
  }

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
    final range = _humResolveTimeRange(rangeIndex, _customStart, _customEnd);
    if (range == null) return;
    final rangeKey = '$rangeIndex-${currentHourKey()}';
    if (_minuteCustomRangeKey == rangeKey) return;
    if (_minuteCustomLoading) return;
    _minuteCustomLoading = true;

    final start = range.start;
    final end = range.end;

    try {
      final snapshot = await _db
          .collection('humidity_minute')
          .orderBy('timestamp', descending: true)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('timestamp', isLessThanOrEqualTo: Timestamp.fromDate(end))
          .limit(1500)
          .get();

      if (!mounted || _selectedTimeRange != rangeIndex) return;

      final points = <Map<String, double>>[];
      for (final doc in snapshot.docs.reversed) {
        final d = doc.data();
        final rawHum = d['humidity'];
        final ts = (d['timestamp'] as Timestamp?)?.toDate();
        if (rawHum == null || ts == null) continue;
        final hoursFromStart = ts.difference(start).inSeconds / 3600.0;
        points.add({'x': hoursFromStart, 'humidity': (rawHum as num).toDouble()});
      }

      setState(() {
        _minuteBufferCustom
          ..clear()
          ..addAll(points);
        _minuteCustomRangeKey = rangeKey;
      });
    } catch (e) {
      debugPrint('[MinuteChart/humidity range] query failed: $e');
    } finally {
      _minuteCustomLoading = false;
    }
  }

  void _onLiveDataChanged() {
    if (!mounted) return;
    final data = LiveSensorService.latestData.value;
    if (data == null) return;

    final humLive = (data['humidity'] as num?)?.toDouble();
    if (humLive == null || humLive < 0) return;

    final tempLive = (data['temperature'] as num?)?.toDouble() ??
        (data['tempAvg'] as num?)?.toDouble();

    if (_lastAppliedTimestamp != null) {
      final tsField = data['timestamp'];
      DateTime? ts;
      if (tsField is String) {
        ts = DateTime.tryParse(tsField);
      } else if (tsField is Timestamp) {
        ts = tsField.toDate();
      }
      if (ts != null && !ts.isAfter(_lastAppliedTimestamp!)) return;
      _lastAppliedTimestamp = ts;
    } else {
      final tsField = data['timestamp'];
      if (tsField is String) {
        _lastAppliedTimestamp = DateTime.tryParse(tsField);
      } else if (tsField is Timestamp) {
        _lastAppliedTimestamp = tsField.toDate();
      }
    }

    final tsForBuffer = _lastAppliedTimestamp ?? DateTime.now();
    setState(() {
      _currentHumidity = humLive;
      _isLoading = false;
      _appendMinuteBufferPoint(humLive, tsForBuffer);
    });
    final now = DateTime.now();
    if (_lastMlFetch == null ||
        now.difference(_lastMlFetch!) > const Duration(minutes: 1)) {
      _lastMlFetch = now;
      _fetchHumidityMLInsight(humLive, tempLive!);
    }
  }

  void _onHumidityMaxNotifierChanged() {
    if (!mounted) return;
    final v = humidityMaxTodayNotifier.value;
    if (v > 0 && _selectedTimeRange == 2) {
      widget.onMaxHumidityChanged?.call(v);
    }
  }

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
      SprinklerMemory.duration = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
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
    await _loadChartFromFirestore();
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (LiveSensorService.latestData.value != null) {
      _onLiveDataChanged();
    }
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _hourlyRefreshTimer?.cancel();
    humidityMaxTodayNotifier.removeListener(_onHumidityMaxNotifierChanged);
    LiveSensorService.latestData.removeListener(_onLiveDataChanged);
    LiveSensorService.connectionStatus.removeListener(_onSharedStatusChanged);
    LiveSensorService.sensorStatus.removeListener(_onSharedStatusChanged);
    super.dispose();
  }



  void _clearStatsForRangeSwitch() {
    _chartData.clear();
    _displayMax = null;
    _displayMin = null;
    _displayAvg = null;
    _minuteBufferCustom.clear();
    _minuteCustomRangeKey = '';
  }

  Future<void> _loadChartFromFirestore() async {
    final rangeIndexAtLoad = _selectedTimeRange;

    final range = _humResolveTimeRange(
      rangeIndexAtLoad,
      _customStart,
      _customEnd,
    );
    if (range == null) return;

    final today = SensorMemory.todayKey();
    final hourKey = currentHourKey();

    // Today: cache hit if we've already loaded for this hour.
    if (rangeIndexAtLoad == 2 &&
        SensorMemory.lastHumidityChartHourKey == hourKey &&
        SensorMemory.lastHumidityChartDate == today &&
        SensorMemory.humidityChartLoaded) {
      if (mounted) {
        setState(() {
          _chartData
            ..clear()
            ..addAll(SensorMemory.lastHumidityChartData);
          _displayMax = SensorMemory.lastHumidityDisplayMax;
          _displayMin = SensorMemory.lastHumidityDisplayMin;
          _displayAvg = SensorMemory.lastHumidityDisplayAvg;
        });
      }
      return;
    }

    // Week/Month: cache hit if loaded within this same hour.
    if (rangeIndexAtLoad == 1 &&
        _cachedWeekHourKey == hourKey &&
        _cachedWeekData.isNotEmpty) {
      if (mounted) {
        setState(() {
          _chartData
            ..clear()
            ..addAll(_cachedWeekData);
          _displayMax = _cachedWeekMax;
          _displayMin = _cachedWeekMin;
          _displayAvg = _cachedWeekAvg;
        });
      }
      return;
    }
    if (rangeIndexAtLoad == 0 &&
        _cachedMonthHourKey == hourKey &&
        _cachedMonthData.isNotEmpty) {
      if (mounted) {
        setState(() {
          _chartData
            ..clear()
            ..addAll(_cachedMonthData);
          _displayMax = _cachedMonthMax;
          _displayMin = _cachedMonthMin;
          _displayAvg = _cachedMonthAvg;
        });
      }
      return;
    }

    try {
      final snapshot = await _db
          .collection('humidity_hourly')
          .orderBy('timestamp', descending: false)
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
          )
          .where(
            'timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(range.end),
          )
          .limit(800)
          .get();

      if (!mounted || _selectedTimeRange != rangeIndexAtLoad) return;

      final docs = snapshot.docs;
      if (docs.isEmpty) {
        setState(() {
          _chartData.clear();
          _displayMax = null;
          _displayAvg = null;
          _displayMin = null;
        });
        if (rangeIndexAtLoad == 2) {
          SensorMemory.lastHumidityChartData = [];
          SensorMemory.humidityChartLoaded = true;
          SensorMemory.lastHumidityChartDate = today;
          SensorMemory.lastHumidityChartHourKey = hourKey;
          SensorMemory.lastHumidityDisplayMax = null;
          SensorMemory.lastHumidityDisplayMin = null;
          SensorMemory.lastHumidityDisplayAvg = null;
        }
        return;
      }

      // Roll up across EVERY hourly doc gathered in the range:
      //   Highest = max of all hourly humidityMax values
      //   Lowest  = min of all hourly humidityMin values
      //   Average = simple (equal-weight) mean of all hourly humidityAvg values
      // A doc that is missing humidityMin/humidityAvg is excluded from that
      // particular stat instead of being faked from humidityMax, so a single
      // incomplete doc can't silently drag Lowest/Average toward Highest.
      final allData = <Map<String, double>>[];
      final allMaxValues = <double>[];
      final allMinValues = <double>[];
      final allAvgValues = <double>[];

      for (final doc in docs) {
        final d = doc.data();
        final rawMax = d['humidityMax'];
        if (rawMax == null) continue;

        final max = (rawMax as num).toDouble();
        final rawMin = d['humidityMin'];
        final rawAvg = d['humidityAvg'];

        final docTs = (d['timestamp'] as Timestamp?)?.toDate();
        if (docTs != null) {
          final x = docTs.difference(range.start).inMinutes / 60.0;
          allData.add({'x': x, 'humidity': max});
        }

        allMaxValues.add(max);
        if (rawMin != null) allMinValues.add((rawMin as num).toDouble());
        if (rawAvg != null) allAvgValues.add((rawAvg as num).toDouble());
      }

      if (allMaxValues.isEmpty) {
        setState(() {
          _chartData.clear();
          _displayMax = null;
          _displayAvg = null;
          _displayMin = null;
        });
        return;
      }

      final historicalMax = allMaxValues.reduce((a, b) => a > b ? a : b);
      final historicalMin = allMinValues.isNotEmpty
          ? allMinValues.reduce((a, b) => a < b ? a : b)
          : null;
      final historicalAvg = allAvgValues.isNotEmpty
          ? allAvgValues.reduce((a, b) => a + b) / allAvgValues.length
          : null;

      if (!mounted || _selectedTimeRange != rangeIndexAtLoad) return;

      setState(() {
        _chartData
          ..clear()
          ..addAll(allData);
        _displayMax = historicalMax;
        _displayMin = historicalMin;
        _displayAvg = historicalAvg;

        if (rangeIndexAtLoad == 2) {
          SensorMemory.resetIfNewDay();
          if (historicalMax > SensorMemory.lastHumidityMaxToday) {
            SensorMemory.setHumidityMaxToday(historicalMax);
          }
          widget.onMaxHumidityChanged?.call(historicalMax);
        }
      });

      // Persist Today cache.
      if (rangeIndexAtLoad == 2) {
        SensorMemory.lastHumidityChartData = List.of(_chartData);
        SensorMemory.humidityChartLoaded = true;
        SensorMemory.lastHumidityChartDate = today;
        SensorMemory.lastHumidityChartHourKey = hourKey;
        SensorMemory.lastHumidityDisplayMax = _displayMax;
        SensorMemory.lastHumidityDisplayMin = _displayMin;
        SensorMemory.lastHumidityDisplayAvg = _displayAvg;
        SensorMemory.save();
      }
      // Persist Week/Month session cache.
      if (rangeIndexAtLoad == 1) {
        _cachedWeekData = List.of(_chartData);
        _cachedWeekMax = historicalMax;
        _cachedWeekMin = historicalMin;
        _cachedWeekAvg = historicalAvg;
        _cachedWeekHourKey = hourKey;
      } else if (rangeIndexAtLoad == 0) {
        _cachedMonthData = List.of(_chartData);
        _cachedMonthMax = historicalMax;
        _cachedMonthMin = historicalMin;
        _cachedMonthAvg = historicalAvg;
        _cachedMonthHourKey = hourKey;
      }
    } catch (e) {
      debugPrint('Firestore load error: $e');
      return;
    }
  }

  // ── Sprinkler ───────────────────────────────────────────────────────────────

  Future<void> _toggleSprinkler(bool turnOn) async {
    setState(() => _isSprinklerLoading = true);
    try {
      await FirebaseFirestore.instance
          .collection('sprinkler_command')
          .doc('pending')
          .set({'state': turnOn ? 'on' : 'off'});

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
      builder: (_) => _HumidityCustomRangeSheet(
        initialStart: _customStart,
        initialEnd: _customEnd,
        initialGranularity: _todayGranularity,
        onApply: (start, end, granularity) {
          setState(() {
            _customStart = start;
            _customEnd = end;
            _selectedTimeRange = 3;
            _todayGranularity = granularity;
            _clearStatsForRangeSwitch();
          });
          _loadChartFromFirestore();
          if (_todayGranularity == 1) _loadMinuteChartForRange(3);
        },
      ),
    );

    if (!mounted) return;

    // If the sheet was dismissed (X button, back gesture, or tap outside)
    // without the user ever applying a range, don't leave the UI parked
    // on an empty Custom tab — fall back to Today.
    final wasApplied = applied == true;
    if (!wasApplied && _customStart == null) {
      setState(() {
        _selectedTimeRange = 2;
        _clearStatsForRangeSwitch();
      });
      _loadChartFromFirestore();
      if (_todayGranularity == 1) _loadMinuteChartFromFirestore();
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
                    if (index == 0) widget.onSwitchToTemperature?.call();
                  },
                ),
                const SizedBox(height: 16),
                _buildStatusCard(isDark),
                const SizedBox(height: 12),
                _buildTimeRangeSelector(isDark),
                if (_selectedTimeRange != 3 ||
                    (_customStart != null && _customEnd != null)) ...[
                  const SizedBox(height: 8),
                  _buildGranularityToggle(isDark),
                ],
                if (_selectedTimeRange == 3 &&
                    _customStart != null &&
                    _customEnd != null) ...[
                  const SizedBox(height: 8),
                  _buildCustomRangeBanner(),
                ],
                const SizedBox(height: 16),
                _buildChart(isDark),
                const SizedBox(height: 16),
                _buildHumidityReview(isDark),
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
            Icon(Icons.water_drop_outlined, size: 32, color: color),
            const SizedBox(width: 12),
            Text(
              'Humidity',
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
    final humLabel = _currentHumidity != null
        ? '${_currentHumidity!.toStringAsFixed(1)}%'
        : '--';
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
                _humidityStatus,
                style: TextStyle(color: _textSecondary(isDark), fontSize: 13),
              ),
              const SizedBox(height: 4),
              _isLoading
                  ? const CircularProgressIndicator()
                  : Text(
                      humLabel,
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: (_currentHumidity ?? 0) > 70
                            ? Colors.red
                            : (_currentHumidity ?? 100) < 60
                            ? Colors.orange
                            : _textPrimary(isDark),
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
      children: List.generate(kHumidityTimeRanges.length, (index) {
        final isSelected = _selectedTimeRange == index;
        final isCustom = index == 3;
        return Expanded(
          child: GestureDetector(
            onTap: () async {
              setState(() {
                _selectedTimeRange = index;
                _clearStatsForRangeSwitch();
              });
              if (isCustom) {
                await _showCustomRangePicker();
              } else {
                _loadChartFromFirestore();
                if (_todayGranularity == 1) {
                  if (index == 2) {
                    _loadMinuteChartFromFirestore();
                  } else {
                    _loadMinuteChartForRange(index);
                  }
                }
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(
                right: index < kHumidityTimeRanges.length - 1 ? 6 : 0,
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
                    kHumidityTimeRanges[index],
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

  Widget _buildGranularityToggle(bool isDark) {
    const options = ['Hour', 'Minute'];
    return Row(
      children: [
        Text(
          'Show:',
          style: TextStyle(fontSize: 11, color: _textSecondary(isDark)),
        ),
        const SizedBox(width: 8),
        ...List.generate(options.length, (index) {
          final isSelected = _todayGranularity == index;
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: GestureDetector(
              onTap: () {
                setState(() => _todayGranularity = index);
                if (index == 1) {
                  if (_selectedTimeRange == 2) {
                    _loadMinuteChartFromFirestore();
                  } else {
                    _loadMinuteChartForRange(_selectedTimeRange);
                  }
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1B3A4B) : _cardBg(isDark),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF1B3A4B)
                        : _dividerColor(isDark),
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  options[index],
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.white : _textSecondary(isDark),
                  ),
                ),
              ),
            ),
          );
        }),
      ],
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
              '${_humFormatDateTime(_customStart!)}  →  ${_humFormatDateTime(_customEnd!)}',
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
              _loadChartFromFirestore();
              if (_todayGranularity == 1) _loadMinuteChartFromFirestore();
            },
            child: const Icon(Icons.close, size: 14, color: Color(0xFFE8622A)),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(bool isDark) {
    final range = _humResolveTimeRange(
      _selectedTimeRange,
      _customStart,
      _customEnd,
    );
    final now = DateTime.now();
    return Container(
      decoration: _bentoCard(isDark, accentColor: const Color(0xFFEF5350)),
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: 210,
        width: double.infinity,
        child: (_isLoading || (_selectedTimeRange != 2 && _todayGranularity == 1 && _minuteCustomLoading))
            ? const Center(child: CircularProgressIndicator())
            : _activeChartData.isEmpty
            ? Center(
                child: Text(
                  _selectedTimeRange == 2 && _todayGranularity == 1
                      ? "Waiting for live readings..."
                      : _todayGranularity == 1
                      ? "No minute data for this range"
                      : "No data for selected range",
                  style: TextStyle(color: _textSecondary(isDark)),
                ),
              )
            : ClipRect(
                child: CustomPaint(
                  painter: _HumidityChartPainter(
                    data: List.from(_activeChartData),
                    isDark: isDark,
                    rangeIndex: _selectedTimeRange,
                    rangeStart: range?.start ?? now,
                    rangeEnd: range?.end ?? now,
                  ),
                  child: const SizedBox(height: 210, width: double.infinity),
                ),
              ),
      ),
    );
  }

  Widget _buildHumidityReview(bool isDark) {
    final avgLabel = _activeDisplayAvg != null
        ? '${_activeDisplayAvg!.toStringAsFixed(1)}%'
        : '--';
    final minLabel = _activeDisplayMin != null
        ? '${_activeDisplayMin!.toStringAsFixed(1)}%'
        : '--';
    final maxLabel = _activeDisplayMax != null
        ? '${_activeDisplayMax!.toStringAsFixed(1)}%'
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
                  Icons.water_drop_outlined,
                  color: isDark ? Colors.white70 : const Color(0xFF1B3A4B),
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Humidity Review',
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
              if (_mlCondition != null && !_mlInsightLoading)
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
          if (_mlInsightLoading)
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
                  'AAnalyzing humidity data...',
                  style: TextStyle(fontSize: 12, color: _textSecondary(isDark)),
                ),
              ],
            )
          else if (_currentHumidity == null)
            Text(
              'Connect sensor to receive humidity insights.',
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
  Future<void> _fetchHumidityMLInsight(double humidity, double temperature) async {
    if (humidity <= 0) return;
    setState(() => _mlInsightLoading = true);
    try {
      final result = await MlService.analyzeFarm(
        temperatureC: temperature, // neutral temperature — not the focus here
        humidityPct: humidity,
      );
      if (!mounted) return;
      setState(() {
        _mlCondition = result['condition'] as String?;
        _mlInsight = (result['insights'] as List?)?.join(' ');
        _mlRecommendation =
            (result['recommendations'] as List?)?.first as String?;
        _mlInsightLoading = false;
      });
    } catch (e) {
      debugPrint('Humidity ML error: $e');
      if (!mounted) return;
      setState(() => _mlInsightLoading = false);
    }
  }
}

// ── Custom Range Bottom Sheet ─────────────────────────────────────────────────

class _HumidityCustomRangeSheet extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final int initialGranularity;
  final void Function(DateTime start, DateTime end, int granularity) onApply;

  const _HumidityCustomRangeSheet({
    required this.onApply,
    this.initialStart,
    this.initialEnd,
    this.initialGranularity = 0,
  });

  @override
  State<_HumidityCustomRangeSheet> createState() =>
      _HumidityCustomRangeSheetState();
}

class _HumidityCustomRangeSheetState extends State<_HumidityCustomRangeSheet> {
  late DateTime _startDate;
  late TimeOfDay _startTime;
  late DateTime _endDate;
  late TimeOfDay _endTime;
  late int _granularity;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDate = widget.initialStart ?? now;
    _startTime = TimeOfDay.fromDateTime(widget.initialStart ?? now);
    _endDate = widget.initialEnd ?? now;
    _endTime = TimeOfDay.fromDateTime(widget.initialEnd ?? now);
    _granularity = widget.initialGranularity;
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
              _HumidityDateTimeChip(
                icon: Icons.calendar_today_outlined,
                label: _humFormatDate(_startDate),
                onTap: () => _pickDate(true),
              ),
              const SizedBox(width: 8),
              _HumidityDateTimeChip(
                icon: Icons.access_time,
                label: _humFormatTime(_startTime),
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
              _HumidityDateTimeChip(
                icon: Icons.calendar_today_outlined,
                label: _humFormatDate(_endDate),
                onTap: () => _pickDate(false),
              ),
              const SizedBox(width: 8),
              _HumidityDateTimeChip(
                icon: Icons.access_time,
                label: _humFormatTime(_endTime),
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
          const SizedBox(height: 20),
          _rowLabel('Show Data By'),
          const SizedBox(height: 8),
          Row(
            children: List.generate(2, (index) {
              final label = index == 0 ? 'Hour' : 'Minute';
              final isSelected = _granularity == index;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _granularity = index),
                  child: Container(
                    margin: EdgeInsets.only(right: index == 0 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFFE8622A)
                          : const Color(0xFFE8622A).withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: const Color(0xFFE8622A).withValues(
                          alpha: isSelected ? 1 : 0.3,
                        ),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFFE8622A),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
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
                      widget.onApply(_fullStart, _fullEnd, _granularity);
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

class _HumidityDateTimeChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _HumidityDateTimeChip({
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

class _HumidityChartPainter extends CustomPainter {
  final List<Map<String, double>> data;
  final bool isDark;
  final int rangeIndex;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  _HumidityChartPainter({
    required this.data,
    this.isDark = false,
    required this.rangeIndex,
    required this.rangeStart,
    required this.rangeEnd,
  });

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

  List<(double, String)> _getXLabels() {
    switch (rangeIndex) {
      case 2: // Today — every 6 hours from midnight
        return const [
          (0.0, '12AM'),
          (6.0, '6AM'),
          (12.0, '12PM'),
          (18.0, '6PM'),
          (24.0, '12AM'),
        ];
      case 1: // This Week — one label per day
        return List.generate(7, (i) {
          const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          final d = rangeStart.add(Duration(days: i));
          return (i * 24.0, days[d.weekday - 1]);
        });
      case 0: // This Month — every 7 days
        final labels = <(double, String)>[];
        for (var i = 0; ; i += 7) {
          final d = rangeStart.add(Duration(days: i));
          if (d.isAfter(rangeEnd)) break;
          labels.add((i * 24.0, '${d.day}/${d.month}'));
        }
        return labels;
      case 3: // Custom range — auto-scale
        final totalH = rangeEnd.difference(rangeStart).inHours.toDouble();
        if (totalH <= 0) return const [];
        if (totalH <= 48) {
          final step = (totalH / 4).roundToDouble().clamp(1.0, 12.0);
          final labels = <(double, String)>[];
          for (var h = 0.0; h <= totalH + 0.01; h += step) {
            final dt = rangeStart.add(Duration(hours: h.toInt()));
            final hh = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
            final ampm = dt.hour < 12 ? 'AM' : 'PM';
            labels.add((h, '$hh$ampm'));
          }
          return labels;
        } else {
          final totalDays = (totalH / 24).ceil();
          final step = totalDays > 14 ? 7 : 1;
          final labels = <(double, String)>[];
          for (var d = 0; d < totalDays; d += step) {
            final dt = rangeStart.add(Duration(days: d));
            if (dt.isAfter(rangeEnd)) break;
            labels.add((d * 24.0, '${dt.day}/${dt.month}'));
          }
          return labels;
        }
      default:
        return const [];
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;

    const double leftPadding = 48;
    const double bottomPadding = 36;
    const double topPadding = 8;
    final double chartWidth = size.width - leftPadding;
    final double chartHeight = size.height - bottomPadding - topPadding;
    if (chartWidth <= 0 || chartHeight <= 0) return;

    const double yMin = 0.0;
    const double yMax = 100.0;

    final double totalHours = rangeEnd.difference(rangeStart).inMinutes / 60.0;
    if (totalHours <= 0) return;

    double getX(double hoursFromStart) =>
        leftPadding + (hoursFromStart / totalHours) * chartWidth;

    double getY(double hum) =>
        topPadding +
        chartHeight -
        ((hum.clamp(yMin, yMax) - yMin) / (yMax - yMin)) * chartHeight;

    final gridPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.07)
          : Colors.grey.shade200
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.12)
          : Colors.grey.shade300
      ..strokeWidth = 1;
    final labelStyle = TextStyle(
      color: isDark ? Colors.white38 : Colors.grey.shade500,
      fontSize: 9,
    );

    for (final step in [0, 25, 50, 75, 100]) {
      final y = getY(step.toDouble());
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '$step%',
          style: TextStyle(
            color: isDark ? Colors.white54 : Colors.grey.shade500,
            fontSize: 10,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    canvas.drawLine(
      Offset(leftPadding, topPadding),
      Offset(leftPadding, topPadding + chartHeight),
      axisPaint,
    );
    canvas.drawLine(
      Offset(leftPadding, topPadding + chartHeight),
      Offset(size.width, topPadding + chartHeight),
      axisPaint,
    );

    if (data.length < 2) return;

    final sampled = _sampleData(data, 80, 'humidity');

    for (final (xHours, label) in _getXLabels()) {
      final xCanvas = getX(xHours);
      if (xCanvas < leftPadding - 4 || xCanvas > size.width + 4) continue;
      final tp = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(xCanvas - tp.width / 2, topPadding + chartHeight + 6),
      );
    }

    final fillPath = Path();
    final linePath = Path();
    final firstX = getX(sampled.first['x']!);
    final firstY = getY(sampled.first['humidity']!);

    fillPath.moveTo(firstX, topPadding + chartHeight);
    fillPath.lineTo(firstX, firstY);
    linePath.moveTo(firstX, firstY);

    for (int i = 0; i < sampled.length - 1; i++) {
      final x0 = getX(sampled[i]['x']!);
      final y0 = getY(sampled[i]['humidity']!);
      final x1 = getX(sampled[i + 1]['x']!);
      final y1 = getY(sampled[i + 1]['humidity']!);
      if (x0.isNaN || y0.isNaN || x1.isNaN || y1.isNaN) continue;
      final cpX1 = x0 + (x1 - x0) * 0.5;
      final cpX2 = x1 - (x1 - x0) * 0.5;
      fillPath.cubicTo(cpX1, y0, cpX2, y1, x1, y1);
      linePath.cubicTo(cpX1, y0, cpX2, y1, x1, y1);
    }

    final lastX = getX(sampled.last['x']!);
    fillPath.lineTo(lastX, topPadding + chartHeight);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFEF5350).withValues(alpha: 0.85),
            const Color(0xFFEF5350).withValues(alpha: 0.15),
          ],
        ).createShader(Rect.fromLTWH(0, topPadding, size.width, chartHeight))
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = isDark ? const Color(0xFFEF9A9A) : const Color(0xFFC62828)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HumidityChartPainter old) => true;
}