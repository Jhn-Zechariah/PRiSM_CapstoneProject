import 'package:curved_navigation_bar/curved_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:prism_app/screens/Dashboard_Screen.dart';
import '../features/auth/presentation/components/adminDisplaydrawer.dart';
import '../features/auth/presentation/cubits/auth_cubit.dart';
import 'Pig_profiles.dart';


class AppNav extends StatefulWidget {

  final VoidCallback onThemeToggle;

  const AppNav({super.key,required this.onThemeToggle});

  @override
  State<AppNav> createState() => _AppNavState();
}

class _AppNavState extends State<AppNav> {
  //Selected index
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
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // list of screens for the bottom navigation bar
    final List<Widget> screens = [
      PigProfiles(onThemeToggle: widget.onThemeToggle), // Index 0
      const Center(child: Text("IoT Control")),
      DashboardScreen(onThemeToggle: widget.onThemeToggle), // Index 2: THE MAIN DASHBOARD
      const Center(child: Text("Track Changes")), // Index 3
      const Center(child: Text("Monetization")), // Index 4
    ];

    //FIXED APPBAR
    // return Scaffold(
    //   drawer: _buildCustomDrawer(isDarkMode),
    //
    //   body: SafeArea(
    //     child: Column(
    //       children: [
    //         // 🔹 Top Bar (fixed)
    //         Padding(
    //           padding: const EdgeInsets.all(16),
    //           child: AppTopBar(
    //             // title: 'PRISM' // optional dynamic title
    //           ),
    //         ),
    //
    //         // 🔹 Screen content (changes when navigating)
    //         Expanded(
    //           child: Padding(
    //             padding: const EdgeInsets.symmetric(horizontal: 16),
    //             child: screens[selectedIndex],
    //           ),
    //         ),
    //       ],
    //     ),
    //   ),
    //
    //   bottomNavigationBar: _buildBottomNav(isDarkMode),
    // );

    // SCROLLABLE APPBAR
    return Scaffold(
      drawer: _buildCustomDrawer(isDarkMode),
      body: SafeArea(
        child: screens[selectedIndex],
      ),
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
                    const AdminInfoWidget(),
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
              // Close the drawer first so it doesn't stay open in the background
              Navigator.pop(context);

              // Tell Firebase and your BLoC to log the user out!
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

}
