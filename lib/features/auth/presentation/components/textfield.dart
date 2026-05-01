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
  final bool readonly;
  final VoidCallback? onTap;
  final TextInputType keyboardType;
  final EdgeInsetsGeometry? contentPadding;
  final Color? fillColor;
  final Color? borderColor;

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
    this.onTap,
    this.keyboardType = TextInputType.text,
    this.contentPadding,
    this.fillColor,
    this.borderColor,
    this.readonly = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // 'readonly' will ONLY block the keyboard, it won't change the colors.
    final bool isDisabled = !enabled;

    // Colors are now driven strictly by the isDisabled flag
    final resolvedTextColor = isDisabled
        ? (isDarkMode ? Colors.white54 : Colors.grey[500])
        : (isDarkMode ? Colors.white : Colors.black87);

    final resolvedFillColor = fillColor ?? (isDisabled
        ? (isDarkMode ? const Color(0xFF1E1E1E) : Colors.grey[200])
        : (isDarkMode ? const Color(0xFF2A2A2A) : Colors.white));

    final resolvedBorderColor = borderColor ?? (isDisabled
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
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDisabled
                    ? (isDarkMode ? Colors.white54 : Colors.grey[600])
                    : (isDarkMode ? Colors.white70 : Colors.black87),
              ),
            ),
          ),
        ],

        Material(
          elevation: isDisabled ? 2 : 5,
          color: Colors.transparent,
          shadowColor: Colors.grey,
          borderRadius: BorderRadius.circular(border ?? 30),
          child: TextFormField(
            controller: controller,
            obscureText: obscureText,
            // Native readOnly still blocks the keyboard beautifully
            readOnly: readonly,
            onTap: onTap,
            validator: validator,
            enabled: enabled,
            keyboardType: keyboardType,
            style: TextStyle(
              fontSize: 14,
              color: resolvedTextColor,
            ),
            decoration: InputDecoration(
              labelText: labelText,
              labelStyle: TextStyle(
                color: isDarkMode ? Colors.white60 : Colors.black54,
              ),
              isDense: contentPadding != null,
              contentPadding: contentPadding,
              filled: true,
              fillColor: resolvedFillColor,
              prefixIcon: prefixIcon != null
                  ? Icon(
                prefixIcon,
                color: isDisabled
                    ? (isDarkMode ? Colors.white30 : Colors.grey[400])
                    : (isDarkMode ? Colors.white60 : Colors.black54),
              )
                  : null,
              suffixIcon: suffixIcon,
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
                  color: isDisabled ? resolvedBorderColor : Colors.blue,
                ),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(border ?? 30),
              ),
            ),
          ),
        ),
      ],
    );
  }
}