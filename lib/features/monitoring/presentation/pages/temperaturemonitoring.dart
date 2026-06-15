import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import '../../../../core/widgets/build_tab_bar.dart';
import 'package:prism_app/features/dashboard/presentation/pages/Dashboard_Screen.dart';

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
class _SprinklerMemory {
  static String lastActivated = "--";
  static String date = "--";
  static String duration = "--";
  static String status = "OFF";
  static DateTime? activatedAt;

  static Future<void> save() async {
    try {
      await FirebaseFirestore.instance
          .collection('sprinkler_state')
          .doc('latest')
          .set({
            'lastActivated': lastActivated,
            'date': date,
            'duration': duration,
            'status': status,
            'activatedAt': activatedAt != null
                ? Timestamp.fromDate(activatedAt!)
                : null,
          });
    } catch (e) {
      debugPrint('Error saving sprinkler state: $e');
    }
  }

  static Future<void> load() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('sprinkler_state')
          .doc('latest')
          .get();
      if (doc.exists) {
        final data = doc.data()!;
        lastActivated = data['lastActivated'] as String? ?? '--';
        date = data['date'] as String? ?? '--';
        duration = data['duration'] as String? ?? '--';
        status = data['status'] as String? ?? 'OFF';
        final at = data['activatedAt'];
        activatedAt = at != null ? (at as Timestamp).toDate() : null;
      }
    } catch (e) {
      debugPrint('Error loading sprinkler state: $e');
    }
  }
} // ← one closing

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
    this.onMaxTempChanged, // 👈 ADD THIS LINE
  });

  @override
  State<TemperatureMonitoring> createState() => _TemperatureMonitoringState();
}

class _TemperatureMonitoringState extends State<TemperatureMonitoring> {
  int _selectedTab = 0;
  int _selectedTimeRange = 2;
  bool _isSprinklerLoading = false;
  bool _isLoading = true;

  String _connectionStatus = "Connecting...";
  int _failStreak = 0;

  Timer? _durationTimer;
  DateTime? _sprinklerActivatedAt;

  double? _currentTemp;

  double? _displayMax;
  double? _displayAvg;
  double? _displayMin;

  double? _sessionMax;
  double? _sessionMin;
  double _sessionSum = 0;
  int _sessionCount = 0;

  double _sessionSeedSum = 0;
  int _sessionSeedCount = 0;

  String get _tempStatus {
    final t = _displayMax;
    if (t == null) return "Normal";
    if (t >= 40.5) return "Critical";
    if (t >= 38.5) return "Elevated";
    return "Normal";
  }

  final List<Map<String, double>> _chartData = [];
  int _nextChartIndex = 0;
  Timer? _timer;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _initData();
    _loadSprinklerState();
  }

  Future<void> _loadSprinklerState() async {
    await _SprinklerMemory.load();
    if (!mounted) return;
    if (_SprinklerMemory.activatedAt != null) {
      _startDurationTimer(_SprinklerMemory.activatedAt!);
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
      _SprinklerMemory.duration = d;
    });
  }

  void _stopDurationTimer({bool keepDuration = false}) {
    _durationTimer?.cancel();
    _durationTimer = null;
    if (keepDuration && _sprinklerActivatedAt != null) {
      final elapsed = DateTime.now().difference(_sprinklerActivatedAt!);
      final mins = elapsed.inMinutes;
      final secs = elapsed.inSeconds % 60;
      _SprinklerMemory.duration = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
    }
    _sprinklerActivatedAt = null;
  }

  Future<void> _initData() async {
    await _loadChartFromFirestore(); // wait for full history first
    if (!mounted) return;
    await _fetchData(); // then do first live fetch
    if (!mounted) return;
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _durationTimer?.cancel();
    super.dispose();
  }

  // ── Firestore ───────────────────────────────────────────────────────────────

  Future<void> _saveToFirestore(
    double tempMax,
    double tempAvg,
    double tempMin,
  ) async {
    try {
      await _db.collection('temperature_readings').add({
        'tempMax': tempMax,
        'tempAvg': tempAvg,
        'tempMin': tempMin,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Firestore save error: $e');
    }
  }

  Future<void> _loadChartFromFirestore() async {
    final rangeIndexAtLoad = _selectedTimeRange;

    final range = _resolveTimeRange(rangeIndexAtLoad, _customStart, _customEnd);
    if (range == null) return;

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
            _nextChartIndex = 0;
            if (rangeIndexAtLoad == 2) {
              // Fresh day — reset session so live readings start clean
              _sessionSum = 0;
              _sessionCount = 0;
              _sessionSeedSum = 0;
              _sessionSeedCount = 0;
              _sessionMax = null;
              _sessionMin = null;
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

      for (final doc in docs) {
        final d = doc.data();
        final rawMax = d['tempMax'];
        if (rawMax == null) continue;

        final max = (rawMax as num).toDouble();
        final min = (d['tempMin'] as num?)?.toDouble() ?? max;
        final avg = (d['tempAvg'] as num?)?.toDouble() ?? max;

        // Each document = one chart point using its own tempMax value
        allData.add({'index': allData.length.toDouble(), 'temp': avg});
        allMaxValues.add(max);
        allMinValues.add(min);
        allAvgValues.add(avg);
      }

      if (allMaxValues.isEmpty) {
        setState(() {
          _chartData.clear();
          _nextChartIndex = 0;
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

        // Seed counter so live points continue after history without index collision
        _nextChartIndex = allData.length;

        if (rangeIndexAtLoad == 2) {
          // Reset ALL session accumulators so there's no double-counting
          _sessionSum = 0;
          _sessionCount = 0;
          _sessionSeedSum = allAvgValues.reduce((a, b) => a + b);
          _sessionSeedCount = allAvgValues.length;

          // Reset max/min so live readings don't bleed in from other tabs
          _sessionMax = historicalMax;
          _sessionMin = historicalMin;

          _displayMax = _sessionMax;
          widget.onMaxTempChanged?.call(_displayMax!);
          _displayMin = _sessionMin;
          _displayAvg = _sessionSeedSum / _sessionSeedCount;
        } else {
          // This Week / This Month / Custom — pure Firestore stats
          _displayMax = historicalMax;
          _displayMin = historicalMin;
          _displayAvg = historicalAvg;
        }
      });
    } catch (e) {
      debugPrint('Firestore load error: $e');
    }
  }
  // ── ESP32 fetch ─────────────────────────────────────────────────────────────

  Future<void> _fetchData() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('sensor_live')
          .doc('current')
          .get();

      if (!doc.exists) return;
      final data = doc.data()!;

      final tempMax = (data['tempMax'] as num?)?.toDouble();
      final tempAvg = (data['tempAvg'] as num?)?.toDouble();
      final tempMin = (data['tempMin'] as num?)?.toDouble();

      if (tempMax == null || tempAvg == null || tempMin == null) return;
      if (tempMax < 0 || tempMin < 0 || tempAvg < 0) return;

      setState(() {
        _currentTemp = tempMax;
        _isLoading = false;
        _connectionStatus = "Live";
        _failStreak = 0;

        if (_selectedTimeRange == 2) {
          _sessionSum += tempAvg;
          _sessionCount += 1;

          if (_sessionMax == null || tempMax > _sessionMax!)
            _sessionMax = tempMax;
          if (_sessionMin == null || tempMin < _sessionMin!)
            _sessionMin = tempMin;

          _displayMax = _sessionMax;
          widget.onMaxTempChanged?.call(_displayMax!);
          _displayMin = _sessionMin;
          _displayAvg =
              (_sessionSeedSum + _sessionSum) /
              (_sessionSeedCount + _sessionCount);

          _chartData.add({
            'index': _nextChartIndex.toDouble(),
            'temp': tempAvg,
          });
          _nextChartIndex++;
        }
      });

      await _saveToFirestore(tempMax, tempAvg, tempMin);
    } catch (_) {
      setState(() {
        _failStreak++;
        if (_failStreak == 1) {
          _connectionStatus = "Reconnecting...";
        } else if (_failStreak >= 4) {
          _connectionStatus = "No connection";
        }
        _isLoading = false;
      });
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

        _SprinklerMemory.lastActivated = timeStr;
        _SprinklerMemory.date = dateStr;
        _SprinklerMemory.duration = '0s';
        _SprinklerMemory.status = "ON";
        _SprinklerMemory.activatedAt = now;
        await _SprinklerMemory.save();

        _startDurationTimer(now);
      } else {
        String finalDuration = '--';
        if (_sprinklerActivatedAt != null) {
          final elapsed = now.difference(_sprinklerActivatedAt!);
          final mins = elapsed.inMinutes;
          final secs = elapsed.inSeconds % 60;
          finalDuration = mins > 0 ? '${mins}m ${secs}s' : '${secs}s';
        }
        _SprinklerMemory.duration = finalDuration;
        _SprinklerMemory.status = "OFF";
        _SprinklerMemory.activatedAt = null;
        await _SprinklerMemory.save();

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

  Future<void> _confirmSprinkler() async {
    if (_isSprinklerLoading) return;
    final isOn = sprinklerNotifier.value;
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
    return Row(
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
        const Spacer(),
        _buildConnectionBadge(),
      ],
    );
  }

  Widget _buildConnectionBadge() {
    final Color badgeColor;
    final Color bgColor;
    if (_connectionStatus == "Live") {
      badgeColor = Colors.green;
      bgColor = Colors.green.shade100;
    } else if (_connectionStatus == "Reconnecting...") {
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
    return Container(
      decoration: _bentoCard(isDark, accentColor: Colors.green),
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: 200,
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
                  ),
                  child: const SizedBox(height: 200, width: double.infinity),
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
                _buildReviewStat('Average', avgLabel, const Color(0xFFE8622A), isDark),
                VerticalDivider(color: _dividerColor(isDark), thickness: 1),
                _buildReviewStat('Lowest', minLabel, const Color(0xFF1B3A4B), isDark),
                VerticalDivider(color: _dividerColor(isDark), thickness: 1),
                _buildReviewStat('Highest', maxLabel, Colors.red, isDark),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStat(String label, String value, Color valueColor, bool isDark) {
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
  _TemperatureChartPainter({required this.data, this.isDark = false});

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
      final avg =
          bucket.map((e) => e[key]!).reduce((a, b) => a + b) / bucket.length;
      result.add({'index': i.toDouble(), key: avg});
    }
    return result;
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
    // AFTER
    const double yMin = 20.0; // ← changed
    const double yMax = 45.0;
    // ← added 20

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
    final xMin = sampled.first['index']!;
    final xMax = sampled.last['index']!;
    if (xMax == xMin) return;

    double getX(double i) =>
        leftPadding + ((i - xMin) / (xMax - xMin)) * chartWidth;
    double getY(double t) =>
        topPadding +
        chartHeight -
        ((t.clamp(yMin, yMax) - yMin) / (yMax - yMin)) * chartHeight;

    final fillPath = Path();
    final linePath = Path();
    final firstX = getX(sampled.first['index']!);
    final firstY = getY(sampled.first['temp']!);

    fillPath.moveTo(firstX, topPadding + chartHeight);
    fillPath.lineTo(firstX, firstY);
    linePath.moveTo(firstX, firstY);

    for (int i = 0; i < sampled.length - 1; i++) {
      final x0 = getX(sampled[i]['index']!);
      final y0 = getY(sampled[i]['temp']!);
      final x1 = getX(sampled[i + 1]['index']!);
      final y1 = getY(sampled[i + 1]['temp']!);
      if (x0.isNaN || y0.isNaN || x1.isNaN || y1.isNaN) continue;
      final cpX1 = x0 + (x1 - x0) * 0.5;
      final cpX2 = x1 - (x1 - x0) * 0.5;
      fillPath.cubicTo(cpX1, y0, cpX2, y1, x1, y1);
      linePath.cubicTo(cpX1, y0, cpX2, y1, x1, y1);
    }

    final lastX = getX(sampled.last['index']!);
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
