import 'package:flutter/material.dart';

class MedicineCard extends StatelessWidget {
  final String name;
  final String category;
  final int stock;
  final String expiryDate;
  final String status;

  const MedicineCard({
    super.key,
    required this.name,
    required this.category,
    required this.stock,
    required this.expiryDate,
    required this.status,
  });

  // Helper to determine status color (works fine in both modes)
  Color _getStatusColor() {
    switch (status.toLowerCase()) {
      case "high":
        return Colors.green;
      case "average":
        return Colors.orange;
      case "low":
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1. Get current theme data
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _getStatusColor();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        // 2. Use surface color for the card background
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        // 3. Use outline or divider color for the border
        border: Border.all(color: theme.dividerColor),
        boxShadow: [
          if (theme.brightness == Brightness.light)
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // HEADER ROW
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  // text color automatically switches based on theme
                ),
              ),
              Icon(
                Icons.grid_view,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),

          const SizedBox(height: 8),

          // 4. Use onSurfaceVariant for secondary/subtitle text
          _buildInfoText("Category", category, theme),
          _buildInfoText("Stocks", stock.toString(), theme),
          _buildInfoText("Expiry date", expiryDate, theme),

          const SizedBox(height: 10),

          // STATUS BADGE
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              // Using Opacity that works well in both modes
              color: statusColor.withAlpha(40),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Helper to keep text styling consistent
  Widget _buildInfoText(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(
              text: "$label: ",
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ],
        ),
      ),
    );
  }
}
