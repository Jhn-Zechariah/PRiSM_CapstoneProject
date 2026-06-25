import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import '../../../../core/widgets/build_tab_bar.dart';
import 'package:prism_app/features/dashboard/presentation/pages/Dashboard_Screen.dart';

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
  int _selectedTab = 1;
  int _selectedTimeRange = 2;
  bool _isSprinklerLoading = false;
  static bool _humidityCacheIsToday() =>
      SensorMemory.lastHumidityChartDate == SensorMemory.todayKey();

  bool _isLoading = !SensorMemory.humidityChartLoaded ||
      !_humidityCacheIsToday();

  // Now mirrors LiveSensorService directly instead of maintaining its own
  // HTTP polling / failure-counting logic.
  String _connectionStatus = LiveSensorService.connectionStatus.value;
  String _sensorStatus = LiveSensorService.sensorStatus.value;

  // ── THEME HELPERS ──────────────────────────────────────────────────
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
        spreadRadius: 0,
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

  Timer? _durationTimer;
  DateTime? _sprinklerActivatedAt;

  // Live reading (current snapshot)
  double? _currentHumidity;
  DateTime? _lastAppliedTimestamp;

  // Display stats shown in the review card.
  double? _displayMax = _humidityCacheIsToday() ? SensorMemory.lastHumidityDisplayMax : null;
  double? _displayMin = _humidityCacheIsToday() ? SensorMemory.lastHumidityDisplayMin : null;
  double? _displayAvg = _humidityCacheIsToday() ? SensorMemory.lastHumidityDisplayAvg : null;

  // Per-session cache for This Week (index 1) and This Month (index 0).
  // Keyed by hour so they auto-refresh once a new hourly doc lands.
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
    if (h >= 80) return "High";
    if (h <= 40) return "Low";
    return "Normal";
  }

  final List<Map<String, double>> _chartData =
  _humidityCacheIsToday() ? List.of(SensorMemory.lastHumidityChartData) : [];

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

    // Listen to the single shared poller instead of running our own
    // Timer + http.get() against the ESP32. This now only feeds the
    // live numeric readout on the status card — the chart itself is
    // sourced entirely from humidity_hourly (see _loadChartFromFirestore).
    LiveSensorService.latestData.addListener(_onLiveDataChanged);
    LiveSensorService.connectionStatus.addListener(_onSharedStatusChanged);
    LiveSensorService.sensorStatus.addListener(_onSharedStatusChanged);

    // ESP32 writes one new humidity_hourly doc per hour, so there's no
    // point re-querying more often. This timer just triggers a check —
    // _loadChartFromFirestore() itself is a no-op (zero reads) if the
    // current hour key hasn't advanced since the last successful load.
    _hourlyRefreshTimer = Timer.periodic(
        const Duration(hours: 1), (_) => _loadChartFromFirestore());
  }

  void _onSharedStatusChanged() {
    if (!mounted) return;
    setState(() {
      _connectionStatus = LiveSensorService.connectionStatus.value;
      _sensorStatus = LiveSensorService.sensorStatus.value;
      if (_sensorStatus == "Sensor Offline") _currentHumidity = null;
    });
  }

  /// Updates only the live numeric readout shown on the status card.
  /// The chart, averages, and min/max stats all come from
  /// humidity_hourly via _loadChartFromFirestore — this no longer
  /// feeds the chart at all, since hourly docs are the single source
  /// of truth for "Today" as well as Week/Month/Custom ranges now.
  void _onLiveDataChanged() {
    if (!mounted) return;
    final data = LiveSensorService.latestData.value;
    if (data == null) return;

    final hRaw = data['humidity'];
    if (hRaw == null) return;
    final h = (hRaw as num).toDouble();

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

    setState(() {
      _currentHumidity = h;
      _isLoading = false;
    });
  }

  void _onHumidityMaxNotifierChanged() {
    if (!mounted) return;
    final v = humidityMaxTodayNotifier.value;
    if (v > 0 && _selectedTimeRange == 2 &&
        (_displayMax == null || v > _displayMax!)) {
      setState(() => _displayMax = v);
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
    // Apply whatever the shared service already has, in case it fetched
    // before this screen's listener was attached.
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

  // ── Chart data — sourced entirely from humidity_hourly ──────────────
  //
  // The ESP32 writes exactly one new document to humidity_hourly per
  // hour, for every time range (Today/Week/Month/Custom). Each hourly
  // doc already carries its own humidityMax/humidityMin/humidityAvg, so
  // min/max/avg for the whole range can be derived directly from the
  // SAME docs fetched for the chart — no second uncapped query needed.

  Future<void> _loadChartFromFirestore() async {
    final rangeIndexAtLoad = _selectedTimeRange;

    final range = _resolveTimeRange(rangeIndexAtLoad, _customStart, _customEnd);
    if (range == null) return;

    // Serve cached result for This Week / This Month so tab switches are
    // instant. Cache is date-keyed and auto-invalidates at midnight.
    // Max/min are always re-merged with today's live data on cache hit.
    final today = SensorMemory.todayKey();
    final hourKey = currentHourKey();

    // Today: cache hit if we've already loaded for this hour.
    if (rangeIndexAtLoad == 2 &&
        SensorMemory.lastHumidityChartHourKey == hourKey &&
        SensorMemory.lastHumidityChartDate == today &&
        SensorMemory.humidityChartLoaded) {
      return; // already up to date, zero reads
    }
    // Week/Month: cache hit if loaded within this same hour.
    if (rangeIndexAtLoad == 1 &&
        _cachedWeekHourKey == hourKey &&
        _cachedWeekData.isNotEmpty) {
      setState(() {
        _chartData..clear()..addAll(_cachedWeekData);
        _displayMax = _cachedWeekMax;
        _displayMin = _cachedWeekMin;
        _displayAvg = _cachedWeekAvg;
      });
      return;
    }
    if (rangeIndexAtLoad == 0 &&
        _cachedMonthHourKey == hourKey &&
        _cachedMonthData.isNotEmpty) {
      setState(() {
        _chartData..clear()..addAll(_cachedMonthData);
        _displayMax = _cachedMonthMax;
        _displayMin = _cachedMonthMin;
        _displayAvg = _cachedMonthAvg;
      });
      return;
    }

    try {
      // Single source of truth for ALL ranges: humidity_hourly. The
      // ESP32 writes one doc/hour here, so even a Month-wide query only
      // returns on the order of ~720-750 docs — a fraction of what the
      // old per-reading collection (plus its separate uncapped accurate-
      // stats query) would have returned for the same range.
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
          .limit(800) // generous ceiling for a ~31-day month of hourly docs
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

      final allData = <Map<String, double>>[];
      final allMaxValues = <double>[];
      final allMinValues = <double>[];
      final allAvgValues = <double>[];

      for (final doc in docs) {
        final d = doc.data();
        final rawAvg = d['humidityAvg'];
        if (rawAvg == null) continue;

        final avg = (rawAvg as num).toDouble();
        final max = (d['humidityMax'] as num?)?.toDouble() ?? avg;
        final min = (d['humidityMin'] as num?)?.toDouble() ?? avg;

        final docTs = (d['timestamp'] as Timestamp?)?.toDate();
        if (docTs != null) {
          // X-axis = actual elapsed hours since the range's start, so gaps
          // in coverage (e.g. sensor downtime) show as gaps in the line
          // instead of being silently compressed away by a sequential index.
          final x = docTs.difference(range.start).inMinutes / 60.0;
          allData.add({'x': x, 'humidity': max});
        }
        allMaxValues.add(max);
        allMinValues.add(min);
        allAvgValues.add(avg);
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

      // Derived directly from the hourly docs already fetched above —
      // each doc already carries its own pre-aggregated max/min/avg for
      // that hour, so no second query is needed to get an accurate
      // range-wide max/min/avg.
      final historicalMax = allMaxValues.reduce((a, b) => a > b ? a : b);
      final historicalMin = allMinValues.reduce((a, b) => a < b ? a : b);
      final historicalAvg =
          allAvgValues.reduce((a, b) => a + b) / allAvgValues.length;

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

      // Cache Today so navigating back / hourly re-checks are instant.
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
      // Cache Week/Month, keyed by hour so they refresh once an hour.
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

  Widget _buildConnectionBadge() {
    final Color badgeColor;
    final Color bgColor;
    if (_connectionStatus == "Live") {
      badgeColor = Colors.green;
      bgColor = Colors.green.shade100;
    } else if (_connectionStatus == "Connecting..." ||
        _connectionStatus == "Reconnecting...") {
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

    // Block activation when sensor is offline (deactivation always allowed)
    if (_sensorStatus != "Sensor Online" && !isOn) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      _isSprinklerDialogOpen = false; // ← reset before returning
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
                    if (index == 0) widget.onSwitchToTemperature?.call();
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
    final sensorColor = sensorOnline ? Colors.green : Colors.red;

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
                  color: (_currentHumidity ?? 0) >= 80
                      ? Colors.red
                      : (_currentHumidity ?? 100) <= 40
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
                      Icons.calendar_month_outlined,
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
      decoration: _bentoCard(isDark, accentColor: const Color(0xFFEF5350)),
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: 210,
        width: double.infinity,
        child: _isLoading
            ? Center(
          child: CircularProgressIndicator(
            color: const Color(0xFFE8622A),
          ),
        )
            : _chartData.isEmpty
            ? Center(
          child: Text(
            "No data for selected range",
            style: TextStyle(color: _textSecondary(isDark)),
          ),
        )
            : ClipRect(
          child: CustomPaint(
            painter: _HumidityChartPainter(
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

  Widget _buildHumidityReview(bool isDark) {
    final avgLabel = _displayAvg != null
        ? '${_displayAvg!.toStringAsFixed(1)}%'
        : '--';
    final minLabel = _displayMin != null
        ? '${_displayMin!.toStringAsFixed(1)}%'
        : '--';
    final maxLabel = _displayMax != null
        ? '${_displayMax!.toStringAsFixed(1)}%'
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFFE8A020).withValues(alpha: 0.12)
            : const Color(0xFFFFF9C4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE8A020).withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFE8A020).withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
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

  // Returns (xHours, label) pairs for X-axis tick marks.
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
    const yMax = 100.0;
    const yMin = 0.0;

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
      final y =
          topPadding +
              chartHeight -
              ((step - yMin) / (yMax - yMin)) * chartHeight;
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '$step%',
          style: TextStyle(
            color: isDark ? Colors.white38 : Colors.grey.shade500,
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
    final xMin = sampled.first['x']!;
    final xMax = sampled.last['x']!;
    if (xMax == xMin) return;

    double getX(double v) =>
        leftPadding + ((v - xMin) / (xMax - xMin)) * chartWidth;
    double getY(double h) =>
        topPadding +
            chartHeight -
            ((h.clamp(yMin, yMax) - yMin) / (yMax - yMin)) * chartHeight;

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
            const Color(0xFFEF5350).withValues(alpha: isDark ? 0.5 : 0.85),
            const Color(0xFFEF5350).withValues(alpha: 0.05),
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