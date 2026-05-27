import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import '../../../../core/widgets/build_tab_bar.dart';

// FIX #9: single shared constant, no more kEsp32IpHumidity
const String kEsp32BaseUrl = "http://192.168.1.100";

// FIX #11: shared time range list
const List<String> kTimeRanges = [
  'This Month', 'This Week', 'Today', 'Custom Range',
];

// FIX #11: shared date/time formatters
String _formatDateTime(DateTime dt) {
  final d   = dt.day.toString().padLeft(2, '0');
  final m   = dt.month.toString().padLeft(2, '0');
  final h   = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final min = dt.minute.toString().padLeft(2, '0');
  final p   = dt.hour < 12 ? 'AM' : 'PM';
  return '$d/$m/${dt.year}  $h:$min $p';
}

String _formatDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/'
    '${d.month.toString().padLeft(2, '0')}/${d.year}';

String _formatTime(TimeOfDay t) {
  final h   = t.hour == 0 ? 12 : t.hour > 12 ? t.hour - 12 : t.hour;
  final min = t.minute.toString().padLeft(2, '0');
  final p   = t.period == DayPeriod.am ? 'AM' : 'PM';
  return '${h.toString().padLeft(2, '0')}:$min $p';
}

// FIX #11: shared time range resolver
DateTimeRange? _resolveTimeRange(
    int index, DateTime? customStart, DateTime? customEnd) {
  final now = DateTime.now();
  switch (index) {
    case 0:
      return DateTimeRange(
          start: DateTime(now.year, now.month, 1), end: now);
    case 1:
      final ws = now.subtract(Duration(days: now.weekday - 1));
      return DateTimeRange(
          start: DateTime(ws.year, ws.month, ws.day), end: now);
    case 2:
      return DateTimeRange(
          start: DateTime(now.year, now.month, now.day), end: now);
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
  const HumidityMonitoring({super.key, this.onSwitchToTemperature});

  @override
  State<HumidityMonitoring> createState() => _HumidityMonitoringState();
}

class _HumidityMonitoringState extends State<HumidityMonitoring> {
  int  _selectedTab        = 1;
  int  _selectedTimeRange  = 2;
  bool _isActivated        = false;
  bool _isSprinklerLoading = false; // FIX #12
  bool _isLoading          = true;

  String _connectionStatus = "Connecting...";
  int    _failStreak       = 0;

  double? _humidity;
  double? _humidityMax;
  double? _humidityMin;
  double? _humidityAvg;

  int    _liveReadingCount = 0;
  double _liveHumiditySum  = 0;

  // FIX #4: compute status locally (consistent with temperature approach)
  String get _humidityStatus {
    final h = _humidity;
    if (h == null) return "Normal";
    if (h > 80) return "High";
    if (h < 40) return "Low";
    return "Normal";
  }

  // FIX #3: only append live points when on "Today"
  bool get _isLiveRange => _selectedTimeRange == 2;

  // FIX #5: avoid redundant Firestore writes
  double? _lastSavedHumidity;

  // FIX #7: track session stats for Firestore save
  double? _sessionMax;
  double? _sessionMin;
  double? _sessionAvg;

  final List<Map<String, double>> _chartData = [];
  Timer? _timer;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    _loadChartFromFirestore();
    _fetchData();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ── Firestore ───────────────────────────────────────────────────────────────

  Future<void> _saveToFirestore(double humidity) async {
    // FIX #5: skip if value unchanged
    if (_lastSavedHumidity == humidity) return;
    _lastSavedHumidity = humidity;
    try {
      // FIX #7: save min/max/avg to match temperature's Firestore structure
      await _db.collection('humidity_readings').add({
        'humidity':    humidity,
        'humidityMax': _sessionMax ?? humidity,
        'humidityMin': _sessionMin ?? humidity,
        'humidityAvg': _sessionAvg ?? humidity,
        'timestamp':   FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Firestore save error: $e');
    }
  }

  Future<void> _loadChartFromFirestore() async {
    final range = _resolveTimeRange(_selectedTimeRange, _customStart, _customEnd);
    if (range == null) return;

    try {
      // FIX #6: raised limit so monthly data is never cut off
      final snapshot = await _db
          .collection('humidity_readings')
          .orderBy('timestamp', descending: false)
          .where('timestamp',
              isGreaterThanOrEqualTo: Timestamp.fromDate(range.start))
          .where('timestamp',
              isLessThanOrEqualTo: Timestamp.fromDate(range.end))
          .limit(2000)
          .get();

      final docs = snapshot.docs;
      if (docs.isEmpty) return;

      final allData = <Map<String, double>>[];
      for (int i = 0; i < docs.length; i++) {
        final d = docs[i].data();
        allData.add({
          'index':    i.toDouble(),
          'humidity': (d['humidity'] as num).toDouble(),
        });
      }

      final values = allData.map((e) => e['humidity']!).toList();
      setState(() {
        _chartData.clear();
        _chartData.addAll(allData);
        _humidityMax      = values.reduce((a, b) => a > b ? a : b);
        _humidityMin      = values.reduce((a, b) => a < b ? a : b);
        _humidityAvg      = values.reduce((a, b) => a + b) / values.length;
        _liveReadingCount = 0;
        _liveHumiditySum  = 0;
      });
    } catch (e) {
      debugPrint('Firestore load error: $e');
    }
  }

  // ── ESP32 fetch ─────────────────────────────────────────────────────────────

  Future<void> _fetchData() async {
    try {
      final response = await http
          .get(Uri.parse("$kEsp32BaseUrl/data"))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final h    = (data['humidity'] as num).toDouble();

        setState(() {
          _humidity         = h;
          _failStreak       = 0;
          _connectionStatus = "Live";
          _isLoading        = false;

          _liveHumiditySum  += h;
          _liveReadingCount += 1;
          _humidityAvg = _liveHumiditySum / _liveReadingCount;

          if (_humidityMax == null || h > _humidityMax!) _humidityMax = h;
          if (_humidityMin == null || h < _humidityMin!) _humidityMin = h;

          // FIX #7: update session stats
          _sessionMax = _humidityMax;
          _sessionMin = _humidityMin;
          _sessionAvg = _humidityAvg;

          // FIX #3: only append live points on "Today"
          if (_isLiveRange) {
            _chartData.add({
              'index':    _chartData.length.toDouble(),
              'humidity': h,
            });
            // FIX #10: no reindex loop needed
            if (_chartData.length > 20) _chartData.removeAt(0);
          }
        });

        await _saveToFirestore(h);
      }
    } catch (_) {
      setState(() {
        _failStreak++;
        // FIX #13: require 4 failures before showing "No connection"
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
    setState(() => _isSprinklerLoading = true); // FIX #12
    try {
      final state    = turnOn ? "on" : "off";
      final response = await http
          .get(Uri.parse("$kEsp32BaseUrl/sprinkler?state=$state"))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        setState(() => _isActivated = turnOn);
      } else {
        _showSnackBar("Sprinkler request failed (${response.statusCode})");
      }
    } catch (_) {
      _showSnackBar("Failed to control sprinkler");
    } finally {
      setState(() => _isSprinklerLoading = false);
    }
  }

  void _showSnackBar(String msg) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  Future<void> _confirmSprinkler() async {
    if (_isSprinklerLoading) return;
    final action    = _isActivated ? 'Deactivate' : 'Activate';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$action Sprinkler?'),
        content: Text(_isActivated
            ? 'Are you sure you want to turn the sprinkler off?'
            : 'Are you sure you want to turn the sprinkler on?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _isActivated ? const Color(0xFFD32F2F) : Colors.green,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(action, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _toggleSprinkler(!_isActivated);
  }

  // ── Custom range picker ─────────────────────────────────────────────────────

  Future<void> _showCustomRangePicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CustomRangeSheet(
        initialStart: _customStart,
        initialEnd:   _customEnd,
        onApply: (start, end) {
          setState(() {
            _customStart       = start;
            _customEnd         = end;
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
                _buildStatusCard(),
                const SizedBox(height: 12),
                _buildTimeRangeSelector(),
                if (_selectedTimeRange == 3 &&
                    _customStart != null &&
                    _customEnd != null) ...[
                  const SizedBox(height: 8),
                  _buildCustomRangeBanner(),
                ],
                const SizedBox(height: 16),
                _buildChart(),
                const SizedBox(height: 16),
                _buildHumidityReview(),
                const SizedBox(height: 16),
                _buildInsights(),
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
    final color  = isDark ? Colors.white : Colors.black;
    return Row(children: [
      Icon(Icons.water_drop_outlined, size: 32, color: color),
      const SizedBox(width: 12),
      Text('Humidity',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
              color: color)),
      const Spacer(),
      _buildConnectionBadge(),
    ]);
  }

  Widget _buildConnectionBadge() {
    final Color badgeColor;
    final Color bgColor;
    if (_connectionStatus == "Live") {
      badgeColor = Colors.green;
      bgColor    = Colors.green.shade100;
    } else if (_connectionStatus == "Reconnecting...") {
      badgeColor = Colors.orange;
      bgColor    = Colors.orange.shade100;
    } else {
      badgeColor = Colors.red;
      bgColor    = Colors.red.shade100;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: bgColor, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.circle, size: 8, color: badgeColor),
        const SizedBox(width: 4),
        Text(_connectionStatus,
            style: TextStyle(fontSize: 11, color: badgeColor)),
      ]),
    );
  }

  Widget _buildStatusCard() {
    final humLabel = _humidity != null
        ? '${_humidity!.toStringAsFixed(1)}%' : '--';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_humidityStatus,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            const SizedBox(height: 4),
            _isLoading
                ? const CircularProgressIndicator()
                : Text(humLabel,
                    style: const TextStyle(fontSize: 40,
                        fontWeight: FontWeight.bold, color: Colors.black)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            const SizedBox(height: 10),
            // FIX #12: loading indicator while request is in flight
            GestureDetector(
              onTap: _isSprinklerLoading ? null : _confirmSprinkler,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: _isSprinklerLoading
                      ? Colors.grey.shade400
                      : _isActivated
                          ? Colors.green
                          : const Color(0xFFD32F2F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: _isSprinklerLoading
                    ? const SizedBox(
                        width: 18, height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_isActivated ? Icons.check_circle : Icons.shower,
                            color: Colors.white, size: 18),
                        const SizedBox(width: 6),
                        Text(_isActivated ? 'Active' : 'Activate',
                            style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.bold, fontSize: 14)),
                      ]),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildTimeRangeSelector() {
    return Row(
      children: List.generate(kTimeRanges.length, (index) {
        final isSelected = _selectedTimeRange == index;
        final isCustom   = index == 3;
        return Expanded(
          child: GestureDetector(
            onTap: () async {
              // FIX #2: always update state before opening sheet
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
                  right: index < kTimeRanges.length - 1 ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE8622A) : Colors.white,
                border: Border.all(
                  color: isCustom && !isSelected
                      ? const Color(0xFFE8622A).withValues(alpha: 0.5)
                      : isSelected
                          ? const Color(0xFFE8622A)
                          : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isCustom) ...[
                    Icon(Icons.calendar_month_outlined, size: 11,
                        color: isSelected
                            ? Colors.white : const Color(0xFFE8622A)),
                    const SizedBox(width: 3),
                  ],
                  Text(kTimeRanges[index],
                      style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : isCustom
                                  ? const Color(0xFFE8622A)
                                  : Colors.grey.shade600,
                          fontSize: 11,
                          fontWeight: isSelected || isCustom
                              ? FontWeight.bold : FontWeight.normal)),
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
            color: const Color(0xFFE8622A).withValues(alpha: 0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.schedule, size: 14, color: Color(0xFFE8622A)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${_formatDateTime(_customStart!)}  →  ${_formatDateTime(_customEnd!)}',
            style: const TextStyle(fontSize: 11, color: Color(0xFFE8622A),
                fontWeight: FontWeight.w500),
          ),
        ),
        // FIX #14: clear button to reset custom range
        GestureDetector(
          onTap: () {
            setState(() {
              _customStart       = null;
              _customEnd         = null;
              _selectedTimeRange = 2;
            });
            _loadChartFromFirestore();
          },
          child: const Icon(Icons.close, size: 14, color: Color(0xFFE8622A)),
        ),
      ]),
    );
  }

  Widget _buildChart() {
    return SizedBox(
      height: 200,
      width: double.infinity,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chartData.isEmpty
              ? const Center(
                  child: Text("No data for selected range",
                      style: TextStyle(color: Colors.grey)))
              : ClipRect(
                  child: CustomPaint(
                    painter: _HumidityChartPainter(data: List.from(_chartData)),
                    child: const SizedBox(height: 200, width: double.infinity),
                  ),
                ),
    );
  }

  Widget _buildHumidityReview() {
    final avgLabel = _humidityAvg != null
        ? '${_humidityAvg!.toStringAsFixed(1)}%' : '--';
    final minLabel = _humidityMin != null
        ? '${_humidityMin!.toStringAsFixed(1)}%' : '--';
    final maxLabel = _humidityMax != null
        ? '${_humidityMax!.toStringAsFixed(1)}%' : '--';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.water_drop_outlined, color: Color(0xFF1B3A4B), size: 20),
          SizedBox(width: 8),
          Text('Humidity Review',
              style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 15, color: Color(0xFF1B3A4B))),
        ]),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(children: [
            _buildReviewStat('Average', avgLabel, const Color(0xFFE8622A)),
            VerticalDivider(color: Colors.grey.shade300, thickness: 1),
            _buildReviewStat('Lowest',  minLabel, const Color(0xFF1B3A4B)),
            VerticalDivider(color: Colors.grey.shade300, thickness: 1),
            _buildReviewStat('Highest', maxLabel, Colors.red),
          ]),
        ),
      ]),
    );
  }

  Widget _buildReviewStat(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(children: [
        Text(label,
            style: TextStyle(color: valueColor, fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Text(value,
            style: const TextStyle(fontSize: 22,
                fontWeight: FontWeight.bold, color: Color(0xFF1B3A4B))),
      ]),
    );
  }

  Widget _buildInsights() {
    final h   = _humidity;
    final avg = _humidityAvg;
    String insight = 'No data available yet.';
    if (h != null && avg != null) {
      if (h > 80) {
        insight = 'Humidity is too high (${h.toStringAsFixed(1)}%). '
            'This may encourage mold growth — consider ventilating.';
      } else if (h < 40) {
        insight = 'Humidity is too low (${h.toStringAsFixed(1)}%). '
            'Plants may be stressed — consider activating the sprinkler.';
      } else {
        insight = 'Humidity is within the ideal range. '
            'Average is ${avg.toStringAsFixed(1)}% — no action needed.';
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9C4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [
          Icon(Icons.lightbulb_outline, color: Color(0xFFE8A020), size: 20),
          SizedBox(width: 8),
          Text('Insights:', style: TextStyle(fontWeight: FontWeight.bold,
              fontSize: 15, color: Color(0xFF1B3A4B))),
        ]),
        const SizedBox(height: 8),
        Text(insight,
            style: const TextStyle(fontSize: 13, color: Color(0xFF1B3A4B))),
      ]),
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
  late DateTime  _startDate;
  late TimeOfDay _startTime;
  late DateTime  _endDate;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();
    final now  = DateTime.now();
    _startDate = widget.initialStart ?? now;
    _startTime = TimeOfDay.fromDateTime(widget.initialStart ?? now);
    _endDate   = widget.initialEnd   ?? now;
    _endTime   = TimeOfDay.fromDateTime(widget.initialEnd   ?? now);
  }

  DateTime get _fullStart => DateTime(_startDate.year, _startDate.month,
      _startDate.day, _startTime.hour, _startTime.minute);
  DateTime get _fullEnd => DateTime(_endDate.year, _endDate.month,
      _endDate.day, _endTime.hour, _endTime.minute);
  bool get _isValid => _fullStart.isBefore(_fullEnd);

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: Color(0xFFE8622A))),
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
              colorScheme: const ColorScheme.light(primary: Color(0xFFE8622A))),
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
        left: 24, right: 24, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Icon(Icons.date_range, color: Color(0xFFE8622A), size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text('Custom Date Range',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold,
                      color: Color(0xFF1B3A4B))),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Icon(Icons.close, color: Colors.grey.shade400, size: 22),
            ),
          ]),
          const SizedBox(height: 20),
          _rowLabel('From'),
          const SizedBox(height: 8),
          Row(children: [
            _DateTimeChip(icon: Icons.calendar_today_outlined,
                label: _formatDate(_startDate), onTap: () => _pickDate(true)),
            const SizedBox(width: 8),
            _DateTimeChip(icon: Icons.access_time,
                label: _formatTime(_startTime), onTap: () => _pickTime(true)),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Divider(color: Colors.grey.shade200)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Icon(Icons.arrow_downward,
                  size: 16, color: Colors.grey.shade400),
            ),
            Expanded(child: Divider(color: Colors.grey.shade200)),
          ]),
          const SizedBox(height: 12),
          _rowLabel('To'),
          const SizedBox(height: 8),
          Row(children: [
            _DateTimeChip(icon: Icons.calendar_today_outlined,
                label: _formatDate(_endDate), onTap: () => _pickDate(false)),
            const SizedBox(width: 8),
            _DateTimeChip(icon: Icons.access_time,
                label: _formatTime(_endTime), onTap: () => _pickTime(false)),
          ]),
          if (!_isValid) ...[
            const SizedBox(height: 10),
            const Row(children: [
              Icon(Icons.error_outline, size: 14, color: Colors.red),
              SizedBox(width: 4),
              Text('Start must be before end.',
                  style: TextStyle(color: Colors.red, fontSize: 12)),
            ]),
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
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Apply Range',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowLabel(String text) => Text(text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
          color: Colors.grey.shade500, letterSpacing: 0.5));
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
                color: const Color(0xFFE8622A).withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(icon, size: 14, color: const Color(0xFFE8622A)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 12,
                      fontWeight: FontWeight.w600, color: Color(0xFF1B3A4B)),
                  overflow: TextOverflow.ellipsis),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Chart painter ─────────────────────────────────────────────────────────────

class _HumidityChartPainter extends CustomPainter {
  final List<Map<String, double>> data;
  _HumidityChartPainter({required this.data});

  List<Map<String, double>> _sampleData(
      List<Map<String, double>> src, int maxPts, String key) {
    if (src.length <= maxPts) return src;
    final result = <Map<String, double>>[];
    final step   = src.length / maxPts;
    for (int i = 0; i < maxPts; i++) {
      final start  = (i * step).floor();
      final end    = ((i + 1) * step).floor().clamp(0, src.length);
      if (start >= src.length) break;
      final bucket = src.sublist(start, end);
      final avg    = bucket.map((e) => e[key]!).reduce((a, b) => a + b) /
          bucket.length;
      result.add({'index': i.toDouble(), key: avg});
    }
    return result;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    const double leftPadding   = 48;
    const double bottomPadding = 36;
    const double topPadding    = 8;
    final double chartWidth    = size.width - leftPadding;
    final double chartHeight   = size.height - bottomPadding - topPadding;
    if (chartWidth <= 0 || chartHeight <= 0) return;
    const yMax = 100.0;
    const yMin = 0.0;

    final gridPaint = Paint()..color = Colors.grey.shade200..strokeWidth = 1;
    final axisPaint = Paint()..color = Colors.grey.shade300..strokeWidth = 1;

    for (final step in [0, 25, 50, 75, 100]) {
      final y = topPadding + chartHeight -
          ((step - yMin) / (yMax - yMin)) * chartHeight;
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '$step%',
            style: TextStyle(color: Colors.grey.shade500, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    canvas.drawLine(Offset(leftPadding, topPadding),
        Offset(leftPadding, topPadding + chartHeight), axisPaint);
    canvas.drawLine(Offset(leftPadding, topPadding + chartHeight),
        Offset(size.width, topPadding + chartHeight), axisPaint);

    if (data.length < 2) return;

    final sampled = _sampleData(data, 80, 'humidity');
    final xMin    = sampled.first['index']!;
    final xMax    = sampled.last['index']!;
    if (xMax == xMin) return;

    double getX(double i) =>
        leftPadding + ((i - xMin) / (xMax - xMin)) * chartWidth;
    double getY(double h) =>
        topPadding + chartHeight -
            ((h.clamp(yMin, yMax) - yMin) / (yMax - yMin)) * chartHeight;

    final fillPath = Path();
    final linePath = Path();
    final firstX   = getX(sampled.first['index']!);
    final firstY   = getY(sampled.first['humidity']!);

    fillPath.moveTo(firstX, topPadding + chartHeight);
    fillPath.lineTo(firstX, firstY);
    linePath.moveTo(firstX, firstY);

    for (int i = 0; i < sampled.length - 1; i++) {
      final x0 = getX(sampled[i]['index']!);
      final y0 = getY(sampled[i]['humidity']!);
      final x1 = getX(sampled[i + 1]['index']!);
      final y1 = getY(sampled[i + 1]['humidity']!);
      if (x0.isNaN || y0.isNaN || x1.isNaN || y1.isNaN) continue;
      final cpX1 = x0 + (x1 - x0) * 0.5;
      final cpX2 = x1 - (x1 - x0) * 0.5;
      fillPath.cubicTo(cpX1, y0, cpX2, y1, x1, y1);
      linePath.cubicTo(cpX1, y0, cpX2, y1, x1, y1);
    }

    final lastX = getX(sampled.last['index']!);
    fillPath.lineTo(lastX, topPadding + chartHeight);
    fillPath.close();

    canvas.drawPath(fillPath, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFFEF5350).withValues(alpha: 0.85),
          const Color(0xFFEF5350).withValues(alpha: 0.15),
        ],
      ).createShader(Rect.fromLTWH(0, topPadding, size.width, chartHeight))
      ..style = PaintingStyle.fill);

    canvas.drawPath(linePath, Paint()
      ..color = const Color(0xFFC62828)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(covariant _HumidityChartPainter old) =>
      old.data.length != data.length ||
      (data.isNotEmpty &&
          old.data.last['humidity'] != data.last['humidity']);
}