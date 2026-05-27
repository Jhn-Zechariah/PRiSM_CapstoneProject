import 'dart:async';
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/widgets/app_top_bar.dart';
import '../../../../core/widgets/text.dart';

const String esp32Ip = "192.168.1.100";

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  Timer? _timer;

  bool _isLoading = true;
  bool _isActivated = false;

  String _connectionStatus = "Connecting...";
  String _tempStatus = "Normal";
  String _sprinklerStatus = "OFF";
  String _lastActivated = "—";
  String _mode = "—";
  String _pigStatus = "—";
  String _waterLevel = "—";
  String _waterStatus = "—";

  double _tempMax = 0;

  @override
  void initState() {
    super.initState();

    _fetchData();

    _timer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _fetchData(),
    );
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
          _tempMax =
              (data['tempMax'] as num?)?.toDouble() ?? 0;

          _tempStatus =
              data['tempStatus'] as String? ?? "Normal";

          _isActivated =
              data['sprinkler'] as bool? ?? false;

          _sprinklerStatus =
              _isActivated ? "ON" : "OFF";

          _lastActivated =
              data['lastActivated'] as String? ?? "—";

          _mode = data['mode'] as String? ?? "—";

          _pigStatus =
              data['pigStatus'] as String? ?? "—";

          _waterLevel =
              data['waterLevel'] as String? ?? "—";

          _waterStatus =
              data['waterStatus'] as String? ?? "—";

          _connectionStatus = "Live";
          _isLoading = false;
        });
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
          .get(
            Uri.parse(
              "http://$esp32Ip/sprinkler?state=$state",
            ),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        setState(() {
          _isActivated = turnOn;
          _sprinklerStatus = turnOn ? "ON" : "OFF";
        });
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Failed to control sprinkler",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
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
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(bool isDark) {
    final isLive = _connectionStatus == "Live";

    return Row(
      children: [
        CircleAvatar(
          radius: 24,
          backgroundColor: Colors.transparent,
          child: Icon(
            Symbols.account_circle,
            size: 50,
            color:
                isDark ? Colors.white : Colors.black,
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              const CustomText(
                type: TextType.username,
                prefix: 'Hello, ',
                suffix: '👋',
                fontSize: 20,
              ),

              Text(
                "What do you want today?",
                style: TextStyle(
                  color: isDark
                      ? Colors.white60
                      : Colors.grey,
                ),
              ),
            ],
          ),
        ),

        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 4,
          ),
          decoration: BoxDecoration(
            color: isLive
                ? Colors.green.withOpacity(0.15)
                : Colors.red.withOpacity(0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color:
                  isLive ? Colors.green : Colors.red,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isLive
                    ? Icons.wifi
                    : Icons.wifi_off,
                size: 12,
                color:
                    isLive ? Colors.green : Colors.red,
              ),

              const SizedBox(width: 4),

              Text(
                _connectionStatus,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      isLive ? Colors.green : Colors.red,
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
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                _tempStatus,
                style: TextStyle(
                  color: isDark
                      ? Colors.white60
                      : Colors.grey,
                ),
              ),

              const SizedBox(height: 4),

              _isLoading
                  ? const CircularProgressIndicator()
                  : Text(
                      "${_tempMax.toStringAsFixed(1)}°C",
                      style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.white
                            : Colors.black,
                      ),
                    ),
            ],
          ),

          ElevatedButton.icon(
            onPressed: () =>
                _toggleSprinkler(!_isActivated),
            icon: const Icon(Icons.water_drop),
            label: Text(
              _isActivated ? "Active" : "Activate",
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _isActivated
                      ? Colors.green
                      : Colors.red,
              foregroundColor: Colors.white,
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
              "Max Temp: ${_tempMax.toStringAsFixed(1)}°C",
              "Sprinkler: $_sprinklerStatus",
              "Pig Status: $_pigStatus",
            ],
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
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: Colors.blue,
              ),

              const SizedBox(width: 6),

              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color:
                      isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          ...items.map(
            (item) => Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                item,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? Colors.white60
                      : Colors.grey,
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
            ? Colors.blue.withOpacity(0.2)
            : const Color(0xFFB0C4DE),
        borderRadius: BorderRadius.circular(16),
      ),
      child: SizedBox(
        height: 150,
        child: BarChart(
          BarChartData(
            barGroups:
                [35, 38, 36, 40, 37, 39, 35, 38]
                    .asMap()
                    .entries
                    .map(
                      (e) => BarChartGroupData(
                        x: e.key,
                        barRods: [
                          BarChartRodData(
                            toY: e.value.toDouble(),
                            color: Colors.blue,
                            width: 16,
                          ),
                        ],
                      ),
                    )
                    .toList(),
            borderData:
                FlBorderData(show: false),
            titlesData:
                const FlTitlesData(show: false),
            gridData:
                const FlGridData(show: false),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomStatsRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildInfoCard(
            isDark,
            Icons.calendar_month_outlined,
            "Vaccine Schedule",
            [
              "Vax name:",
              "Date:",
            ],
          ),
        ),

        const SizedBox(width: 12),

        Expanded(
          child: _buildWaterLevelCard(isDark),
        ),
      ],
    );
  }

  Widget _buildWaterLevelCard(bool isDark) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:
            isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
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
                  fontWeight: FontWeight.bold,
                  color:
                      isDark ? Colors.white : Colors.black,
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          Text(
            "Level: $_waterLevel",
            style: TextStyle(
              fontSize: 12,
              color:
                  isDark ? Colors.white60 : Colors.grey,
            ),
          ),

          Text(
            "Status: $_waterStatus",
            style: TextStyle(
              fontSize: 12,
              color: _getWaterStatusColor(
                _waterStatus,
              ),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

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
        color: Colors.amber.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        "Based on current conditions, we recommend activating the sprinkler system for 15 minutes.",
        style: TextStyle(
          fontSize: 12,
          color:
              isDark ? Colors.white60 : Colors.black87,
        ),
      ),
    );
  }
}