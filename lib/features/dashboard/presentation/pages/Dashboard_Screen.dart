import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../../core/widgets/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../../core/widgets/text.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int selectedIndex = 2;

  // Sensor data variables
  double _waterPct = 0;
  String _waterStatus = "Unknown";
  double _humidity = 0;
  double _tempMax = 0;
  double _tempAvg = 0;
  double _tempMin = 0;
  String _tempStatus = "Normal";

  @override
  void initState() {
    super.initState();
    _startFetching();
  }

  void _startFetching() {
    Future.delayed(Duration.zero, () async {
      while (mounted) {
        await _fetchSensorData();
        await Future.delayed(const Duration(seconds: 3));
      }
    });
  }

  Future<void> _fetchSensorData() async {
    try {
      final response = await http
          .get(Uri.parse("http://192.168.1.100/data"))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _waterPct = (data['waterPct'] as num).toDouble();
          _humidity = (data['humidity'] as num).toDouble();
          _tempMax = (data['tempMax'] as num).toDouble();
          _tempAvg = (data['tempAvg'] as num).toDouble();
          _tempMin = (data['tempMin'] as num).toDouble();
          _tempStatus = data['tempStatus'] ?? "Normal";

          if (_waterPct >= 70) {
            _waterStatus = "High";
          } else if (_waterPct >= 40) {
            _waterStatus = "Medium";
          } else if (_waterPct > 10) {
            _waterStatus = "Low";
          } else {
            _waterStatus = "Critical";
          }
        });
      }
    } catch (e) {
      setState(() {
        _waterStatus = "Offline";
      });
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
          ],
        ),
      ],
    );
  }

  Widget _buildWeatherCard(bool isDark) {
    Color statusColor;
    if (_tempStatus == "Fever Alert") {
      statusColor = Colors.red;
    } else if (_tempStatus == "Elevated") {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.green;
    }

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
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
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
            onPressed: () {},
            icon: const Icon(Icons.water_drop_outlined, size: 16),
            label: const Text("Activate"),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
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
              "Max Temp: ${_tempMax.toStringAsFixed(1)}°",
              "Avg Temp: ${_tempAvg.toStringAsFixed(1)}°",
              "Pig Status: $_tempStatus",
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
              "Humidity: ${_humidity.toStringAsFixed(1)}%",
              "Min Temp: ${_tempMin.toStringAsFixed(1)}°",
              "Mode: Auto",
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
            : const Color(0xFFDCEAF5),
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
        // ✅ Water Level Card
        Flexible(
          flex: 1,
          child: _buildWaterLevelCard(isDark),
        ),
      ],
    );
  }

  Widget _buildWaterLevelCard(bool isDark) {
    Color statusColor;
    if (_waterStatus == "High") {
      statusColor = Colors.green;
    } else if (_waterStatus == "Medium") {
      statusColor = Colors.orange;
    } else if (_waterStatus == "Low") {
      statusColor = Colors.red;
    } else if (_waterStatus == "Critical") {
      statusColor = Colors.red.shade900;
    } else {
      statusColor = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.water_outlined,
                size: 20,
                color: Color(0xFF3333CC),
              ),
              const SizedBox(width: 6),
              Text(
                "Water Level",
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
            "Level: ${_waterPct.toStringAsFixed(0)}%",
            style: TextStyle(
              color: isDark
                  ? Colors.white60
                  : const Color.fromARGB(255, 112, 112, 112),
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                "Status: ",
                style: TextStyle(
                  color: isDark
                      ? Colors.white60
                      : const Color.fromARGB(255, 112, 112, 112),
                  fontSize: 12,
                ),
              ),
              Text(
                _waterStatus,
                style: TextStyle(
                  color: statusColor,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _waterPct / 100,
              minHeight: 6,
              backgroundColor:
                  isDark ? Colors.white12 : Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
        ],
      ),
    );
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
            _waterStatus == "Critical" || _waterStatus == "Low"
                ? "Water level is $_waterStatus! Please refill the tank immediately to ensure proper hydration for the pigs."
                : _tempStatus == "Fever Alert"
                    ? "Fever detected! Activate the sprinkler system immediately and contact your veterinarian."
                    : _tempStatus == "Elevated"
                        ? "Temperature is elevated. Consider activating the sprinkler for 15 minutes to cool down."
                        : "All conditions are normal. No immediate action required. Keep monitoring regularly.",
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