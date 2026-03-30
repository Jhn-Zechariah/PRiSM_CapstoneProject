import 'package:flutter/material.dart';

class AppTopBar extends StatelessWidget {
  final bool isDark;

  const AppTopBar({super.key, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Builder(
          builder: (context) => IconButton(
            icon: Icon(
              Icons.menu,
              color: isDark ? Colors.white : Colors.black,
              size: 28,
            ),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
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
