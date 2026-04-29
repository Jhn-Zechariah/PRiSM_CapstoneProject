import 'package:flutter/material.dart';

class PigMedCard extends StatelessWidget {
  final dynamic pig;
  final Color accentColor;
  final VoidCallback onAdd;

  const PigMedCard({
    super.key,
    required this.pig,
    required this.accentColor,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    // Dynamic Colors based on Theme
    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color;
    final labelColor = theme.textTheme.bodySmall?.color;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        // Subtle border for Dark Mode, grey border for Light Mode
        border: Border.all(
          color: isDarkMode ? theme.dividerColor : Colors.grey.shade200,
        ),
        // Adding the shadow seen in your image for Light Mode
        boxShadow: isDarkMode
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The colored accent bar on the left
              Container(width: 8, color: accentColor),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              pig.name,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight:
                                    FontWeight.w800, // Matching the bold look
                                color: textColor,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            RichText(
                              text: TextSpan(
                                style: TextStyle(
                                  fontSize: 13,
                                  color: labelColor,
                                ),
                                children: [
                                  const TextSpan(text: 'Recent intake: '),
                                  TextSpan(
                                    text: 'None', // Or your dynamic value
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: isDarkMode
                                          ? Colors.white70
                                          : Colors.black54,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Add Button
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: onAdd,
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              // Using a slightly more visible background for the icon
                              color: accentColor.withValues(
                                alpha: isDarkMode ? 0.2 : 0.1,
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              Icons.add,
                              size: 24,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
