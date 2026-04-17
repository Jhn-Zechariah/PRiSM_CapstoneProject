import 'package:flutter/material.dart';

class SocialLoginButton extends StatelessWidget {
  final String asset;
  final String label;
  final bool isDarkMode;
  final VoidCallback onTap;

  const SocialLoginButton({
    super.key,
    required this.asset,
    required this.label,
    required this.isDarkMode,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        decoration: BoxDecoration(
          border: Border.all(color: isDarkMode ? Colors.white24 : Colors.black12),
          borderRadius: BorderRadius.circular(20),
          color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset(
              asset,
              width: 25,
              height: 25,
              errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.login, size: 25),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
      ),
    );
  }
}