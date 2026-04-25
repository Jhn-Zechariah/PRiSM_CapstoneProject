import 'package:flutter/material.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String? labelText; // The label inside the field
  final IconData? prefixIcon;
  final bool obscureText;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final bool enabled;
  final String? label; // The title above the field

  const CustomTextField({
    super.key,
    required this.controller,
    this.labelText,
    this.prefixIcon,
    this.obscureText = false,
    this.suffixIcon,
    this.validator,
    this.enabled = true,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // Aligns text to the left
      mainAxisSize: MainAxisSize.min, // Prevents the column from taking infinite height
      children: [
        // 👇 Conditionally show the label if it was provided
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 17),
            child: Text(
              label!, // Use ! because we already checked if it's null
              style: TextStyle(
                fontWeight: FontWeight.w500,
                // Map your _isEditing logic directly to the 'enabled' property
                color: enabled
                    ? (isDarkMode ? Colors.white : Colors.black)
                    : (isDarkMode ? Colors.white54 : Colors.grey[600]),
              ),
            ),
          ),
          // Space between your new label and the text field
        ],

        // 👇 Your existing text field
        TextFormField(
          controller: controller,
          obscureText: obscureText,
          validator: validator,
          enabled: enabled,
          style: TextStyle(
            color: enabled
                ? (isDarkMode ? Colors.white : Colors.black)
                : (isDarkMode ? Colors.white54 : Colors.grey[600]),
          ),
          decoration: InputDecoration(
            labelText: labelText,
            labelStyle: TextStyle(
              color: isDarkMode ? Colors.white60 : Colors.black54,
            ),
            prefixIcon: prefixIcon != null
                ? Icon(
              prefixIcon,
              color: isDarkMode ? Colors.white60 : Colors.black54,
            )
                : null,
            suffixIcon: suffixIcon,

            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(30),
              borderSide: BorderSide(
                color: isDarkMode ? Colors.white24 : Colors.black12,
              ),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
          ),
        ),
      ],
    );
  }
}