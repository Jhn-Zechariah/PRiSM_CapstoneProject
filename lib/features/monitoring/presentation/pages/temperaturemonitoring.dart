import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import '../../../../core/widgets/build_tab_bar.dart';
import '../../../../core/widgets/header.dart';

const String esp32Ip = "192.168.1.100";

class TemperatureMonitoring extends StatefulWidget {
  final VoidCallback? onSwitchToHumidity;
  const TemperatureMonitoring({super.key, this.onSwitchToHumidity});

  @override
  State<TemperatureMonitoring> createState() => _TemperatureMonitoringState();
}

class _TemperatureMonitoringState extends State<TemperatureMonitoring> {
  int _selectedTab       = 0;
  int _selectedTimeRange = 3;
  bool _isActivated      = false;
  bool _isLoading        = true;
  String _connectionStatus = "Connecting...";

  double _tempMax    = 0;
  double _tempAvg    = 0;
  double _tempMin    = 0;
  String _tempStatus = "Normal";

  final List<Map<String, double>> _chartData = [];
  Timer? _timer;

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  final List<String> _timeRanges = [
    'All Time', 'This Month', 'This Week', 'Today',
  ];

  @override
  void initState() {
    super.initState();
    _fetchData();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _saveToFirestore(
      double max, double avg, double min, String status) async {
    try {
      await _db.collection('temperature_readings').add({
        'tempMax':    max,
        'tempAvg':    avg,
        'tempMin':    min,
        'tempStatus': status,
        'timestamp':  FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('Firestore save error: $e');
    }
  }

  Future<void> _loadChartFromFirestore() async {
    final now = DateTime.now();
    DateTime? startDate;

    switch (_selectedTimeRange) {
      case 0:
        startDate = null;
        break;
      case 1:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case 2:
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        startDate = DateTime(weekStart.year, weekStart.month, weekStart.day);
        break;
      case 3:
        startDate = DateTime(now.year, now.month, now.day);
        break;
      default:
        startDate = null;
    }

    try {
      Query query = _db
          .collection('temperature_readings')
          .orderBy('timestamp', descending: false);

      if (startDate != null) {
        query = query.where('timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startDate));
      }

      final snapshot = await query.get();
      final docs = snapshot.docs;

      if (docs.isEmpty) return;

      List<Map<String, double>> allData = [];
      for (int i = 0; i < docs.length; i++) {
        final d = docs[i].data() as Map<String, dynamic>;
        allData.add({
          'index': i.toDouble(),
          'temp':  (d['tempMax'] as num).toDouble(),
        });
      }

      setState(() {
        _chartData.clear();
        _chartData.addAll(allData);

        final temps = allData.map((e) => e['temp']!).toList();
        _tempMax = temps.reduce((a, b) => a > b ? a : b);
        _tempMin = temps.reduce((a, b) => a < b ? a : b);
        _tempAvg = temps.reduce((a, b) => a + b) / temps.length;
      });
    } catch (e) {
      debugPrint('Firestore load error: $e');
    }
  }

  Future<void> _fetchData() async {
    try {
      final response = await http
          .get(Uri.parse("http://$esp32Ip/data"))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final max    = (data['tempMax']    as num).toDouble();
        final avg    = (data['tempAvg']    as num).toDouble();
        final min    = (data['tempMin']    as num).toDouble();
        final status = data['tempStatus'] ?? "Normal";

        setState(() {
          _tempMax    = max;
          _tempAvg    = avg;
          _tempMin    = min;
          _tempStatus = status;
          _isLoading  = false;
          _connectionStatus = "Live";

          _chartData.add({
            'index': _chartData.length.toDouble(),
            'temp':  max,
          });

          if (_chartData.length > 20) {
            _chartData.removeAt(0);
            for (int i = 0; i < _chartData.length; i++) {
              _chartData[i] = {
                'index': i.toDouble(),
                'temp':  _chartData[i]['temp']!,
              };
            }
          }
        });

        await _saveToFirestore(max, avg, min, status);
      }
    } catch (e) {
      setState(() {
        _connectionStatus = "No connection";
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleSprinkler(bool turnOn) async {
    try {
      final state = turnOn ? "on" : "off";
      final response = await http
          .get(Uri.parse("http://$esp32Ip/sprinkler?state=$state"))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        setState(() => _isActivated = turnOn);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Failed to control sprinkler")),
      );
    }
  }

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
                CustomFeatureHeader(
                  title: 'Temperature',
                  icon:  Icons.thermostat,
                ),
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
                _buildStatusCard(),
                const SizedBox(height: 12),
                _buildTimeRangeSelector(),
                const SizedBox(height: 16),
                _buildChart(),
                const SizedBox(height: 16),
                _buildTemperatureReview(),
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


  Widget _buildStatusCard() {
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
            Text(_tempStatus,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
            const SizedBox(height: 4),
            _isLoading
                ? const CircularProgressIndicator()
                : Text('${_tempMax.toStringAsFixed(1)}°C',
                style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold,
                    color: _tempMax >= 40.5 ? Colors.red : Colors.black)),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(
              '${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _toggleSprinkler(!_isActivated),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  color: _isActivated
                      ? Colors.green : const Color(0xFFD32F2F),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
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
      children: List.generate(_timeRanges.length, (index) {
        final isSelected = _selectedTimeRange == index;
        return Expanded(
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedTimeRange = index);
              _loadChartFromFirestore();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(
                  right: index < _timeRanges.length - 1 ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFFE8622A) : Colors.white,
                border: Border.all(color: isSelected
                    ? const Color(0xFFE8622A) : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(_timeRanges[index],
                  style: TextStyle(
                      color: isSelected
                          ? Colors.white : Colors.grey.shade600,
                      fontSize: 11,
                      fontWeight: isSelected
                          ? FontWeight.bold : FontWeight.normal)),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildChart() {
    return SizedBox(
      height: 200,
      width: double.infinity,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chartData.isEmpty
              ? const Center(child: Text("Waiting for data...",
                  style: TextStyle(color: Colors.grey)))
              : ClipRect(
                  child: CustomPaint(
                    painter: TemperatureChartPainter(
                        data: List.from(_chartData)),
                    child: const SizedBox(
                        height: 200, width: double.infinity),
                  ),
                ),
    );
  }

  Widget _buildTemperatureReview() {
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
          Icon(Icons.thermostat, color: Color(0xFF1B3A4B), size: 20),
          SizedBox(width: 8),
          Text('Temperature Review',
              style: TextStyle(fontWeight: FontWeight.bold,
                  fontSize: 15, color: Color(0xFF1B3A4B))),
        ]),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(children: [
            _buildReviewStat('Average',
                '${_tempAvg.toStringAsFixed(1)}°C',
                const Color(0xFFE8622A)),
            VerticalDivider(color: Colors.grey.shade300, thickness: 1),
            _buildReviewStat('Lowest',
                '${_tempMin.toStringAsFixed(1)}°C',
                const Color(0xFF1B3A4B)),
            VerticalDivider(color: Colors.grey.shade300, thickness: 1),
            _buildReviewStat('Highest',
                '${_tempMax.toStringAsFixed(1)}°C', Colors.red),
          ]),
        ),
      ]),
    );
  }

  Widget _buildReviewStat(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(children: [
        Text(label, style: TextStyle(color: valueColor, fontSize: 13,
            fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        Text(value, style: const TextStyle(fontSize: 22,
            fontWeight: FontWeight.bold, color: Colors.black)),
      ]),
    );
  }

  Widget _buildInsights() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF9C4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.lightbulb_outline,
                color: Color(0xFFE8A020), size: 20),
            SizedBox(width: 8),
            Text('Insights:', style: TextStyle(fontWeight: FontWeight.bold,
                fontSize: 15, color: Color(0xFF1B3A4B))),
          ]),
          SizedBox(height: 12),
        ],
      ),
    );
  }
}

class TemperatureChartPainter extends CustomPainter {
  final List<Map<String, double>> data;
  TemperatureChartPainter({required this.data});

  List<Map<String, double>> _sampleData(
      List<Map<String, double>> data, int maxPoints, String key) {
    if (data.length <= maxPoints) return data;
    final List<Map<String, double>> result = [];
    final double step = data.length / maxPoints;
    for (int i = 0; i < maxPoints; i++) {
      final int start = (i * step).floor();
      final int end = ((i + 1) * step).floor().clamp(0, data.length);
      if (start >= data.length) break;
      final bucket = data.sublist(start, end);
      final avg = bucket.map((e) => e[key]!).reduce((a, b) => a + b) /
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
    const yMax = 45.0;
    const yMin = 25.0;

    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    for (final step in [25, 30, 35, 40, 45]) {
      final y = topPadding + chartHeight -
          ((step - yMin) / (yMax - yMin)) * chartHeight;
      canvas.drawLine(
          Offset(leftPadding, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(text: '$step°C',
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

    final sampled = _sampleData(data, 80, 'temp');

    final xMin = sampled.first['index']!;
    final xMax = sampled.last['index']!;
    if (xMax == xMin) return;

    double getX(double i) =>
        leftPadding + ((i - xMin) / (xMax - xMin)) * chartWidth;
    double getY(double t) =>
        topPadding + chartHeight -
            ((t.clamp(yMin, yMax) - yMin) / (yMax - yMin)) * chartHeight;

    Path fillPath = Path();
    Path linePath = Path();

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
        ).createShader(
            Rect.fromLTWH(0, topPadding, size.width, chartHeight))
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = const Color(0xFF2E7D32)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}