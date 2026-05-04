import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:prism_app/features/auth/presentation/components/text.dart';
import 'package:prism_app/features/dashboard/presentation/pages/Dashboard_Screen.dart';
import 'package:prism_app/features/auth/presentation/pages/user_profile.dart';
import 'package:prism_app/features/medication/presentation/pages/pig_meds.dart';
import '../../features/monitoring/presentation/pages/IoTControlsDialog.dart';
import '../../features/monitoring/presentation/pages/NotificationControlsDialog.dart';
import '../../features/feeding/presentation/pages/feedingrecord.dart';
import '../../features/auth/data/firestore_profile_repo.dart';
import '../../features/auth/presentation/cubits/auth_cubit.dart';
import '../../features/pig_management/presentation/pages/pig_profiles.dart';
import '../../features/auth/presentation/cubits/profile_cubit.dart';
import '../../features/monitoring/presentation/pages/temperaturemonitoring.dart';
import '../../features/monitoring/presentation/pages/humiditymonitoring.dart';
import '../../features/medication/presentation/pages/meds_stocks.dart';

class AppNav extends StatefulWidget {
  final VoidCallback onThemeToggle;

  const AppNav({super.key, required this.onThemeToggle});

  @override
  State<AppNav> createState() => _AppNavState();
}

class _AppNavState extends State<AppNav> {
  int selectedIndex = 2; // Default to Home
  bool _showHumidity = false; // Controls Temperature vs Humidity sub-tab
  bool _showPigMeds = false; // Controls Stock vs Pig Meds sub-tab

  final List<Widget> _navItems = const [
    Icon(Symbols.savings, size: 30, color: Colors.white),
    Icon(Symbols.thermostat, size: 30, color: Colors.white),
    Icon(Symbols.home, size: 30, color: Colors.white),
    Icon(Symbols.yoshoku, size: 30, color: Colors.white),
    Icon(Symbols.mixture_med, size: 30, color: Colors.white),
  ];

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final List<Widget> screens = [
      PigProfilesScreen(), // Index 0: Pig Profiles
      _showHumidity // Index 1: Temperature / Humidity
          ? HumidityMonitoring(
              onSwitchToTemperature: () {
                setState(() => _showHumidity = false);
              },
            )
          : TemperatureMonitoring(
              onSwitchToHumidity: () {
                setState(() => _showHumidity = true);
              },
            ),
      const DashboardScreen(), // Index 2: Home / Dashboard
      const FeedingRecordsPage(), // Index 3: Feeding Records
      _showPigMeds // Index 4: Pig Meds
          ? pig_meds(
              onSwitchToStock: () {
                setState(() => _showPigMeds = false);
              },
            )
          : meds_Stocks(
              onSwitchToPigMeds: () {
                setState(() => _showPigMeds = true);
              },
            ),
    ];

    return Scaffold(
      drawer: _buildCustomDrawer(isDarkMode),
      body: SafeArea(child: screens[selectedIndex]),
      bottomNavigationBar: _buildBottomNav(isDarkMode),
    );
  }

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
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      type: TextType.username,
                      textColor: Colors.white,
                      fontSize: 18,
                    ),
                    CustomText(
                      type: TextType.email,
                      textColor: Colors.white,
                      fontSize: 11,
                    )
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
            _drawerTile(Icons.person_outline, "My Profile", () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BlocProvider(
                    create: (context) =>
                        ProfileCubit(profileRepo: FirebaseProfileRepo()),
                    child: const MyProfile(),
                  ),
                ),
              );
            }),
            _drawerTile(Icons.sensors, "IoT Control", () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return const IoTControlsDialog();
                },
              );
            }),
            _drawerTile(Icons.notifications, "Notification", () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return const NotificationControlsDialog();
                },
              );
            }),
            _drawerTile(
              isDark ? Icons.wb_sunny : Icons.nightlight_round,
              isDark ? "Switch to Light Mode" : "Switch to Dark Mode",
              () {
                widget.onThemeToggle();
                Navigator.pop(context);
              },
            ),
            const Spacer(),
            const Divider(color: Colors.white24),
            _drawerTile(Icons.logout, "Log Out", () {
              Navigator.pop(context);
              final authCubit = context.read<AuthCubit>();
              authCubit.logout();
            }),
            const SizedBox(height: 20),
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

  Widget _buildBottomNav(bool isDark) {
    return CurvedNavigationBar(
      backgroundColor: Colors.transparent,
      color: isDark ? const Color(0xFF1E1E1E) : Colors.black,
      buttonBackgroundColor: Colors.blue,
      height: 70,
      index: selectedIndex,
      items: _navItems,
      animationDuration: const Duration(milliseconds: 300),
      onTap: (index) {
        setState(() {
          selectedIndex = index;
          // Reset humidity sub-tab when leaving the thermostat tab
          if (index != 1) _showHumidity = false;
        });
      },
    );
  }
}
