import 'dart:async'; // 👈 ADD THIS for Timer
import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:prism_app/core/widgets/text.dart';
import 'package:prism_app/core/widgets/theme_seting.dart';
import 'package:prism_app/features/auth/presentation/pages/landing_page.dart';
import 'package:prism_app/features/dashboard/presentation/pages/Dashboard_Screen.dart';
import 'package:prism_app/features/auth/presentation/pages/user_profile.dart';
import 'package:prism_app/features/medication/presentation/pages/pig_meds.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../features/auth/presentation/cubits/auth_states.dart';
import '../../features/feeding/data/firestore_feeding_record_repo.dart';
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
import 'package:cloud_firestore/cloud_firestore.dart';

class AppNav extends StatefulWidget {
  // 🔹 CHANGED: Change VoidCallback to a function that accepts the current theme state
  final Function(ThemeMode selectedMode) onThemeToggle;

  const AppNav({super.key, required this.onThemeToggle});

  @override
  State<AppNav> createState() => _AppNavState();
}

class _AppNavState extends State<AppNav> {
  int selectedIndex = 2;
  bool _showHumidity = false;
  bool _showPigMeds = false;

  final _feedingRepo = FirestoreFeedingRecordRepo();

  final List<Widget> _navItems = const [
    Icon(Symbols.savings, size: 30, color: Colors.white),
    Icon(Symbols.thermostat, size: 30, color: Colors.white),
    Icon(Symbols.home, size: 30, color: Colors.white),
    Icon(Symbols.yoshoku, size: 30, color: Colors.white),
    Icon(Symbols.mixture_med, size: 30, color: Colors.white),
  ];

  @override
  void initState() {
    super.initState();
  } // ✅ only ONE closing brace here

  @override
  void dispose() {
    super.dispose();
  }




  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final List<Widget> screens = [
      PigProfilesScreen(), // Index 0: Pig Profiles
      // Index 1: Temperature / Humidity Monitor Option
      _showHumidity
          ? HumidityMonitoring(
        onSwitchToTemperature: () => setState(() => _showHumidity = false),
        // 🔹 These now read from sprinklerNotifier directly inside the screen
        // so no need to pass isActivated / onSprinklerChanged / onMaxChanged
      )
          : TemperatureMonitoring(
              onSwitchToHumidity: () => setState(() => _showHumidity = true),
            ),
      DashboardScreen(),
      FeedingRecordsPage(repo: _feedingRepo),
      _showPigMeds
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

    return BlocListener<AuthCubit, AuthState>(
      listener: (context, state) {
        // When the user clicks logout, this catches it and boots them to login!
        if (state is Unauthenticated) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  LandingPage(onThemeToggle: widget.onThemeToggle),
            ),
            (route) => false, // Completely destroys the dashboard history
          );
        }
      },
      child: Scaffold(
        drawer: _buildCustomDrawer(isDarkMode),
        body: SafeArea(child: screens[selectedIndex]),
        bottomNavigationBar: _buildBottomNav(isDarkMode),
      ),
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
            _drawerTile(Symbols.barcode_reader, "IoT Control", () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return const IoTControlsDialog();
                },
              );
            }),
            _drawerTile(Symbols.notifications_active, "Notification", () {
              Navigator.pop(context);
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return const NotificationControlsDialog();
                },
              );
            }),
            _drawerTile(
              Icons.brightness_6,
              "Theme Settings",
                  () async { // 🔹 1. Add 'async' here!
                Navigator.pop(context); // Close the drawer first

                // 🔹 2. Ask SharedPreferences what the user actually saved last time
                final prefs = await SharedPreferences.getInstance();
                final savedThemeIndex = prefs.getInt('theme_mode') ?? 0; // Default to 0 (System)
                final actualCurrentTheme = ThemeMode.values[savedThemeIndex];

                // 🔹 3. Only show the dialog if the widget is still on screen
                if (context.mounted) {
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return ThemeSettingsDialog(
                        // 🔹 4. Pass the real saved theme instead of ThemeMode.system!
                        currentTheme: actualCurrentTheme,
                        onThemeSelected: (selectedMode) {
                          widget.onThemeToggle(selectedMode);
                        },
                      );
                    },
                  );
                }
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
          if (index != 1) _showHumidity = false;
        });
      },
    );
  }
}
