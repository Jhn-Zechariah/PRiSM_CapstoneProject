import 'package:flutter/material.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import '../../../../core/widgets/build_tab_bar.dart';

class HumidityMonitoring extends StatefulWidget {
  final VoidCallback? onSwitchToTemperature;
  const HumidityMonitoring({super.key, this.onSwitchToTemperature});

  @override
  State<HumidityMonitoring> createState() => _HumidityMonitoringState();
}

class _HumidityMonitoringState extends State<HumidityMonitoring> {
  // ignore: prefer_final_fields
  int _selectedTab = 1;
  int _selectedTimeRange = 3;
  bool _isActivated = false;

  final List<String> _timeRanges = [
    'All Time',
    'This Month',
    'This Week',
    'Today',
  ];

  final List<Map<String, double>> _chartData = [
    {'hour': 7.0, 'humidity': 10.0},
    {'hour': 7.5, 'humidity': 13.0},
    {'hour': 8.0, 'humidity': 16.0},
    {'hour': 8.5, 'humidity': 14.0},
    {'hour': 9.0, 'humidity': 22.0},
    {'hour': 9.5, 'humidity': 28.0},
    {'hour': 10.0, 'humidity': 26.0},
    {'hour': 10.5, 'humidity': 24.0},
    {'hour': 11.0, 'humidity': 27.0},
    {'hour': 11.5, 'humidity': 30.0},
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: AppTopBar(),
          ),
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
                    setState(() {
                      _selectedTab = index;
                    });

                    if (index == 0) {
                      widget.onSwitchToTemperature?.call();
                    }
                  },
                ),
                const SizedBox(height: 16),
                _buildStatusCard(),
                const SizedBox(height: 12),
                _buildTimeRangeSelector(),
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(
          Icons.water_drop_outlined,
          size: 32,
          color: isDarkMode ? Colors.white : Colors.black,
        ),
        const SizedBox(width: 12),
        Text(
          'Humidity',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w900,
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        const Spacer(),
      ],
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Normal',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
              const SizedBox(height: 4),
              const Text(
                '35%',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Mon 08-30',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _isActivated = !_isActivated),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _isActivated
                        ? Colors.green
                        : const Color(0xFFD32F2F),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _isActivated ? Icons.check_circle : Icons.shower,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _isActivated ? 'Active' : 'Activate',
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
            ],
          ),
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
            onTap: () => setState(() => _selectedTimeRange = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(
                right: index < _timeRanges.length - 1 ? 6 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE8622A) : Colors.white,
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFFE8622A)
                      : Colors.grey.shade300,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                _timeRanges[index],
                style: TextStyle(
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildChart() {
    return Container(
      height: 200,
      padding: const EdgeInsets.only(left: 8, right: 8, top: 8),
      child: CustomPaint(
        painter: HumidityChartPainter(data: _chartData),
        size: const Size(double.infinity, 200),
      ),
    );
  }

  Widget _buildHumidityReview() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.water_drop_outlined,
                color: Color(0xFF1B3A4B),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Humidity Review',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF1B3A4B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              children: [
                _buildReviewStat('Average', '35%', const Color(0xFFE8622A)),
                VerticalDivider(color: Colors.grey.shade300, thickness: 1),
                _buildReviewStat('Lowest', '32%', const Color(0xFF1B3A4B)),
                VerticalDivider(color: Colors.grey.shade300, thickness: 1),
                _buildReviewStat('Highest', '40%', Colors.red),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewStat(String label, String value, Color valueColor) {
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
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1B3A4B),
            ),
          ),
        ],
      ),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, color: Color(0xFFE8A020), size: 20),
              SizedBox(width: 8),
              Text(
                'Insights:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Color(0xFF1B3A4B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

class HumidityChartPainter extends CustomPainter {
  final List<Map<String, double>> data;
  HumidityChartPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    const double leftPadding = 48;
    const double bottomPadding = 36;
    const double topPadding = 8;
    final double chartWidth = size.width - leftPadding;
    final double chartHeight = size.height - bottomPadding - topPadding;

    final gridPaint = Paint()
      ..color = Colors.grey.shade200
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 1;

    const yMax = 30.0;
    const yMin = 0.0;
    for (final step in [0, 5, 10, 15, 20, 25, 30]) {
      final y =
          topPadding +
          chartHeight -
          ((step - yMin) / (yMax - yMin)) * chartHeight;
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '$step° C',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    final xMin = data.first['hour']!;
    final xMax = data.last['hour']!;
    for (final hour in [7.0, 8.0, 9.0, 10.0, 11.0]) {
      final x = leftPadding + ((hour - xMin) / (xMax - xMin)) * chartWidth;
      final tp = TextPainter(
        text: TextSpan(
          text: '${hour.toInt()}:00 AM',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x - tp.width / 2, size.height - bottomPadding + 8),
      );
    }

    Path fillPath = Path();
    Path linePath = Path();
    for (int i = 0; i < data.length; i++) {
      final x =
          leftPadding +
          ((data[i]['hour']! - xMin) / (xMax - xMin)) * chartWidth;
      final y =
          topPadding +
          chartHeight -
          ((data[i]['humidity']! - yMin) / (yMax - yMin)) * chartHeight;
      if (i == 0) {
        fillPath.moveTo(x, topPadding + chartHeight);
        fillPath.lineTo(x, y);
        linePath.moveTo(x, y);
      } else {
        final prevX =
            leftPadding +
            ((data[i - 1]['hour']! - xMin) / (xMax - xMin)) * chartWidth;
        final prevY =
            topPadding +
            chartHeight -
            ((data[i - 1]['humidity']! - yMin) / (yMax - yMin)) * chartHeight;
        final cpX = (prevX + x) / 2;
        fillPath.cubicTo(cpX, prevY, cpX, y, x, y);
        linePath.cubicTo(cpX, prevY, cpX, y, x, y);
      }
    }
    final lastX =
        leftPadding +
        ((data.last['hour']! - xMin) / (xMax - xMin)) * chartWidth;
    fillPath.lineTo(lastX, topPadding + chartHeight);
    fillPath.close();

    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFEF5350).withValues(alpha: 0.6),
            const Color(0xFFEF5350).withValues(alpha: 0.05),
          ],
        ).createShader(Rect.fromLTWH(0, topPadding, size.width, chartHeight))
        ..style = PaintingStyle.fill,
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = const Color(0xFFEF5350)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );

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
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
