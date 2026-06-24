import 'package:flutter/material.dart';

class MedicineCard extends StatelessWidget {
  final String name;
  final String unit;
  final String category;

  // FIX #7: Changed from int to double so fractional amounts (e.g. 2.5 mL)
  // are never silently truncated. The old int forced a lossy .round() at every
  // call site. Display formatting is now handled here in the widget.
  final double stock;

  final String expiryDate;
  final String status;
  final VoidCallback? onTap;
  final VoidCallback? onEditMedicine;
  final VoidCallback? onAddStock;

  const MedicineCard({
    super.key,
    required this.name,
    required this.unit,
    required this.category,
    required this.stock,
    required this.expiryDate,
    required this.status,
    this.onTap,
    this.onEditMedicine,
    this.onAddStock,
  });

  Color _getStatusColor() {
    switch (status.toLowerCase()) {
      case 'high':
        return Colors.green;
      case 'average':
        return Colors.orange;
      case 'low':
      case 'no stock':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  // FIX #7: Show whole numbers without a decimal point (e.g. "10 tablet"),
  // but keep one decimal place for fractional amounts (e.g. "2.5 mL").
  String get _formattedStock {
    if (stock % 1 == 0) {
      return '${stock.toStringAsFixed(0)} $unit';
    }
    return '${stock.toStringAsFixed(1)} $unit';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final statusColor = _getStatusColor();

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
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
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  onSelected: (String value) {
                    if (value == 'edit') {
                      onEditMedicine?.call();
                    } else if (value == 'add_stock') {
                      onAddStock?.call();
                    }
                  },
                  itemBuilder: (BuildContext context) => [
                    const PopupMenuItem<String>(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Edit Medicine'),
                        ],
                      ),
                    ),
                    const PopupMenuItem<String>(
                      value: 'add_stock',
                      child: Row(
                        children: [
                          Icon(Icons.add_box_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Add Stock'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const SizedBox(height: 8),

            _buildInfoText('Category', category, theme),
            _buildInfoText('Stocks', _formattedStock, theme),
            _buildInfoText('Expiry date', expiryDate, theme),

            const SizedBox(height: 10),

            // STATUS BADGE
            Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
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
      ),
    );
  }

  Widget _buildInfoText(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: theme.textTheme.bodyMedium,
          children: [
            TextSpan(
              text: '$label: ',
              style:
              TextStyle(color: theme.colorScheme.onSurfaceVariant),
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