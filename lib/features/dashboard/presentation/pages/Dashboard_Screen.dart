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

  double _tempMax     = 0;
  String _tempStatus  = "Normal";
  bool   _isActivated = false;

  String _sprinklerStatus = "OFF";
  String _lastActivated   = "—";
  String _mode            = "—";
  String _pigStatus       = "—";

  // ✅ FIX: these now get populated from the updated ESP32 /data endpoint
  String _waterLevel  = "—";
  String _waterStatus = "—";

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
          _tempMax         = (data['tempMax']   as num?)?.toDouble() ?? _tempMax;
          _tempStatus      = data['tempStatus'] as String? ?? _tempStatus;
          _isActivated     = data['sprinkler']  as bool?   ?? _isActivated;
          _sprinklerStatus = _isActivated ? "ON" : "OFF";
          _lastActivated   = data['lastActivated'] as String? ?? _lastActivated;
          _mode            = data['mode']       as String? ?? _mode;
          _pigStatus       = data['pigStatus']  as String? ?? _pigStatus;

          // ✅ FIX: correctly reads "waterLevel" and "waterStatus" from ESP32
          _waterLevel      = data['waterLevel'] as String? ?? _waterLevel;
          _waterStatus     = data['waterStatus'] as String? ?? _waterStatus;

          _isLoading        = false;
          _connectionStatus = "Live";
        });
      }
    } catch (_) {
      setState(() {
        _connectionStatus = "No connection";
        _isLoading        = false;
      });
    }
  }

  Future<void> _toggleSprinkler(bool turnOn) async {
    try {
      final state    = turnOn ? "on" : "off";
      final response = await http
          .get(Uri.parse("http://$esp32Ip/sprinkler?state=$state"))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200) {
        setState(() {
          _isActivated     = turnOn;
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

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16),
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
                color: isDark
                    ? const Color.fromARGB(255, 255, 255, 255)
                    : const Color.fromARGB(255, 0, 0, 0),
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
                    fontSize: 20,
                  ),
                  Text(
                    "What do you want today?",
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            // Connection status badge
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
        ),
      ],
    );
  }

  Widget _buildWeatherCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
          child: _buildInfoCard(
            isDark,
            Icons.bar_chart,
            "Quick Stats",
            [
              "Max Temp: ${_isLoading ? '…' : '${_tempMax.toStringAsFixed(1)}°C'}",
              "Sprinkler: $_sprinklerStatus",
              "Pig Status: $_pigStatus",
            ],
            Colors.green.withValues(alpha: 0.2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildInfoCard(
            isDark,
            Icons.water_outlined,
            "Control",
            [
              "Status: $_sprinklerStatus",
              "Last: $_lastActivated",
              "Mode: $_mode",
            ],
            Colors.blue.withValues(alpha: 0.2),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(
    bool isDark,
    IconData icon,
    String title,
    List<String> items,
    Color? backgroundColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor ??
            (isDark ? const Color(0xFF2C2C2C) : Colors.white),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.blue),
              const SizedBox(width: 6),
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
          const SizedBox(height: 8),
          ...items.map(
            (e) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                e,
                style: TextStyle(
                  color: isDark
                      ? Colors.white60
                      : const Color.fromARGB(255, 112, 112, 112),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF3B72FF).withValues(alpha: 0.2)
            : const Color(0xFFB0C4DE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart,
                color: isDark
                    ? Colors.blue
                    : const Color.fromARGB(255, 0, 0, 0),
              ),
              const SizedBox(width: 8),
              Text(
                "Temperature Graph (last 24 hrs)",
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 150,
            child: BarChart(
              BarChartData(
                barGroups: [35, 38, 36, 40, 37, 39, 35, 38]
                    .asMap()
                    .entries
                    .map(
                      (e) => BarChartGroupData(
                        x: e.key,
                        barRods: [
                          BarChartRodData(
                            toY: e.value.toDouble(),
                            color: isDark ? Colors.blue : Colors.black87,
                            width: 16,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    )
                    .toList(),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: const FlTitlesData(show: false),
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
        Flexible(
          flex: 1,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? const Color(0xFF2C2C2C)
                  : const Color.fromRGBO(247, 127, 0, 0.2),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.calendar_month_outlined,
                      size: 16,
                      color: Colors.blue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "Vaccine Schedule",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...["Vax name:", "Date:"].map(
                  (e) => Text(
                    e,
                    style: TextStyle(
                      color: isDark
                          ? Colors.white60
                          : const Color.fromARGB(255, 112, 112, 112),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 13),
        Flexible(
          flex: 1,
          child: _buildWaterLevelCard(isDark),
        ),
      ],
    );
  }

  // ✅ FIX: now shows real _waterLevel and _waterStatus from ESP32
  Widget _buildWaterLevelCard(bool isDark) {
    return Container(
      width: 500,
      height: 85,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF2C2C2C)
            : const Color.fromRGBO(0, 48, 73, 0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.water_outlined,
                size: 16,
                color: Colors.blue,
              ),
              const SizedBox(width: 6),
              Text(
                "Water Level",
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: isDark
                      ? const Color.fromARGB(255, 255, 255, 255)
                      : const Color.fromARGB(255, 0, 0, 0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _isLoading
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Level: $_waterLevel",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white60
                            : const Color.fromARGB(255, 112, 112, 112),
                      ),
                    ),
                    Text(
                      "Status: $_waterStatus",
                      style: TextStyle(
                        fontSize: 12,
                        color: _getWaterStatusColor(_waterStatus),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ],
      ),
    );
  }

  /// Returns a color based on water status severity
  Color _getWaterStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'full':
        return Colors.green;
      case 'normal':
        return Colors.blue;
      case 'low':
        return Colors.orange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Widget _buildRecommendationCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? const Color.fromRGBO(248, 222, 34, 0.2)
            : const Color.fromRGBO(248, 222, 34, 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.light_mode, size: 16, color: Colors.blue),
              const SizedBox(width: 6),
              Text(
                "Recommendations",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            "Based on current conditions, we recommend activating the sprinkler system for 15 minutes to maintain optimal humidity levels.",
            style: TextStyle(
              color: isDark
                  ? Colors.white60
                  : const Color.fromARGB(255, 112, 112, 112),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}