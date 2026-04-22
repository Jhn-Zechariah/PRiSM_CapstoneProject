import 'package:flutter/material.dart';

class AppTopBar extends StatelessWidget {
  final String? title;
  final bool showBackButton; // New parameter

  const AppTopBar({super.key, this.title, this.showBackButton = false});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Builder(
          builder: (context) => IconButton(
            icon: Icon(
              Icons.menu,
              color: isDarkMode ? Colors.white : Colors.black,
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
        Expanded(
          child: Center(
            child: title != null
                ? Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
        Image.asset(
          isDarkMode ? 'assets/logo_dark.png' : 'assets/logo_light.png',
          height: 40,
          errorBuilder: (context, error, stackTrace) => Icon(
            Icons.business,
            size: 40,
            color: isDarkMode ? Colors.white24 : Colors.grey,
          ),
        ),
      ],
    );
  }
}
