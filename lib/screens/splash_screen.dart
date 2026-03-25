import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  SplashScreenState createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  bool _appLoaded = false;
  bool _navigated = false;
  bool _animationDone = false;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3), // fallback duration
    );

    _loadApp();
  }

  Future<void> _loadApp() async {
    try {
      await Future.delayed(const Duration(seconds: 3));
    } finally {
      _appLoaded = true;
    }

    if (!mounted) return;

    setState(() {});
    _goNextIfReady();
  }

  void _goNextIfReady() {
    if (!mounted) return;
    if (_navigated || !_appLoaded || !_animationDone) return;

    _navigated = true;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    final animationPath = isDarkMode
        ? 'assets/lottie/prism_dark.json'
        : 'assets/lottie/prism.json';

    return Scaffold(
      body: Center(
        child: Lottie.asset(
          animationPath,
          controller: _controller,
          repeat: false,
          fit: BoxFit.contain,
          onLoaded: (composition) {
            _controller
              ..duration = composition.duration
              ..forward().whenComplete(() {
                if (!mounted) return;
                setState(() {
                  _animationDone = true;
                });
                _goNextIfReady();
              });
          },
        ),
      ),
    );
  }
}
