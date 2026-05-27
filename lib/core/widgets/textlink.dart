import 'package:flutter/material.dart';

class CustomTextLink extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color? color;

  const CustomTextLink({
    super.key,
    required this.text,
    required this.onPressed,
    this.color, // Defaults to the blue used in your reference, but can be overridden
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color ?? const Color(0xFF3B82F6),
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}