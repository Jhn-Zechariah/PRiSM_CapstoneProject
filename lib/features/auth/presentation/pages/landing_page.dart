import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:prism_app/features/auth/presentation/pages/auth_page.dart';

class LandingPage extends StatefulWidget {
  final VoidCallback onThemeToggle;
  const LandingPage({super.key, required this.onThemeToggle});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _sheetController;
  late Animation<Offset> _slideAnimation;
  bool _isLearnMoreOpen = false;

  @override
  void initState() {
    super.initState();
    _sheetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(parent: _sheetController, curve: Curves.easeInOut),
        );
  }

  @override
  void dispose() {
    _sheetController.dispose();
    super.dispose();
  }

  void _openLearnMore() {
    setState(() => _isLearnMoreOpen = true);
    _sheetController.forward();
  }

  void _closeLearnMore() {
    _sheetController.reverse().then((_) {
      if (mounted) setState(() => _isLearnMoreOpen = false);
    });
  }

  // Navigate to login — use push so the user can't go back to landing
  void _goToLogin() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AuthPage(onThemeToggle: widget.onThemeToggle),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Stack(
        children: [
          _buildLandingContent(isDarkMode),
          if (_isLearnMoreOpen) ...[
            // Dim backdrop
            GestureDetector(
              onTap: _closeLearnMore,
              child: Container(color: Colors.black54),
            ),
            // Slide-up sheet
            SlideTransition(
              position: _slideAnimation,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _buildLearnMoreSheet(isDarkMode),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Landing content ───────────────────────────────────────────────────────

  Widget _buildLandingContent(bool isDarkMode) {
    return SizedBox.expand(
      child: Stack(
        children: [
          // Background image
          Image.asset(
            isDarkMode ? 'assets/LP_darkmode.png' : 'assets/LP_lightmode.png',
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
          ),

          // Foreground
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 70),

                // Logo
                SvgPicture.asset(
                  isDarkMode ? 'assets/logo_dark.svg' : 'assets/logo_light.svg',
                  height: 100,
                ),

                const SizedBox(height: 12),

                // Tagline
                Text(
                  'Smart pig monitoring for healthier \npig farm.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    color: isDarkMode ? Colors.white70 : Colors.black54,
                    height: 1.5,
                  ),
                ),

                const SizedBox(height: 300),

                // Buttons
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      // Get Started → goes to login
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _goToLogin,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2979FF),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Get Started',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 12),

                      // Learn More → slide-up sheet
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: OutlinedButton(
                          onPressed: _openLearnMore,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: isDarkMode
                                ? Colors.white
                                : Colors.black87,
                            side: BorderSide(
                              color: isDarkMode
                                  ? Colors.white38
                                  : Colors.black26,
                              width: 1.5,
                            ),
                            backgroundColor: isDarkMode
                                ? Colors.black26
                                : Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: const Text(
                            'Learn More',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Learn More sheet ──────────────────────────────────────────────────────

  Widget _buildLearnMoreSheet(bool isDarkMode) {
    final bgColor = isDarkMode ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final subtitleColor = isDarkMode ? Colors.white60 : Colors.black54;

    return Container(
      width: double.infinity,
      height: MediaQuery.of(context).size.height * 0.80,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDarkMode ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'About PRISM 🌡️',
                  style: TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                IconButton(
                  onPressed: _closeLearnMore,
                  icon: Icon(Icons.close, color: subtitleColor),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'What is PRISM?',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'PRISM is a smart pig monitoring system designed to help '
                    'farmers monitor the health, environment, and overall well-being '
                    'of their pigs in real time. Through IoT-powered technology, the '
                    'application tracks body temperature and environmental humidity, '
                    'while also providing a smart cooling system to help regulate heat '
                    'when necessary. PRISM also allows farmers to manage feeding and '
                    'medication records, while offering insights and recommendations '
                    'to support better farm management and improve livestock care.',
                    textAlign: TextAlign.justify,
                    style: TextStyle(
                      fontSize: 14,
                      color: subtitleColor,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Key Features',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildFeatureItem(
                    icon: Icons.monitor_heart_outlined,
                    title: 'Real-time Monitoring',
                    description:
                        'Track pigs body temperature and environmental humidity in real time to ensure optimal conditions.',
                    textColor: textColor,
                    subtitleColor: subtitleColor,
                  ),
                  _buildFeatureItem(
                    icon: Icons.ac_unit_outlined,
                    title: 'Remote Cooling Control',
                    description:
                        'Control the cooling system remotely to maintain optimal temperatures.',
                    textColor: textColor,
                    subtitleColor: subtitleColor,
                  ),
                  _buildFeatureItem(
                    icon: Icons.notifications_outlined,
                    title: 'Smart Alerts',
                    description:
                        'Get notified instantly when something needs your attention.',
                    textColor: textColor,
                    subtitleColor: subtitleColor,
                  ),
                  _buildFeatureItem(
                    icon: Icons.bar_chart_outlined,
                    title: 'Analytics & Reports',
                    description:
                        'View trends and historical data to make informed decisions.',
                    textColor: textColor,
                    subtitleColor: subtitleColor,
                  ),
                  _buildFeatureItem(
                    icon: Icons.recommend_outlined,
                    title: 'Smart Recommendations',
                    description:
                        'Get personalized insights and suggestions based on your farm data.',
                    textColor: textColor,
                    subtitleColor: subtitleColor,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem({
    required IconData icon,
    required String title,
    required String description,
    required Color textColor,
    required Color subtitleColor,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF2979FF).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: const Color(0xFF2979FF), size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 13,
                    color: subtitleColor,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
