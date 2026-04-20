import 'package:flutter/material.dart';

class AppTopBar extends StatelessWidget {
  final bool isDark;
  final bool showBackButton; // New parameter

  const AppTopBar({
    super.key,
    required this.isDark,
    this.showBackButton = false, // Default is the Menu icon
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // DYNAMIC ICON LOGIC
        Builder(
          builder: (context) => IconButton(
            icon: Icon(
              showBackButton ? Icons.arrow_back : Icons.menu,
              color: isDark ? Colors.white : Colors.black,
              size: 28,
            ),
            onPressed: () {
              if (showBackButton) {
                Navigator.of(context).pop();
              } else {
                Scaffold.of(context).openDrawer();
              }
            },
          ),
        ),

        // LOGO
        Image.asset(
          isDark ? 'assets/logo_dark.png' : 'assets/logo_light.png',
          height: 40,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.business,
            size: 40,
            color: isDark ? Colors.white24 : Colors.grey,
          ),
        ),
      ],
    );
  }
}
