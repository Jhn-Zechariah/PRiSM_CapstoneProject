import 'package:flutter/material.dart';

class CustomSnackbar {
  /// Shows a customized floating snackbar.
  /// [isError] overrides the theme to show a red error style.
  /// [backgroundColor] and [messageColor] override the default theme colors if provided.
  static void show({
    required BuildContext context,
    required String message,
    bool isError = false,
    Color? backgroundColor,
    Color? messageColor,
  }) {
    // 1. Check the current theme
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // 2. Set default background color (Error > Custom > Theme Default)
    final defaultBgColor = isError
        ? Colors.red.shade600
        : Colors.green.shade600;

    final finalBgColor = backgroundColor ?? defaultBgColor;

    // 3. Set default text/icon color (Error > Custom > Theme Default)
    final defaultTextColor = isError
        ? Colors.white
        : (isDarkMode ? Colors.white : Colors.black87);

    final finalTextColor = messageColor ?? defaultTextColor;

    final snackBar = SnackBar(
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.only(top: 16,bottom: 20,left: 16,right: 16),
      elevation: 6,
      backgroundColor: finalBgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
      duration: const Duration(seconds: 3),
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: finalTextColor, // Applies the dynamic color to the icon
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: finalTextColor, // Applies the dynamic color to the text
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );

    // Hide any currently showing snackbar before showing the new one
    ScaffoldMessenger.of(context)
    //   ..hideCurrentSnackBar()
      .showSnackBar(snackBar);
  }
}