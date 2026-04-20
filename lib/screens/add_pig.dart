import 'package:flutter/material.dart';
import 'app_top_bar.dart';

class AddPig extends StatefulWidget {
  final VoidCallback onThemeToggle;

  const AddPig({super.key, required this.onThemeToggle});

  @override
  State<AddPig> createState() => _AddPigState();
}

class _AddPigState extends State<AddPig> {
  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTopBar(isDark: isDarkMode, showBackButton: true),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  //logo and title row
}
