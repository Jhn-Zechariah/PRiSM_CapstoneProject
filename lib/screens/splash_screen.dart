import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'login_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => SplashScreenState();
}

class SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  bool _appLoaded = false;
  bool _animationDone = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _loadApp();
  }

  Future<void> _loadApp() async {
    try {
      // Replace this with your real loading logic
      await Future.delayed(const Duration(seconds: 3));
    } finally {
      _appLoaded = true;
      _goNextIfReady();
    }
  }

  void _goNextIfReady() {
    if (_navigated || !_appLoaded || !_animationDone || !mounted) return;

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
                _animationDone = true;
                _goNextIfReady();
              });
          },
        ),
      ),
    ); 
    
  }
} // dsfsd