import 'package:flutter/material.dart';
import 'package:prism_app/screens/splash_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // 1. Logic to track the current theme (Defaulting to system)
  ThemeMode _themeMode = ThemeMode.system;

  // 2. Function to switch between modes
  void toggleTheme() {
    setState(() {
      if (_themeMode == ThemeMode.light) {
        _themeMode = ThemeMode.dark;
      } else {
        _themeMode = ThemeMode.light;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      
      // Light Theme Definition
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),

      // Dark Theme Definition
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),

      // 3. Use the variable here instead of a hardcoded mode
      themeMode: _themeMode,
      
      // 4. Pass the toggle function down so Dashboard can use it
      home: SplashScreen(onThemeToggle: toggleTheme),
    );
  }
}