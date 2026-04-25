import 'package:flutter/material.dart';

class EditMyProfileButton extends StatelessWidget {
  final String label;
  final Color backgroundColor;
  final Color textColor;
  final BorderRadius borderRadius;
  final VoidCallback onTap; // This is the logic "bridge" to the parent

  const EditMyProfileButton({
    super.key,
    required this.label,
    required this.backgroundColor,
    required this.textColor,
    required this.borderRadius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap, // Executes the logic passed from MyProfile
      borderRadius: borderRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: borderRadius,
          // Optional: Add the subtle shadow seen in your screenshot
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: textColor,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
