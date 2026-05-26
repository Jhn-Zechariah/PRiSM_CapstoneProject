import 'package:flutter/material.dart';

class CustomFeatureHeader extends StatelessWidget {
  final String title;
  final IconData icon;

  // This allows you to pass any button (Add, Filter, etc.) on the right side.
  // If you don't pass anything, it just shows the title and icon!
  final Widget? trailing;

  const CustomFeatureHeader({
    super.key,
    required this.title,
    required this.icon,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contentColor = isDark ? Colors.white : Colors.black;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 32,
              color: contentColor,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: contentColor,
              ),
            ),
          ],
        ),

        // Safely display the trailing widget if one was provided
        if (trailing != null) trailing!,
      ],
    );
  }
}