import 'package:flutter/material.dart';

class CustomDropdown extends StatelessWidget {
  final String? label; // The title above the dropdown
  final String? value; // The currently selected value
  final List<String> items; // The list of options
  final void Function(String?)? onChanged; // What happens when they pick an option
  final double? border;
  final EdgeInsetsGeometry? contentPadding;
  final bool filled;
  final Color? fillColor;
  final String? labelText; // The label inside the field (optional)

  // 👇 1. Add the validator property
  final String? Function(String?)? validator;

  const CustomDropdown({
    super.key,
    this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.border,
    this.contentPadding,
    this.filled = false,
    this.fillColor,
    this.labelText,
    // 👇 2. Add it to the constructor
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // Conditionally show the label above the field
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
        ],

        // The actual Dropdown field
        DropdownButtonFormField<String>(
          initialValue: value,
          isDense: true,
          // 👇 3. Pass the validator to the DropdownButtonFormField
          validator: validator,
          dropdownColor: fillColor ?? (isDarkMode ? const Color(0xFF2A2A2A) : Colors.white),
          style: TextStyle(
            fontSize: 14,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
          decoration: InputDecoration(
            labelText: labelText,
            labelStyle: TextStyle(
              color: isDarkMode ? Colors.white60 : Colors.black54,
            ),
            isDense: contentPadding != null,
            contentPadding: contentPadding,
            filled: filled,
            fillColor: fillColor,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(border ?? 30),
              borderSide: BorderSide(
                color: isDarkMode ? Colors.white24 : Colors.black26,
              ),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(border ?? 30),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(border ?? 30),
              borderSide: const BorderSide(color: Colors.blue),
            ),
          ),
          icon: Icon(
            Icons.arrow_drop_down,
            size: 20,
            color: isDarkMode ? Colors.white54 : Colors.black54,
          ),
          items: items.map((String item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(item),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}