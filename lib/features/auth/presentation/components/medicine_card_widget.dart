import 'package:flutter/material.dart';

class MedicineCard extends StatelessWidget {
  final String name;
  final String category;
  final int stock;
  final String expiryDate;
  final String status; // High, Average, Low

  const MedicineCard({
    super.key,
    required this.name,
    required this.category,
    required this.stock,
    required this.expiryDate,
    required this.status,
  });

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
    final color = _getStatusColor();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
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
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Icon(Icons.grid_view, size: 18),
            ],
          ),

          const SizedBox(height: 8),

          Text("Category: $category"),
          Text("Stocks: $stock"),
          Text("Expiry date: $expiryDate"),

          const SizedBox(height: 10),

          // STATUS BADGE
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status,
              style: TextStyle(color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }
}
