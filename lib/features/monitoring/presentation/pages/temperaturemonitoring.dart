import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import '../../../../core/widgets/build_tab_bar.dart';
import 'package:prism_app/features/dashboard/presentation/pages/Dashboard_Screen.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

const String kEsp32BaseUrl = "http://192.168.1.100";

const List<String> kTimeRanges = [
  'This Month',
  'This Week',
  'Today',
  'Custom Range',
];

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

// ── Temperature Monitoring ────────────────────────────────────────────────────

class TemperatureMonitoring extends StatefulWidget {
  final VoidCallback? onSwitchToHumidity;
  final bool isActivated;
  final ValueChanged<bool> onSprinklerChanged;
  final ValueChanged<double>? onMaxTempChanged;
  const TemperatureMonitoring({
    super.key,
    this.onSwitchToHumidity,
    required this.isActivated,
    required this.onSprinklerChanged,
    this.onMaxTempChanged,
  });

  @override
  State<TemperatureMonitoring> createState() => _TemperatureMonitoringState();
}

class _TemperatureMonitoringState extends State<TemperatureMonitoring> {
  int _selectedTab = 0;
  int _selectedTimeRange = 2;
  bool _isSprinklerLoading = false;
  bool _isLoading = !SensorMemory.tempChartLoaded ||
      SensorMemory.lastTempChartDate != SensorMemory.todayKey();

  String _connectionStatus = SensorMemory.lastConnectionStatus;
  String _sensorStatus = "Sensor Offline";
  int _consecutiveFailures = 0;

  Timer? _durationTimer;
  DateTime? _sprinklerActivatedAt;

  double? _currentTemp;

  static bool _tempCacheIsToday() =>
      SensorMemory.lastTempChartDate == SensorMemory.todayKey();

  double? _displayMax = _tempCacheIsToday() ? SensorMemory.lastTempDisplayMax : null;
  double? _displayAvg = _tempCacheIsToday() ? SensorMemory.lastTempDisplayAvg : null;
  double? _displayMin = _tempCacheIsToday() ? SensorMemory.lastTempDisplayMin : null;

  double? _sessionMax = _tempCacheIsToday() ? SensorMemory.lastTempSessionMax : null;
  double? _sessionMin = _tempCacheIsToday() ? SensorMemory.lastTempSessionMin : null;

  double _sessionSeedSum = 0;
  int _sessionSeedCount = 0;

  // Per-session cache for This Week (index 1) and This Month (index 0).
  // Keyed by todayKey() so they auto-invalidate when the day rolls over.
  static List<Map<String, double>> _cachedWeekData = [];
  static double? _cachedWeekMax;
  static double? _cachedWeekMin;
  static double? _cachedWeekAvg;
  static String _cachedWeekDate = '';

  static List<Map<String, double>> _cachedMonthData = [];
  static double? _cachedMonthMax;
  static double? _cachedMonthMin;
  static double? _cachedMonthAvg;
  static String _cachedMonthDate = '';

  // Tracks the hour-bucket (e.g. 2025-01-01T14) that live readings are
  // currently being averaged into, so the "Today" average treats each
  // hour as one weighted entry — matching the granularity of the seeded
  // hourly-aggregate documents instead of letting whichever hour the app
  // happens to be open dominate the average.
  String? _liveHourKey;
  double _liveHourSum = 0;
  int _liveHourCount = 0;
  double _liveHourMax = 0;
  int? _liveHourChartIndex;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  String get _tempStatus {
    if (_currentTemp == null) return "";
    final t = _displayMax;
    if (t == null) return "";
    if (t >= 40.5) return "Critical";
    if (t >= 38.5) return "Elevated";
    return "Normal";
  }

  final List<Map<String, double>> _chartData =
      _tempCacheIsToday() ? List.of(SensorMemory.lastTempChartData) : [];
  Timer? _timer;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DateTime? _customStart;
  DateTime? _customEnd;
  DateTime? _lastSeededTimestamp;

  // Midnight of "today" — used as the X-axis zero point for live chart
  // points, so live points line up on the same real-time scale as the
  // seeded historical points (which use range.start as their zero point).
  DateTime get _todayStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _initConnectivityListener();
    _initData();
    _loadSprinklerState();
    tempMaxTodayNotifier.addListener(_onTempMaxNotifierChanged);
  }

  void _onTempMaxNotifierChanged() {
    if (!mounted) return;
    final v = tempMaxTodayNotifier.value;
    if (v > 0 && (_sessionMax == null || v > _sessionMax!)) {
      _sessionMax = v;
      if (_selectedTimeRange == 2) {
        setState(() => _displayMax = v);
        widget.onMaxTempChanged?.call(v);
      }
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

  void _initConnectivityListener() {
    // On launch: set status immediately based on current network state.
    Connectivity().checkConnectivity().then((results) {
      if (!mounted) return;
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (hasNet) {
        setState(() {
          _connectionStatus = "Live";
          SensorMemory.lastConnectionStatus = "Live";
        });
      } else {
        setState(() {
          _connectionStatus = "Connecting...";
          _currentTemp = null;
          _sensorStatus = "Sensor Offline";
          SensorMemory.lastConnectionStatus = "Connecting...";
          SensorMemory.lastSensorStatus = "Sensor Offline";
        });
      }
    });

    // Internet LOST → "Connecting..." (fetch will confirm "No connection" shortly after).
    // Internet BACK → "Live" immediately.
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      if (!mounted) return;
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      if (hasNet) {
        setState(() {
          _connectionStatus = "Live";
          SensorMemory.lastConnectionStatus = "Live";
        });
      } else {
        setState(() {
          _connectionStatus = "Connecting...";
          _currentTemp = null;
          _sensorStatus = "Sensor Offline";
          SensorMemory.lastConnectionStatus = "Connecting...";
          SensorMemory.lastSensorStatus = "Sensor Offline";
        });
        // Immediately attempt a fetch so it fails fast → "No connection" within ~1s.
        _fetchData();
      }
    });
  }

  Future<void> _initData() async {
    await _loadChartFromFirestore();
    if (!mounted) return;
    // Show cached data immediately — no spinner while waiting for network
    setState(() => _isLoading = false);
    await _fetchData();
    if (!mounted) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _durationTimer?.cancel();
    _connectivitySub?.cancel(); // add this
    tempMaxTodayNotifier.removeListener(_onTempMaxNotifierChanged);
    super.dispose();
  }

 // ── ESP32 fetch ─────────────────────────────────────────────────────────────

  Future<void> _fetchData() async {
    Map<String, dynamic>? data;
    bool isRemote = false;

    // 1. Try local ESP32 first (same-WiFi / LAN).
    try {
      final response = await http
          .get(Uri.parse('http://192.168.1.100/sensor'))
          .timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        data = jsonDecode(response.body) as Map<String, dynamic>;
      }
    } catch (_) {}

    // 2. Fallback: Firestore live_sensor document (works on mobile data /
    //    any WiFi — ESP32 firmware must push to live_sensor/latest).
    if (data == null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('live_sensor')
            .doc('latest')
            .get();
        if (doc.exists && doc.data() != null) {
          data = Map<String, dynamic>.from(doc.data()!);
          isRemote = true;
        }
      } catch (_) {}
    }

    // 3. Both sources failed.
    if (data == null) {
      _consecutiveFailures++;
      // Suppress the first failure — it's often a transient hiccup caused
      // by Firestore being busy loading chart data when the user switches
      // range tabs. Only flip to "Sensor Offline" after 2 consecutive misses.
      if (_consecutiveFailures < 2) return;
      if (!mounted) return;
      final results = await Connectivity().checkConnectivity();
      final hasNet = results.any((r) => r != ConnectivityResult.none);
      final connLabel = hasNet ? "Live" : "No connection";
      setState(() {
        _connectionStatus = connLabel;
        _sensorStatus = "Sensor Offline";
        SensorMemory.lastConnectionStatus = connLabel;
        SensorMemory.lastSensorStatus = "Sensor Offline";
        _isLoading = false;
        _currentTemp = null;
      });
      return;
    }

    try {
      final tempLive = (data['temperature'] as num?)?.toDouble()
          ?? (data['tempAvg'] as num?)?.toDouble();
      final tempMax = (data['tempMax'] as num?)?.toDouble();
      final tempAvg = (data['tempAvg'] as num?)?.toDouble();
      final tempMin = (data['tempMin'] as num?)?.toDouble();

      if (tempLive == null || tempMax == null || tempAvg == null || tempMin == null) return;
      if (tempMax < 0 || tempMin < 0 || tempAvg < 0) return;

      // Timestamp: String from local HTTP, Firestore Timestamp when remote.
      final tsField = data['timestamp'];
      DateTime? ts;
      if (tsField is Timestamp) {
        ts = tsField.toDate();
      } else if (tsField is String) {
        ts = DateTime.tryParse(tsField);
      }

      // Compute staleness before setState so the failure counter can be
      // updated before deciding whether to flip the sensor status.
      final nowUtc = DateTime.now().toUtc();
      final tsUtc = ts?.toUtc();
      final diffSeconds = tsUtc != null
          ? nowUtc.difference(tsUtc).inSeconds
          : -1;
      final stalenessLimit = isRemote ? 60 : 15;
      final isStale = ts == null || diffSeconds > stalenessLimit;

      if (isStale) {
        _consecutiveFailures++;
      } else {
        _consecutiveFailures = 0;
      }
      final shouldShowOffline = _consecutiveFailures >= 2;

      setState(() {
        _isLoading = false;

        if (!isStale) {
          // Fresh reading — reset failure streak and update sensor status.
          _connectionStatus = "Live";
          SensorMemory.lastConnectionStatus = "Live";
          _currentTemp = tempLive;
          _sensorStatus = "Sensor Online";
          SensorMemory.lastSensorStatus = "Sensor Online";

          if (_selectedTimeRange == 2) {
            final isNewReading = _lastSeededTimestamp == null ||
                ts!.isAfter(_lastSeededTimestamp!);

            if (isNewReading) {
              _accumulateLiveHourly(tempLive, tempAvg, ts!);
            }

            if (_sessionMax == null || tempLive > _sessionMax!) {
              _sessionMax = tempLive;
            }
            SensorMemory.resetIfNewDay();
            if (_sessionMax != null &&
                _sessionMax! > SensorMemory.lastTempMaxToday) {
              SensorMemory.setTempMaxToday(_sessionMax!);
              SensorMemory.save();
            }
            if (_sessionMin == null || tempMin < _sessionMin!) {
              _sessionMin = tempMin;
            }

            _displayMax = _sessionMax;
            widget.onMaxTempChanged?.call(_displayMax!);
            _displayMin = _sessionMin;
            _displayAvg = _computeWeightedAvg();
          }
        } else if (shouldShowOffline) {
          // Only flip to offline after 2+ consecutive stale/failed polls.
          _connectionStatus = "Sensor Offline";
          SensorMemory.lastConnectionStatus = "Sensor Offline";
          _currentTemp = null;
          _sensorStatus = "Sensor Offline";
          SensorMemory.lastSensorStatus = "Sensor Offline";
        }
        // First stale poll: keep previous status — don't flip offline yet.
      });

      // Keep Today cache in sync with live updates.
      if (_selectedTimeRange == 2) {
        SensorMemory.lastTempDisplayMax = _displayMax;
        SensorMemory.lastTempDisplayMin = _displayMin;
        SensorMemory.lastTempDisplayAvg = _displayAvg;
        SensorMemory.lastTempSessionMax = _sessionMax;
        SensorMemory.lastTempSessionMin = _sessionMin;
      }

    } catch (_) {
      _consecutiveFailures++;
      if (_consecutiveFailures < 2) return;
      if (!mounted) return;
      setState(() {
        _sensorStatus = "Sensor Offline";
        SensorMemory.lastSensorStatus = "Sensor Offline";
        _isLoading = false;
        _currentTemp = null;
      });
    }
  }

  /// Folds a new live reading into the current-hour bucket. Each hour
  /// contributes exactly ONE averaged value to the session total — same
  /// granularity as the seeded Firestore hourly-aggregate documents —
  /// so the live hour doesn't get over-weighted just because it has many
  /// more samples (one every ~5s) than the seeded hours (one per hour).
  /// Also updates a single chart point for the in-progress hour instead
  /// of appending a new point per reading, so the "Today" line has the
  /// same one-point-per-hour density as the seeded historical portion.
  // liveMax  → used for the chart point (tracks the hourly peak)
  // liveAvg  → used for the "Average" display stat only
  void _accumulateLiveHourly(double liveMax, double liveAvg, DateTime ts) {
    final hourKey = '${ts.year}-${ts.month}-${ts.day}-${ts.hour}';

    if (_liveHourKey != null && _liveHourKey != hourKey) {
      // Hour crossed — close out previous hour for the avg seed.
      if (_liveHourCount > 0) {
        _sessionSeedSum += _liveHourSum / _liveHourCount;
        _sessionSeedCount += 1;
      }
      _liveHourSum = 0;
      _liveHourCount = 0;
      _liveHourMax = 0;
      _liveHourChartIndex = null;
    }

    _liveHourKey = hourKey;
    _liveHourSum += liveAvg;   // average accumulator
    _liveHourCount += 1;
    if (liveMax > _liveHourMax) _liveHourMax = liveMax;  // peak for Highest stat only

    final x = ts.difference(_todayStart).inMinutes / 60.0;

    // Plot the current live reading (not the hourly peak) so the chart line
    // visually updates every 5 s with the actual sensor value.
    // _liveHourMax is still used for the "Highest" display stat.
    if (_liveHourChartIndex != null &&
        _liveHourChartIndex! < _chartData.length) {
      _chartData[_liveHourChartIndex!] = {'x': x, 'temp': liveMax};
    } else {
      _liveHourChartIndex = _chartData.length;
      _chartData.add({'x': x, 'temp': liveMax});
    }
  }

  /// Average across completed hours (seed) plus the current in-progress
  /// hour (live), each hour weighted equally regardless of sample count.
  double? _computeWeightedAvg() {
    final completedSum = _sessionSeedSum;
    final completedCount = _sessionSeedCount;
    final hasLiveHour = _liveHourCount > 0;

    final totalSum =
        completedSum + (hasLiveHour ? _liveHourSum / _liveHourCount : 0);
    final totalCount = completedCount + (hasLiveHour ? 1 : 0);

    return totalCount > 0 ? totalSum / totalCount : null;
  }

  Future<void> _loadChartFromFirestore() async {
    final rangeIndexAtLoad = _selectedTimeRange;

    final range = _resolveTimeRange(rangeIndexAtLoad, _customStart, _customEnd);
    if (range == null) return;

    // Serve cached result for This Week / This Month so tab switches are
    // instant. Cache is date-keyed and auto-invalidates at midnight.
    // Max/min are always re-merged with today's live data on cache hit.
    final today = SensorMemory.todayKey();
    if (rangeIndexAtLoad == 1 && _cachedWeekDate == today && _cachedWeekData.isNotEmpty) {
      setState(() {
        _chartData..clear()..addAll(_cachedWeekData);
        var cMax = _cachedWeekMax ?? 0.0;
        var cMin = _cachedWeekMin ?? double.infinity;
        SensorMemory.resetIfNewDay();
        if (SensorMemory.lastTempMaxToday > cMax) cMax = SensorMemory.lastTempMaxToday;
        if (SensorMemory.lastTempDisplayMin != null &&
            SensorMemory.lastTempDisplayMin! < cMin) cMin = SensorMemory.lastTempDisplayMin!;
        _displayMax = cMax;
        _displayMin = cMin == double.infinity ? _cachedWeekMin : cMin;
        _displayAvg = _cachedWeekAvg;
      });
      return;
    }
    if (rangeIndexAtLoad == 0 && _cachedMonthDate == today && _cachedMonthData.isNotEmpty) {
      setState(() {
        _chartData..clear()..addAll(_cachedMonthData);
        var cMax = _cachedMonthMax ?? 0.0;
        var cMin = _cachedMonthMin ?? double.infinity;
        SensorMemory.resetIfNewDay();
        if (SensorMemory.lastTempMaxToday > cMax) cMax = SensorMemory.lastTempMaxToday;
        if (SensorMemory.lastTempDisplayMin != null &&
            SensorMemory.lastTempDisplayMin! < cMin) cMin = SensorMemory.lastTempDisplayMin!;
        _displayMax = cMax;
        _displayMin = cMin == double.infinity ? _cachedMonthMin : cMin;
        _displayAvg = _cachedMonthAvg;
      });
      return;
    }

    try {
      final snapshot = await _db
          .collection('temperature_readings')
          .orderBy('timestamp', descending: false)
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(range.start),
          )
          .where(
            'timestamp',
            isLessThanOrEqualTo: Timestamp.fromDate(range.end),
          )
          .limit(2000)
          .get();

      if (!mounted || _selectedTimeRange != rangeIndexAtLoad) return;

      final docs = snapshot.docs;
      if (docs.isEmpty) {
        setState(() {
         _chartData.clear();
            if (rangeIndexAtLoad == 2) {
            // Fresh day — reset session so live readings start clean
            _sessionSeedSum = 0;
            _sessionSeedCount = 0;
            _liveHourKey = null;
            _liveHourSum = 0;
            _liveHourCount = 0;
            _liveHourMax = 0;
            _liveHourChartIndex = null;
            _sessionMax = null;
            _sessionMin = null;
            _lastSeededTimestamp = null;
            _displayMax = null;
            _displayAvg = null;
            _displayMin = null;
          } else {
            _displayMax = null;
            _displayAvg = null;
            _displayMin = null;
          }
        });
        return;
      }

      final allData = <Map<String, double>>[];
      final allMaxValues = <double>[];
      final allMinValues = <double>[];
      final allAvgValues = <double>[];
      DateTime? lastDocTimestamp;

      for (final doc in docs) {
        final d = doc.data();
        final rawMax = d['tempMax'];
        if (rawMax == null) continue;

        final max = (rawMax as num).toDouble();
        final min = (d['tempMin'] as num?)?.toDouble() ?? max;
        final avg = (d['tempAvg'] as num?)?.toDouble() ?? max;

        final docTs = (d['timestamp'] as Timestamp?)?.toDate();
        if (docTs != null) {
          lastDocTimestamp = docTs;
          // X-axis = actual elapsed hours since the range's start, so gaps
          // in coverage (e.g. sensor downtime) show as gaps in the line
          // instead of being silently compressed away by a sequential index.
          final x = docTs.difference(range.start).inMinutes / 60.0;
          allData.add({'x': x, 'temp': max});
        }
        allMaxValues.add(max);
        allMinValues.add(min);
        allAvgValues.add(avg);
      }

      if (allMaxValues.isEmpty) {
        setState(() {
          _chartData.clear();
          if (rangeIndexAtLoad != 2) {
            _displayMax = null;
            _displayAvg = null;
            _displayMin = null;
          }
        });
        return;
      }

      final historicalMax = allMaxValues.reduce((a, b) => a > b ? a : b);
      final historicalMin = allMinValues.reduce((a, b) => a < b ? a : b);
      final historicalAvg =
          allAvgValues.reduce((a, b) => a + b) / allAvgValues.length;

      setState(() {
        _chartData
          ..clear()
          ..addAll(allData);

        if (rangeIndexAtLoad == 2) {
          _liveHourKey = null;
          _liveHourSum = 0;
          _liveHourCount = 0;
          _liveHourMax = 0;
          _liveHourChartIndex = null;
          // Use the last seeded document's own Firestore timestamp as the
          // cutoff — comparing against the SAME clock that live readings'
          // `ts` come from, instead of the local device clock.
          _lastSeededTimestamp = lastDocTimestamp;

          // Each Firestore hourly-aggregate doc already represents one
          // hour's average — sum them as-is, one entry per hour.
          _sessionSeedSum = allAvgValues.reduce((a, b) => a + b);
          _sessionSeedCount = allAvgValues.length;

          _sessionMax = historicalMax;
          _sessionMin = historicalMin;

          // Seed from Firestore history, then take the larger of that and
          // whatever SensorMemory already knows (e.g. a higher live reading
          // recorded by another screen like the Dashboard, not yet pushed
          // to Firestore's hourly aggregate). Only write back to
          // SensorMemory when our value is the larger one — this lets both
          // screens converge upward without either one overwriting a
          // higher value the other already recorded.
          // Always overwrite lastTempMaxToday with the Firestore-derived
          // historicalMax — this corrects any stale/inflated value that was
          // saved by a previous code version using the ESP32's all-day
          // tempMax field. Live readings in _fetchData will push it higher
          // if the temperature genuinely exceeds this baseline.
          SensorMemory.resetIfNewDay();
          SensorMemory.setTempMaxToday(_sessionMax!);
          SensorMemory.save();
          _displayMax = _sessionMax;
          if (_displayMax != null) widget.onMaxTempChanged?.call(_displayMax!);
          _displayMin = _sessionMin;
          _displayAvg = _computeWeightedAvg();
        } else {
          double mergedMax = historicalMax;
          double mergedMin = historicalMin;
          // If this range's end includes "now" (This Week / This Month
          // both do, since their end is DateTime.now()), the live high/low
          // recorded in SensorMemory may be newer than anything that's
          // synced to Firestore's hourly aggregates yet. Without this,
          // a broader range can show a LOWER max than "Today" — which
          // is impossible since today is a subset of this week/month.
          final rangeIncludesToday = !range.end.isBefore(_todayStart);
          if (rangeIncludesToday) {
            SensorMemory.resetIfNewDay();
            if (SensorMemory.lastTempMaxToday > mergedMax) {
              mergedMax = SensorMemory.lastTempMaxToday;
            }
            if (SensorMemory.lastTempDisplayMin != null &&
                SensorMemory.lastTempDisplayMin! < mergedMin) {
              mergedMin = SensorMemory.lastTempDisplayMin!;
            }
          }
          _displayMax = mergedMax;
          _displayMin = mergedMin;
          _displayAvg = historicalAvg;
        }
      });

      // Cache Today tab data so navigating back shows values instantly.
      if (rangeIndexAtLoad == 2) {
        SensorMemory.lastTempChartData = List.of(_chartData);
        SensorMemory.tempChartLoaded = true;
        SensorMemory.lastTempChartDate = SensorMemory.todayKey();
        SensorMemory.lastTempDisplayMax = _displayMax;
        SensorMemory.lastTempDisplayMin = _displayMin;
        SensorMemory.lastTempDisplayAvg = _displayAvg;
        SensorMemory.lastTempSessionMax = _sessionMax;
        SensorMemory.lastTempSessionMin = _sessionMin;
      }
      // Cache This Week / This Month so repeat tab switches are instant.
      if (rangeIndexAtLoad == 1) {
        _cachedWeekData = List.of(_chartData);
        _cachedWeekMax = historicalMax;
        _cachedWeekMin = historicalMin;
        _cachedWeekAvg = historicalAvg;
        _cachedWeekDate = today;
      } else if (rangeIndexAtLoad == 0) {
        _cachedMonthData = List.of(_chartData);
        _cachedMonthMax = historicalMax;
        _cachedMonthMin = historicalMin;
        _cachedMonthAvg = historicalAvg;
        _cachedMonthDate = today;
      }
    } catch (e) {
      debugPrint('Firestore load error: $e');
      // Don't wipe existing display values on network failure —
      // keep whatever was already showing
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

      widget.onSprinklerChanged(turnOn);
      sprinklerNotifier.value = turnOn; // instantly notify dashboard
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

  Future<void> _confirmSprinkler() async {
    if (_isSprinklerLoading) return;

    final isOn = sprinklerNotifier.value;

    // Block activation when sensor is offline (deactivation always allowed)
    if (_sensorStatus != "Sensor Online" && !isOn) {
      showDialog(
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
    if (confirmed == true) await _toggleSprinkler(!isOn);
  }

  // ── Custom range picker ─────────────────────────────────────────────────────

  Future<void> _showCustomRangePicker() async {
    await showModalBottomSheet(
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
          });
          _loadChartFromFirestore();
        },
      ),
    );
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
    final sensorColor = sensorOnline ? Colors.green : Colors.red;

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
                    sensorOnline ? "Sensor Online" : "Sensor Offline",
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
                style: TextStyle(color: _textSecondary(isDark), fontSize: 13),
              ),
              const SizedBox(height: 4),
              _isLoading
                  ? const CircularProgressIndicator()
                  : Text(
                      currentLabel,
                      style: TextStyle(
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                        color: (_currentTemp ?? 0) >= 40.5
                            ? Colors.red
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
                  ), // closes AnimatedContainer
                ), // closes GestureDetector
              ), // closes ValueListenableBuilder
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
              setState(() => _selectedTimeRange = index);
              if (isCustom) {
                await _showCustomRangePicker();
              } else {
                _loadChartFromFirestore();
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
              });
              _loadChartFromFirestore();
            },
            child: const Icon(Icons.close, size: 14, color: Color(0xFFE8622A)),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(bool isDark) {
    final range = _resolveTimeRange(_selectedTimeRange, _customStart, _customEnd);
    final now = DateTime.now();
    return Container(
      decoration: _bentoCard(isDark, accentColor: Colors.green),
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: 210,
        width: double.infinity,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _chartData.isEmpty
            ? Center(
                child: Text(
                  "No data for selected range",
                  style: TextStyle(color: _textSecondary(isDark)),
                ),
              )
            : ClipRect(
                child: CustomPaint(
                  painter: _TemperatureChartPainter(
                    data: List.from(_chartData),
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

  Widget _buildTemperatureReview(bool isDark) {
    final avgLabel = _displayAvg != null
        ? '${_displayAvg!.toStringAsFixed(1)}°C'
        : '--';
    final minLabel = _displayMin != null
        ? '${_displayMin!.toStringAsFixed(1)}°C'
        : '--';
    final maxLabel = _displayMax != null
        ? '${_displayMax!.toStringAsFixed(1)}°C'
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
    final accentAlpha = isDark ? 0.25 : 0.15;
    final shadowAlpha = isDark ? 0.12 : 0.06;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFFE8A020).withValues(alpha: 0.12)
            : const Color(0xFFFFF9C4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE8A020).withValues(alpha: accentAlpha),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE8A020).withValues(alpha: shadowAlpha),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                'Insights:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _textPrimary(isDark),
                ),
              ),
            ],
          ),
          // TODO: ML output goes here
        ],
      ),
    );
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
                onTap: () => Navigator.pop(context),
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
                      Navigator.pop(context);
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
  final int rangeIndex;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  _TemperatureChartPainter({
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

  // Returns (xHours, label) pairs for X-axis tick marks.
  // xHours is in the same units as the data: hours since midnight (Today)
  // or hours since rangeStart (all other ranges).
  List<(double, String)> _getXLabels() {
    switch (rangeIndex) {
      case 2: // Today — label every 6 hours
        return const [
          (0.0, '12AM'),
          (6.0, '6AM'),
          (12.0, '12PM'),
          (18.0, '6PM'),
        ];
      case 1: // This Week — one label per day
        return List.generate(7, (i) {
          const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
          final d = rangeStart.add(Duration(days: i));
          return (i * 24.0, days[d.weekday - 1]);
        });
      case 0: // This Month — label every 7 days
        final labels = <(double, String)>[];
        for (var i = 0; ; i += 7) {
          final d = rangeStart.add(Duration(days: i));
          if (d.isAfter(rangeEnd)) break;
          labels.add((i * 24.0, '${d.day}/${d.month}'));
        }
        return labels;
      case 3: // Custom Range — auto based on duration
        final totalH = rangeEnd.difference(rangeStart).inHours.toDouble();
        if (totalH <= 0) return const [];
        if (totalH <= 48) {
          final step = (totalH / 4).roundToDouble().clamp(1.0, 12.0);
          final labels = <(double, String)>[];
          for (var h = 0.0; h <= totalH; h += step) {
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
    const double yMin = 20.0;
    const double yMax = 45.0;

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

    for (final step in [20, 25, 30, 35, 40, 45]) {
      final y =
          topPadding +
          chartHeight -
          ((step - yMin) / (yMax - yMin)) * chartHeight;
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '$step°C',
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

    final sampled = _sampleData(data, 80, 'temp');
    final xMin = sampled.first['x']!;
    final xMax = sampled.last['x']!;
    if (xMax == xMin) return;

    double getX(double v) =>
        leftPadding + ((v - xMin) / (xMax - xMin)) * chartWidth;
    double getY(double t) =>
        topPadding +
        chartHeight -
        ((t.clamp(yMin, yMax) - yMin) / (yMax - yMin)) * chartHeight;

    // X-axis time labels.
    for (final (xHours, label) in _getXLabels()) {
      final xCanvas = getX(xHours);
      if (xCanvas < leftPadding || xCanvas > size.width) continue;
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
    final firstY = getY(sampled.first['temp']!);

    fillPath.moveTo(firstX, topPadding + chartHeight);
    fillPath.lineTo(firstX, firstY);
    linePath.moveTo(firstX, firstY);

    for (int i = 0; i < sampled.length - 1; i++) {
      final x0 = getX(sampled[i]['x']!);
      final y0 = getY(sampled[i]['temp']!);
      final x1 = getX(sampled[i + 1]['x']!);
      final y1 = getY(sampled[i + 1]['temp']!);
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
            const Color(0xFF4CAF50).withValues(alpha: 0.85),
            const Color(0xFF4CAF50).withValues(alpha: 0.15),
          ],
        ).createShader(Rect.fromLTWH(0, topPadding, size.width, chartHeight))
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = isDark ? const Color(0xFF66BB6A) : const Color(0xFF2E7D32)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TemperatureChartPainter old) => true;
}
