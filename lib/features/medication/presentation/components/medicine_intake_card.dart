import 'package:flutter/material.dart';
class IntakeHistoryCard extends StatelessWidget {
  final String pigId;
  final String medName;
  final String dosage;
  final DateTime date;
  final String notes;
  final Color accentColor;
  final bool isDark;

  const IntakeHistoryCard({
    super.key,
    required this.pigId,
    required this.medName,
    required this.dosage,
    required this.date,
    required this.notes,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    // Basic date formatting (YYYY-MM-DD)
    final formattedDate = "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 10,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pigId,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoRow('Medicine: ', medName),
                        ),
                        Expanded(
                          child: _buildInfoRow('Dosage: ', dosage),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildInfoRow('Date: ', formattedDate),

                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildInfoRow('Notes: ', notes),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Helper widget to keep the layout clean
  Widget _buildInfoRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.white60 : Colors.black54,
        ),
        children: [
          TextSpan(text: label),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}