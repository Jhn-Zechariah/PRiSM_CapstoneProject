import 'package:flutter/material.dart';

class CustomDropdown extends StatelessWidget {
  final String? label;
  final String? value;
  final List<String> items;
  final void Function(String?)? onChanged;
  final double? border;
  final EdgeInsetsGeometry? contentPadding;
  final Color? fillColor;
  final String? labelText;
  final Color? borderColor;
  final String? Function(String?)? validator;

  final bool enabled;
  final bool readonly;

  const CustomDropdown({
    super.key,
    this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.border,
    this.contentPadding,
    this.fillColor,
    this.labelText,
    this.borderColor,
    this.validator,
    this.enabled = true,
    this.readonly = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Create the master check
    final bool isDisabledOrReadOnly = !enabled || readonly;

    // Define the dynamic colors exactly like the CustomTextField
    final resolvedTextColor = isDisabledOrReadOnly
        ? (isDarkMode ? Colors.white54 : Colors.grey[500])
        : (isDarkMode ? Colors.white : Colors.black87);

    final resolvedFillColor = fillColor ?? (isDisabledOrReadOnly
        ? (isDarkMode ? const Color(0xFF1E1E1E) : Colors.grey[200])
        : (isDarkMode ? const Color(0xFF2A2A2A) : Colors.white));

    final resolvedBorderColor = borderColor ?? (isDisabledOrReadOnly
        ? (isDarkMode ? Colors.white12 : Colors.grey[300]!)
        : (isDarkMode ? Colors.white24 : Colors.black26));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (label != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                // Apply disabled color to the label
                color: isDisabledOrReadOnly
                    ? (isDarkMode ? Colors.white54 : Colors.grey[600])
                    : (isDarkMode ? Colors.white70 : Colors.black87),
              ),
            ),
          ),
        ],

        Material(
          // Drop the elevation if disabled
          elevation: isDisabledOrReadOnly ? 2 : 5,
          color: Colors.transparent,
          shadowColor: Colors.grey,
          borderRadius: BorderRadius.circular(border ?? 30),
          child: DropdownButtonFormField<String>(
            initialValue: value,
            isDense: true,
            validator: validator,
            dropdownColor: fillColor ?? (isDarkMode ? const Color(0xFF2A2A2A) : Colors.white),
            style: TextStyle(
              fontSize: 14,
              color: resolvedTextColor, // Apply text color
            ),
            decoration: InputDecoration(
              labelText: labelText,
              labelStyle: TextStyle(
                color: isDarkMode ? Colors.white60 : Colors.black54,
              ),
              isDense: contentPadding != null,
              contentPadding: contentPadding,
              filled: true,
              fillColor: resolvedFillColor, // Apply fill color

              // Define both enabled and disabled borders
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(border ?? 30),
                borderSide: BorderSide(color: resolvedBorderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(border ?? 30),
                borderSide: BorderSide(color: resolvedBorderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(border ?? 30),
                borderSide: BorderSide(
                  color: isDisabledOrReadOnly ? resolvedBorderColor : Colors.blue,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(border ?? 30),
              ),
            ),
            icon: Icon(
              Icons.arrow_drop_down,
              size: 20,
              // Grey out the dropdown arrow when disabled
              color: isDisabledOrReadOnly
                  ? (isDarkMode ? Colors.white30 : Colors.grey[400])
                  : (isDarkMode ? Colors.white54 : Colors.black54),
            ),
            items: items.map((String item) {
              return DropdownMenuItem<String>(
                value: item,
                child: Text(item),
              );
            }).toList(),
            // Crucial: passing null disables the dropdown natively in Flutter
            onChanged: isDisabledOrReadOnly ? null : onChanged,
          ),
        ),
      ],
    );
  }
}