import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

enum TextType { username, email, custom }

class CustomText extends StatelessWidget {
  final TextType type;
  final String? text;
  final double fontSize;
  final FontWeight? fontWeight;
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
    // Detect theme
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return StreamBuilder<User?>(
      // userChanges() listens specifically for profile updates like displayName
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        final user = snapshot.data;

        // If the stream hasn't fired yet, use the current instance as a fallback
        final currentUser = user ?? FirebaseAuth.instance.currentUser;

        final username = currentUser?.displayName ?? "Admin";
        final email = currentUser?.email ?? "No email";

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
            fontWeight: fontWeight ?? FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        );
      },
    );
  }
}