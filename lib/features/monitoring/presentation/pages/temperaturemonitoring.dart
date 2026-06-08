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

  // ── THEME HELPERS ──────────────────────────────────────────────────
  static const Color _accent = Color(0xFFE8622A);

  Color _cardBg(bool isDark) => isDark ? const Color(0xFF1E1E1E) : Colors.white;

  Color _surfaceBg(bool isDark) =>
      isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5);

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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final List<String> timeRanges = [
      'All Time',
      'This Month',
      'This Week',
      'Today',
    ];

    return BlocBuilder<TemperatureMonitoringCubit, TemperatureMonitoringState>(
      builder: (context, state) {
        if (state is TemperatureInitial) {
          return Scaffold(
            backgroundColor: _surfaceBg(isDark),
            body: Center(child: CircularProgressIndicator(color: _accent)),
          );
        }

        final activeState = state as TemperatureMonitorActive;

        return SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(padding: EdgeInsets.all(16), child: AppTopBar()),
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
                    _buildConnectionBadge(activeState, isDark),
                    const SizedBox(height: 10),
                    _buildStatusCard(activeState, context, isDark),
                    const SizedBox(height: 12),
                    _buildTimeRangeSelector(
                      activeState,
                      timeRanges,
                      context,
                      isDark,
                    ),
                    const SizedBox(height: 16),
                    _buildChart(activeState, isDark),
                    const SizedBox(height: 16),
                    _buildTemperatureReview(activeState, isDark),
                    const SizedBox(height: 16),
                    _buildInsights(isDark),
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

  Widget _buildConnectionBadge(TemperatureMonitorActive state, bool isDark) {
    final isLive = state.connectionStatus == "Live";
    final dotColor = isLive ? Colors.green : Colors.amber;
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
        ),
        const SizedBox(width: 6),
        Text(
          state.connectionStatus,
          style: TextStyle(
            fontSize: 12,
            color: _textSecondary(isDark),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCard(
    TemperatureMonitorActive state,
    BuildContext context,
    bool isDark,
  ) {
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
                state.tempStatus,
                style: TextStyle(color: _textSecondary(isDark), fontSize: 13),
              ),
              const SizedBox(height: 4),
              Text(
                '${state.tempMax.toStringAsFixed(1)}°C',
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.bold,
                  color: state.tempMax >= 40.5
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
              GestureDetector(
                onTap: () => context
                    .read<TemperatureMonitoringCubit>()
                    .toggleSprinkler(),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: state.isSprinklerActivated
                        ? Colors.green
                        : const Color(0xFFD32F2F),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (state.isSprinklerActivated
                                    ? Colors.green
                                    : const Color(0xFFD32F2F))
                                .withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        state.isSprinklerActivated
                            ? Icons.check_circle
                            : Icons.shower,
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

  Widget _buildTimeRangeSelector(
    TemperatureMonitorActive state,
    List<String> timeRanges,
    BuildContext context,
    bool isDark,
  ) {
    return Row(
      children: List.generate(timeRanges.length, (index) {
        final isSelected = state.selectedTimeRangeIndex == index;
        return Expanded(
          child: GestureDetector(
            onTap: () => context
                .read<TemperatureMonitoringCubit>()
                .changeTimeRange(index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: EdgeInsets.only(
                right: index < timeRanges.length - 1 ? 6 : 0,
              ),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isSelected ? _accent : _cardBg(isDark),
                border: Border.all(
                  color: isSelected ? _accent : _dividerColor(isDark),
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              alignment: Alignment.center,
              child: Text(
                timeRanges[index],
                style: TextStyle(
                  color: isSelected ? Colors.white : _textSecondary(isDark),
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

  Widget _buildChart(TemperatureMonitorActive state, bool isDark) {
    return Container(
      decoration: _bentoCard(isDark, accentColor: Colors.green),
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: 200,
        width: double.infinity,
        child: state.chartPoints.isEmpty
            ? Center(
                child: Text(
                  "Waiting for historical data sync...",
                  style: TextStyle(color: _textSecondary(isDark)),
                ),
              )
            : ClipRect(
                child: CustomPaint(
                  painter: TemperatureChartPainter(
                    data: List.from(state.chartPoints),
                    isDark: isDark,
                  ),
                  child: const SizedBox(height: 200, width: double.infinity),
                ),
              ),
      ),
    );
  }

  Widget _buildTemperatureReview(TemperatureMonitorActive state, bool isDark) {
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
                  '${state.tempAvg.toStringAsFixed(1)}°C',
                  _accent,
                  isDark,
                ),
                VerticalDivider(color: _dividerColor(isDark), thickness: 1),
                _buildReviewStat(
                  'Lowest',
                  '${state.tempMin.toStringAsFixed(1)}°C',
                  const Color(0xFF1B3A4B),
                  isDark,
                ),
                VerticalDivider(color: _dividerColor(isDark), thickness: 1),
                _buildReviewStat(
                  'Highest',
                  '${state.tempMax.toStringAsFixed(1)}°C',
                  Colors.red,
                  isDark,
                ),
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
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ── CUSTOM CHART PAINTER ───────────────────────────────────────────
class TemperatureChartPainter extends CustomPainter {
  final List<Map<String, double>> data;
  final bool isDark;
  TemperatureChartPainter({required this.data, this.isDark = false});

  List<Map<String, double>> _sampleData(
    List<Map<String, double>> data,
    int maxPoints,
    String key,
  ) {
    if (data.length <= maxPoints) return data;
    final List<Map<String, double>> result = [];
    final double step = data.length / maxPoints;
    for (int i = 0; i < maxPoints; i++) {
      final int start = (i * step).floor();
      final int end = ((i + 1) * step).floor().clamp(0, data.length);
      if (start >= data.length) break;
      final bucket = data.sublist(start, end);
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
    const yMax = 45.0;
    const yMin = 25.0;

    final gridColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.grey.shade200;
    final axisColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.grey.shade300;
    final labelColor = isDark ? Colors.white38 : Colors.grey.shade500;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = axisColor
      ..strokeWidth = 1;

    for (final step in [25, 30, 35, 40, 45]) {
      final y =
          topPadding +
          chartHeight -
          ((step - yMin) / (yMax - yMin)) * chartHeight;
      canvas.drawLine(Offset(leftPadding, y), Offset(size.width, y), gridPaint);
      final tp = TextPainter(
        text: TextSpan(
          text: '$step°C',
          style: TextStyle(color: labelColor, fontSize: 10),
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

    // Fill gradient adapts to dark mode
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF4CAF50).withValues(alpha: isDark ? 0.5 : 0.85),
            const Color(0xFF4CAF50).withValues(alpha: 0.05),
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
