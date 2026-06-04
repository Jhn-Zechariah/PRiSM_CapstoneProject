import 'dart:async';
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../core/widgets/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../../core/widgets/text.dart';

const String esp32Ip = "192.168.1.100";

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int selectedIndex = 2;

  Timer? _timer;
  bool _isLoading = true;
  String _connectionStatus = "Connecting...";

  double _tempMax = 0;
  String _tempStatus = "Normal";
  bool _isActivated = false;

  String _sprinklerStatus = "OFF";
  String _lastActivated = "—";
  String _mode = "—";
  String _pigStatus = "—";

  @override
  void initState() {
    super.initState();
    _fetchData();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchData());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchData() async {
    try {
      final response = await http
          .get(Uri.parse("http://$esp32Ip/data"))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _tempMax = (data['tempMax'] as num?)?.toDouble() ?? _tempMax;
          _tempStatus = data['tempStatus'] as String? ?? _tempStatus;
          _isActivated = data['sprinkler'] as bool? ?? _isActivated;
          _sprinklerStatus = _isActivated ? "ON" : "OFF";
          _lastActivated = data['lastActivated'] as String? ?? _lastActivated;
          _mode = data['mode'] as String? ?? _mode;
          _pigStatus = data['pigStatus'] as String? ?? _pigStatus;
          _isLoading = false;
          _connectionStatus = "Live";
        });
      }
    } catch (_) {
      if (!mounted) return;
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
        setState(() {
          _isActivated = turnOn;
          _sprinklerStatus = turnOn ? "ON" : "OFF";
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to control sprinkler")),
        );
      }
    }
  }

  BoxDecoration _bentoDecoration(bool isDark, {Color? accentColor}) {
    return BoxDecoration(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(
        color:
            accentColor?.withValues(alpha: 0.25) ??
            (isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.06)),
        width: 1.2,
      ),
      boxShadow: [
        BoxShadow(
          color:
              accentColor?.withValues(alpha: 0.10) ??
              (isDark
                  ? Colors.black.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.08)),
          blurRadius: 16,
          spreadRadius: 0,
          offset: const Offset(0, 6),
        ),
        BoxShadow(
          color: isDark
              ? Colors.white.withValues(alpha: 0.03)
              : Colors.white.withValues(alpha: 0.9),
          blurRadius: 1,
          spreadRadius: 0,
          offset: const Offset(0, -1),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppTopBar(),
            const SizedBox(height: 16),
            _buildHeader(isDarkMode),
            const SizedBox(height: 16),
            _buildWeatherCard(isDarkMode),
            const SizedBox(height: 16),
            _buildQuickStatsRow(isDarkMode),
            const SizedBox(height: 16),
            _buildTemperatureGraph(isDarkMode),
            const SizedBox(height: 16),
            _buildBottomStatsRow(isDarkMode),
            const SizedBox(height: 16),
            _buildRecommendationCard(isDarkMode),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final isLive = _connectionStatus == "Live";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.transparent,
              child: Icon(
                Symbols.account_circle,
                size: 50,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CustomText(
                    type: TextType.username,
                    prefix: 'Hello, ',
                    suffix: '👋',
                    fontSize: 20,
                  ),
                  Text(
                    "Here's what's happening in your farm.",
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: isLive
                ? Colors.green.withValues(alpha: 0.15)
                : Colors.red.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isLive ? Colors.green : Colors.red,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLive ? Icons.wifi : Icons.wifi_off,
                size: 12,
                color: isLive ? Colors.green : Colors.red,
              ),
              const SizedBox(width: 4),
              Text(
                _connectionStatus,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isLive ? Colors.green : Colors.red,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeatherCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _bentoDecoration(isDark),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _tempStatus,
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey,
                  fontSize: 12,
                ),
              ),
              _isLoading
                  ? const SizedBox(
                      height: 40,
                      width: 40,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      "${_tempMax.toStringAsFixed(1)}°",
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
            ],
          ),
          ElevatedButton.icon(
            onPressed: () => _toggleSprinkler(!_isActivated),
            icon: const Icon(Icons.water_drop_outlined, size: 16),
            label: Text(_isActivated ? "Active" : "Activate"),
            style: ElevatedButton.styleFrom(
              backgroundColor: _isActivated ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
              elevation: 4,
              shadowColor: (_isActivated ? Colors.green : Colors.red)
                  .withValues(alpha: 0.4),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatsRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildInfoCard(isDark, Symbols.bar_chart_4_bars, "Quick Stats", [
            "Max Temp: ${_isLoading ? '…' : '${_tempMax.toStringAsFixed(1)}°C'}",
            "Sprinkler: $_sprinklerStatus",
            "Pig Status: $_pigStatus",
          ], const Color(0xFFE53935)),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: _buildInfoCard(isDark, Symbols.shower, "Sprinkler Info", [
            "Status: $_sprinklerStatus",
            "Last: $_lastActivated",
            "Mode: $_mode",
          ], const Color(0xFF1E88E5)),
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    bool isDark,
    IconData icon,
    String title,
    List<String> items,
    Color iconColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _bentoDecoration(isDark, accentColor: iconColor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: iconColor),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                e,
                style: TextStyle(
                  color: isDark ? Colors.white60 : const Color(0xFF707070),
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTemperatureGraph(bool isDark) {
    // TODO: Replace with real IoT data from your cubit/state, e.g.:
    // spots = myState.temperatureReadings.map((r) => FlSpot(r.hour.toDouble(), r.temp)).toList();
    final List<FlSpot> spots = [
      const FlSpot(0, 36.5),
      const FlSpot(1, 36.8),
      const FlSpot(2, 37.1),
      const FlSpot(3, 37.4),
      const FlSpot(4, 37.0),
      const FlSpot(5, 36.9),
      const FlSpot(6, 37.2),
      const FlSpot(7, 37.8),
      const FlSpot(8, 38.1),
      const FlSpot(9, 38.5),
      const FlSpot(10, 39.0),
      const FlSpot(11, 39.3),
      const FlSpot(12, 39.8),
      const FlSpot(13, 40.1),
      const FlSpot(14, 40.0),
      const FlSpot(15, 39.6),
      const FlSpot(16, 39.2),
      const FlSpot(17, 38.8),
      const FlSpot(18, 38.4),
      const FlSpot(19, 38.0),
      const FlSpot(20, 37.6),
      const FlSpot(21, 37.3),
      const FlSpot(22, 37.0),
      const FlSpot(23, 36.8),
    ];

    final double minTemp = spots
        .map((s) => s.y)
        .reduce((a, b) => a < b ? a : b);
    final double maxTemp = spots
        .map((s) => s.y)
        .reduce((a, b) => a > b ? a : b);
    final double yMin = (minTemp - 1).floorToDouble();
    final double yMax = (maxTemp + 1).ceilToDouble();

    final Color lineColor = Colors.green;
    final Color axisColor = isDark ? Colors.white38 : Colors.black26;
    final Color labelColor = isDark ? Colors.white54 : Colors.black45;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _bentoDecoration(isDark, accentColor: Colors.green),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Symbols.monitoring, color: Colors.green, size: 16),
              ),
              const SizedBox(width: 8),
              Text(
                "Temperature Graph (last 24 hrs)",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // Axis hint labels
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("°C", style: TextStyle(fontSize: 10, color: labelColor)),
              Text("Hour", style: TextStyle(fontSize: 10, color: labelColor)),
            ],
          ),

          const SizedBox(height: 8),

          // Chart
          SizedBox(
            height: 180,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 23,
                minY: yMin,
                maxY: yMax,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: lineColor,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      color: Colors.green.withValues(alpha: 0.08),
                    ),
                  ),
                ],
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 1,
                  getDrawingHorizontalLine: (_) => FlLine(
                    // FIX: Colors.black08 does not exist — use withValues instead
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.06)
                        : Colors.black.withValues(alpha: 0.06),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border(
                    bottom: BorderSide(color: axisColor, width: 1),
                    left: BorderSide(color: axisColor, width: 1),
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: 4,
                      getTitlesWidget: (value, meta) {
                        const labels = {
                          0: '12AM',
                          4: '4AM',
                          8: '8AM',
                          12: '12PM',
                          16: '4PM',
                          20: '8PM',
                        };
                        final hour = value.toInt();
                        if (!labels.containsKey(hour)) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            labels[hour]!,
                            style: TextStyle(fontSize: 9, color: labelColor),
                          ),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 36,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        if (value != value.roundToDouble()) {
                          return const SizedBox.shrink();
                        }
                        return SideTitleWidget(
                          meta: meta,
                          child: Text(
                            '${value.toInt()}°',
                            style: TextStyle(fontSize: 10, color: labelColor),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) =>
                        isDark ? const Color(0xFF2A2A2A) : Colors.white,
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          () {
                            final h = spot.x.toInt();
                            final isPM = h >= 12;
                            final hour12 = h % 12 == 0 ? 12 : h % 12;
                            final period = isPM ? 'PM' : 'AM';
                            return '$hour12:00 $period\n${spot.y.toStringAsFixed(1)}°C';
                          }(),
                          TextStyle(
                            color: lineColor,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatsRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildInfoCard(
            isDark,
            Symbols.calendar_month,
            "Vax Schedule",
            ["Vax name: ", "Date: "],
            const Color(0xFFFB8C00),
          ),
        ),
        const SizedBox(width: 5),
        Expanded(
          child: _buildInfoCard(isDark, Symbols.water_medium, "Water Level", [
            "Level: ",
            "Status: ",
          ], const Color(0xFF1E88E5)),
        ),
      ],
    );
  }

  Widget _buildRecommendationCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _bentoDecoration(isDark, accentColor: Colors.amber),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  size: 15,
                  color: Colors.amber,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                "Smart Recommendation",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            "Based on current conditions, we recommend activating the sprinkler system for 15 minutes to maintain optimal humidity levels.",
            style: TextStyle(
              color: isDark ? Colors.white60 : const Color(0xFF707070),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
