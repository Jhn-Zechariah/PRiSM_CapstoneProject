import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import '../../../../core/widgets/build_tab_bar.dart';
import '../../../../core/widgets/header.dart';
import '../cubits/temperature_monitoring_cubit.dart';
import '../cubits/temperature_monitoring_states.dart';

class TemperatureMonitoring extends StatelessWidget {
  final VoidCallback? onSwitchToHumidity;

  const TemperatureMonitoring({super.key, this.onSwitchToHumidity});

  @override
  Widget build(BuildContext context) {
    final List<String> timeRanges = ['All Time', 'This Month', 'This Week', 'Today'];

    return BlocBuilder<TemperatureMonitoringCubit, TemperatureMonitoringState>(
      builder: (context, state) {
        if (state is TemperatureInitial) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        final activeState = state as TemperatureMonitorActive;

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: AppTopBar(),
              ),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomFeatureHeader(
                      title: 'Temperature',
                      icon: Icons.thermostat,
                    ),
                    const SizedBox(height: 16),
                    CustomTabBar(
                      selectedIndex: 0,
                      tabs: const ['Temperature', 'Humidity'],
                      onTabSelected: (index) {
                        if (index == 1) onSwitchToHumidity?.call();
                      },
                    ),
                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: activeState.connectionStatus == "Live"
                                ? Colors.green
                                : Colors.amber,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          activeState.connectionStatus,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    _buildStatusCard(activeState, context),
                    const SizedBox(height: 12),
                    _buildTimeRangeSelector(activeState, timeRanges, context),
                    const SizedBox(height: 16),
                    _buildChart(activeState),
                    const SizedBox(height: 16),
                    _buildTemperatureReview(activeState),
                    const SizedBox(height: 16),
                    _buildInsights(),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusCard(TemperatureMonitorActive state, BuildContext context) {
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
          )
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
                state.tempStatus,
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                '${state.tempMax.toStringAsFixed(1)}°C',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: state.tempMax >= 40.5 ? Colors.red : Colors.black,
                ),
              ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${DateTime.now().day}-${DateTime.now().month}-${DateTime.now().year}',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => context.read<TemperatureMonitoringCubit>().toggleSprinkler(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: state.isSprinklerActivated ? Colors.green : const Color(0xFFD32F2F),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state.isSprinklerActivated ? Icons.check_circle : Icons.shower,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        state.isSprinklerActivated ? 'Active' : 'Activate',
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

  Widget _buildTimeRangeSelector(TemperatureMonitorActive state, List<String> timeRanges, BuildContext context) {
    return Row(
      children: List.generate(timeRanges.length, (index) {
        final isSelected = state.selectedTimeRangeIndex == index;
        return Expanded(
          child: GestureDetector(
            onTap: () => context.read<TemperatureMonitoringCubit>().changeTimeRange(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(right: index < timeRanges.length - 1 ? 6 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFFE8622A) : Colors.white,
                border: Border.all(color: isSelected ? const Color(0xFFE8622A) : Colors.grey.shade300),
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                timeRanges[index],
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

  Widget _buildChart(TemperatureMonitorActive state) {
    return SizedBox(
      height: 200,
      width: double.infinity,
      child: state.chartPoints.isEmpty
          ? const Center(
        child: Text(
          "Waiting for historical data sync...",
          style: TextStyle(color: Colors.grey),
        ),
      )
          : ClipRect(
        child: CustomPaint(
          painter: TemperatureChartPainter(data: List.from(state.chartPoints)),
          child: const SizedBox(height: 200, width: double.infinity),
        ),
      ),
    );
  }

  Widget _buildTemperatureReview(TemperatureMonitorActive state) {
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
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.thermostat, color: Color(0xFF1B3A4B), size: 20),
              SizedBox(width: 8),
              Text(
                'Temperature Review',
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
                _buildReviewStat('Average', '${state.tempAvg.toStringAsFixed(1)}°C', const Color(0xFFE8622A)),
                VerticalDivider(color: Colors.grey.shade300, thickness: 1),
                _buildReviewStat('Lowest', '${state.tempMin.toStringAsFixed(1)}°C', const Color(0xFF1B3A4B)),
                VerticalDivider(color: Colors.grey.shade300, thickness: 1),
                _buildReviewStat('Highest', '${state.tempMax.toStringAsFixed(1)}°C', Colors.red),
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
            style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black),
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
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ── CUSTOM CHART PAINTER ───────────────────────────────────────────
class TemperatureChartPainter extends CustomPainter {
  final List<Map<String, double>> data;
  TemperatureChartPainter({required this.data});

  List<Map<String, double>> _sampleData(List<Map<String, double>> data, int maxPoints, String key) {
    if (data.length <= maxPoints) return data;
    final List<Map<String, double>> result = [];
    final double step = data.length / maxPoints;
    for (int i = 0; i < maxPoints; i++) {
      final int start = (i * step).floor();
      final int end = ((i + 1) * step).floor().clamp(0, data.length);
      if (start >= data.length) break;
      final bucket = data.sublist(start, end);
      final avg = bucket.map((e) => e[key]!).reduce((a, b) => a + b) / bucket.length;
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
      final y = topPadding + chartHeight - ((step - yMin) / (yMax - yMin)) * chartHeight;
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '$step°C',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    canvas.drawLine(Offset(leftPadding, topPadding), Offset(leftPadding, topPadding + chartHeight), axisPaint);
    canvas.drawLine(Offset(leftPadding, topPadding + chartHeight), Offset(size.width, topPadding + chartHeight), axisPaint);

    if (data.length < 2) return;

    final sampled = _sampleData(data, 80, 'temp');

    final xMin = sampled.first['index']!;
    final xMax = sampled.last['index']!;
    if (xMax == xMin) return;

    double getX(double i) => leftPadding + ((i - xMin) / (xMax - xMin)) * chartWidth;
    double getY(double t) => topPadding + chartHeight - ((t.clamp(yMin, yMax) - yMin) / (yMax - yMin)) * chartHeight;

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
        ).createShader(Rect.fromLTWH(0, topPadding, size.width, chartHeight))
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