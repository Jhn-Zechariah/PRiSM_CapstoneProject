import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../features/auth/presentation/components/custom_text.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;

  const DashboardScreen({super.key, required this.onThemeToggle});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int selectedIndex = 2; // Default to Home

  @override
  Widget build(BuildContext context) {
    // Determine theme state for dynamic styling
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

  // --- HEADER SECTION (FIXED TO SHOW LOGO_LIGHT) ---
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
                    ? Color.fromARGB(255, 255, 255, 255)
                    : const Color.fromARGB(255, 0, 0, 0),
              ),
            ),
            const SizedBox(width: 12),
            Column(
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
                "Normal",
                style: TextStyle(
                  color: isDark ? Colors.white60 : Colors.grey,
                  fontSize: 12,
                ),
              ),
              Text(
                "35°",
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

  // --- QUICK STATS ROW ---
  Widget _buildQuickStatsRow(bool isDark) {
    return Row(
      children: [
        Expanded(
          child: _buildInfoCard(
            isDark,
            Icons.bar_chart,
            "Quick Stats",
            const ["Max Temp: ", "Sprinkler: ", "Pig Status: "],
            Colors.green.withValues(alpha: 0.2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildInfoCard(
            isDark,
            Icons.water_outlined,
            "Control",
            const ["Status: ", "Last: ", "Mode: "],
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
        color:
            backgroundColor ??
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

  // --- TEMPERATURE GRAPH ---
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

  // --- BOTTOM STATS ---
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
                    Icon(
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
          child: _buildStatCard(
            isDark,
            "Feeding Schedule",
            "10:00 AM",
            "5:00 PM",
          ),
        ),
        // Empty space to balance the row
      ],
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
              Icon(Icons.light_mode, size: 16, color: Colors.blue),
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

  Widget _buildStatCard(
    bool isDark,
    String label,
    String value1,
    String value2,
  ) {
    return Container(
      width: 150,
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
          Text(
            label,
            style: TextStyle(
              color: isDark
                  ? const Color.fromARGB(255, 255, 255, 255)
                  : const Color.fromARGB(255, 0, 0, 0),
              fontSize: 13,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          // morning time
          Text(
            value1,
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? Colors.white60
                  : const Color.fromARGB(255, 112, 112, 112),
            ),
          ),
          // evening time
          Text(
            value2,
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? Colors.white60
                  : const Color.fromARGB(255, 112, 112, 112),
            ),
          ),
        ],
      ),
    );
  }
}
