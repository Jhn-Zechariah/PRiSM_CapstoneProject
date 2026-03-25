import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.black,
        onPressed: () {},
        child: const Icon(Icons.home, color: Colors.white),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildWeatherCard(),
              const SizedBox(height: 16),
              _buildQuickStatsRow(),
              const SizedBox(height: 16),
              _buildTemperatureGraph(),
              const SizedBox(height: 16),
              _buildBottomStatsRow(),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Image.asset(
              'assets/prism_logo.png',
              height: 40, // adjust to fit
            ),
            IconButton(
                icon: const Icon(Icons.settings_outlined), onPressed: () {}),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: const [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.black12,
              child: Icon(Icons.person, color: Colors.black54),
            ),
            SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("Hello, John", style: TextStyle(
                    fontSize: 20, fontWeight: FontWeight.bold)),
                Text("What do you want today?",
                    style: TextStyle(color: Colors.grey)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWeatherCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                  "Normal", style: TextStyle(color: Colors.grey, fontSize: 12)),
              Text("35°",
                  style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold)),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text("Mon 08-30",
                  style: TextStyle(color: Colors.grey, fontSize: 12)),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.water_drop_outlined, size: 16),
                label: const Text("Activate"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildInfoCard(
            icon: Icons.bar_chart,
            title: "Quick Stats (Today)",
            items: const ["Max Temp:", "Sprinkler Activation:", "Pig Status:"],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildInfoCard(
            icon: Icons.water_outlined,
            title: "Sprinkler Control",
            items: const [
              "Sprinkler status:",
              "Last activated:",
              "Activation mode:"
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildInfoCard(
      {required IconData icon, required String title, required List<
          String> items}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 6),
              Flexible(child: Text(title, style: const TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 13))),
            ],
          ),
          const SizedBox(height: 8),
          ...items.map((e) =>
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(e,
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
              )),
        ],
      ),
    );
  }

  Widget _buildTemperatureGraph() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFB0C4DE), // steel blue like the UI
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.bar_chart, color: Colors.white),
              SizedBox(width: 8),
              Text("Temperature Graph (last 24 hrs)",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
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
                    .map((e) =>
                    BarChartGroupData(
                      x: e.key,
                      barRods: [
                        BarChartRodData(
                          toY: e.value.toDouble(),
                          color: Colors.black87,
                          width: 16,
                          borderRadius: BorderRadius.circular(4),
                        )
                      ],
                    ))
                    .toList(),
                gridData: FlGridData(
                  show: true,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: Colors.white30, strokeWidth: 0.5),
                  drawVerticalLine: false,
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(show: false),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomStatsRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.calendar_month_outlined, size: 16),
                    SizedBox(width: 6),
                    Text("Monthly Expense", style: TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 13)),
                  ],
                ),
                const SizedBox(height: 8),
                ...["Feeds:", "Vaccines:", "Vitamins:", "Labor:", "Others:"]
                    .map((e) =>
                    Text(e, style: const TextStyle(
                        color: Colors.grey, fontSize: 12))),
                const SizedBox(height: 8),
                const Text("₱15,000", style: TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18)),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          children: [
            _buildStatCard("Sales", "₱20,000"),
            const SizedBox(height: 12),
            _buildStatCard("Net Profit", "₱5,000"),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value) {
    return Container(
      width: 130,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 6),
          Text(value, style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 18)),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    return BottomAppBar(
      color: Colors.black,
      shape: const CircularNotchedRectangle(),
      notchMargin: 8,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(icon: const Icon(Icons.pets, color: Colors.white),
              onPressed: () {}),
          IconButton(icon: const Icon(Icons.thermostat, color: Colors.white),
              onPressed: () {}),
          const SizedBox(width: 40), // space for FAB
          IconButton(icon: const Icon(Icons.track_changes, color: Colors.white),
              onPressed: () {}),
          IconButton(icon: const Icon(
              Icons.monetization_on_outlined, color: Colors.white),
              onPressed: () {}),
        ],
      ),
    );
  }

}