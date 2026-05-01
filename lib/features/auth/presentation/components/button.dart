import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color? color;
  final Color? backgroundColor;
  final double? border;
  final bool? borderColor;

  const CustomButton({
    super.key,
    required this.text,
    required this.onPressed,
    this.border,
    this.backgroundColor,
    this.color,
    this.borderColor = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        elevation: 5, // Adjust for shadow depth
        shadowColor: Colors.black,
        minimumSize: const Size(double.infinity, 50),
        backgroundColor: backgroundColor ?? (isDarkMode ? Colors.amber : Colors.blue),
        foregroundColor: color ?? (isDarkMode ? Colors.black : Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(border ?? 30), // Update this
        ),
        disabledBackgroundColor: Colors.grey[400],
        side: borderColor == true ? BorderSide(color: Colors.black54) : null,
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
    );
  }
}
