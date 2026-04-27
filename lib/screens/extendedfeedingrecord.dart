import 'package:flutter/material.dart';

// A read-only two-column preview widget displaying a pig's feeding record info.
// Intended to be embedded inside an expanded pig card on the feeding record screen.
class FeedingRecordExpandedPreview extends StatelessWidget {
  // Display name of the pig this preview belongs to
  final String pigName;

  // Accent color associated with the pig (used by the parent card's left strip)
  final Color pigColor;

  const FeedingRecordExpandedPreview({
    super.key,
    required this.pigName,
    required this.pigColor,
  });

  @override
  Widget build(BuildContext context) {
    // Detect theme brightness for conditional label color
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // ── Left column: Breed and Type of feed labels ────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Breed:', isDark),
              const SizedBox(height: 6),
              _label('Type of feed:', isDark),
            ],
          ),
        ),

        // ── Right column: Stage and Amount of feeds labels ────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _label('Stage:', isDark),
              const SizedBox(height: 6),
              _label('Amount of feeds:', isDark),
            ],
          ),
        ),
      ],
    );
  }

  /// Builds a small muted label that adapts its color to the current theme
  Widget _label(String text, bool isDark) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        // Softer white in dark mode, grey in light mode
        color: isDark ? Colors.white60 : Colors.grey,
      ),
    );
  }
}