import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? labelText;
  final double? border;
  final IconData? prefixIcon;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final bool enabled;
  final String? label;

  // 👇 1. Add these new optional fields
  final TextInputType keyboardType;
  final EdgeInsetsGeometry? contentPadding;
  final bool filled;
  final Color? fillColor;

  const CustomTextField({
    super.key,
    required this.controller,
    this.labelText,
    this.border,
    this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.enabled = true,
    this.label,
    // 👇 2. Initialize them
    this.keyboardType = TextInputType.text,
    this.contentPadding,
    this.filled = false,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4), // adjusted padding slightly
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 13, // Matches your pig screen label size
                fontWeight: FontWeight.w500,
                color: enabled
                    ? (isDarkMode ? Colors.white70 : Colors.black87)
                    : (isDarkMode ? Colors.white54 : Colors.grey[600]),
              ),
            ),
          ),
        ],

        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          enabled: enabled,
          keyboardType: keyboardType, //Apply the keyboard type
          style: TextStyle(
            fontSize: 14,
            color: enabled
                ? (isDarkMode ? Colors.white : Colors.black87)
                : (isDarkMode ? Colors.white54 : Colors.grey[600]),
          ),
          decoration: InputDecoration(
            labelText: labelText,
            labelStyle: TextStyle(
              color: isDarkMode ? Colors.white60 : Colors.black54,
            ),
            // Apply the new styling fields
            isDense: contentPadding != null,
            contentPadding: contentPadding,
            filled: filled,
            fillColor: fillColor,
            prefixIcon: prefixIcon != null
                ? Icon(
              prefixIcon,
              color: isDarkMode ? Colors.white60 : Colors.black54,
            )
                : null,
            suffixIcon: suffixIcon,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(border ?? 30),
              borderSide: BorderSide(
                color: isDarkMode ? Colors.white24 : Colors.black26,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(border ?? 30),
              borderSide: const BorderSide(color: Colors.blue), // Added focus color
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(border ?? 30)),
          ),
        ),
      ],
    );
  }
}