import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:prism_app/features/auth/presentation/pages/auth_page.dart';
import '../features/auth/presentation/pages/login_screen.dart';
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:prism_app/screens/Pig_profiles.dart';
import 'app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
//import 'package:google_nav_bar/google_nav_bar.dart';

class DashboardScreen extends StatefulWidget {
  final VoidCallback onThemeToggle;

  const DashboardScreen({super.key, required this.onThemeToggle});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int selectedIndex = 2; // Default to Home

  //list of icons for the bottom navigation bar
  final List<Widget> _navItems = const [
    Icon(Symbols.savings, size: 30, color: Colors.white),
    Icon(Symbols.thermostat, size: 30, color: Colors.white),
    Icon(Symbols.home, size: 30, color: Colors.white),
    Icon(Symbols.yoshoku, size: 30, color: Colors.white),
    Icon(Symbols.mixture_med, size: 30, color: Colors.white),
  ];

  @override
  Widget build(BuildContext context) {
    // Determine theme state for dynamic styling
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    //list of screens for the bottom navigation bar
    final List<Widget> screens = [
      PigProfiles(onThemeToggle: widget.onThemeToggle), // Index 0
      const Center(child: Text("IoT Control")),
      _buildDashboardHome(isDarkMode), // Index 2: THE MAIN DASHBOARD
      const Center(child: Text("Track Changes")), // Index 3
      const Center(child: Text("Monetization")), // Index 4
    ];

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
      drawer: _buildCustomDrawer(isDarkMode),

      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: screens[selectedIndex],
        ),
      ),

      bottomNavigationBar: _buildBottomNav(isDarkMode),
    );
  }

  Widget _buildDashboardHome(bool isDark) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(isDark),
          const SizedBox(height: 16),
          _buildWeatherCard(isDark),
          const SizedBox(height: 16),
          _buildQuickStatsRow(isDark),
          const SizedBox(height: 16),
          _buildTemperatureGraph(isDark),
          const SizedBox(height: 16),
          _buildBottomStatsRow(isDark),
          const SizedBox(height: 16),
          _buildRecommendationCard(isDark),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // --- HEADER SECTION (FIXED TO SHOW LOGO_LIGHT) ---
  Widget _buildHeader(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTopBar(isDark: isDark),
        const SizedBox(height: 12),
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
                Text(
                  "Hello, John",
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black,
                  ),
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

  // --- DRAWER SECTION ---
  Widget _buildCustomDrawer(bool isDark) {
    return Drawer(
      child: Container(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFF3B72FF),
        child: Column(
          children: [
            const SizedBox(height: 60),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.white24,
                    child: Icon(
                      Icons.person_outline,
                      color: Colors.white,
                      size: 35,
                    ),
                  ),
                  const SizedBox(width: 15),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Zechariah",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "paradojhonzechariah@gmail.com",
                          style: TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Divider(
              color: Colors.white24,
              thickness: 1,
              indent: 20,
              endIndent: 20,
            ),
            _drawerTile(Icons.person_outline, "My Profile", () {}),
            _drawerTile(Icons.sensors, "IoT Control", () {}),
            _drawerTile(
              isDark ? Icons.wb_sunny : Icons.nightlight_round,
              isDark ? "Switch to Light Mode" : "Switch to Dark Mode",
              () {
                Navigator.pop(context);
                widget.onThemeToggle();
              },
            ),
            const Spacer(),
            const Divider(color: Colors.white24),
            _drawerTile(Icons.logout, "Log Out", () {
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      AuthPage(onThemeToggle: widget.onThemeToggle),
                ),
                (route) => false,
              );
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _drawerTile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white, size: 24),
      title: Text(
        title,
        style: const TextStyle(color: Colors.white, fontSize: 16),
      ),
      onTap: onTap,
    );
  }

  // --- WEATHER CARD ---
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
        const SizedBox(width: 12),
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

  Widget _buildBottomNav(bool isDark) {
    return CurvedNavigationBar(
      backgroundColor: Colors.transparent,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.black,
      buttonBackgroundColor: isDark ? Colors.blue : Colors.blue,

      height: 70,
      index: selectedIndex,
      items: _navItems,
      animationDuration: const Duration(milliseconds: 300),
      onTap: (index) {
        setState(() {
          selectedIndex = index;
        });
      },
    );
  }

  /*Widget _buildBottomNav(bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15.0, vertical: 8),
        child: GNav(
          tabBorderRadius: 12,
          backgroundColor: Colors.transparent,
          color: isDark ? Colors.white54 : Colors.grey, // Unselected color
          activeColor: Colors.white, // Selected icon/text color
          tabBackgroundColor: Colors.blue, // THIS is your "Rounded Square"
          gap: 8, // Space between icon and text
          padding: const EdgeInsets.all(16),
          selectedIndex: selectedIndex,
          onTabChange: (index) {
            setState(() {
              selectedIndex = index;
            });
          },
          tabs: const [
            GButton(icon: Icons.pets),
            GButton(icon: Icons.thermostat),
            GButton(icon: Icons.home),
            GButton(icon: Icons.track_changes),
            GButton(icon: Icons.monetization_on),
          ],
        ),
      ),
    );
  }*/
}
