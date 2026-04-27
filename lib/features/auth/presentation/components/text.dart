import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum TextType { username, email, custom }

class CustomText extends StatelessWidget {
  final TextType type;
  final String? text;
  final double fontSize;
  final FontWeight? fontWeight; // optional override
  final String? prefix;

  const CustomText({
    super.key,
    required this.type,
    this.text,
    this.fontSize = 16,
    this.fontWeight,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    final username = user?.displayName ?? "Admin";
    final email = user?.email ?? "No email";

    // detect theme
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String displayText;

    switch (type) {
      case TextType.username:
        displayText = "${prefix ?? ""}$username";
        break;
      case TextType.email:
        displayText = "${prefix ?? ""}$email";
        break;
      case TextType.custom:
        displayText = text ?? "";
        break;
    }

    return Text(
      displayText,
      style: TextStyle(
        fontSize: fontSize,

        // 👇 permanent defaults
        fontWeight: fontWeight ?? FontWeight.bold,
        color: isDark ? Colors.white : Colors.black,
      ),
    );
  }
}
