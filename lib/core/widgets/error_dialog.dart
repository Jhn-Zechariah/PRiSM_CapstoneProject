import 'package:flutter/material.dart';

class CustomErrorDialog {
  static void show({
    required BuildContext context,
    required String message,
    String title = 'Missing Information',
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF002D44))),
          ),
        ],
      ),
    );
  }
}