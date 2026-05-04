import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/snackbar.dart';
import '../pages/pig_information.dart';
import '../pages/update_pig_weight_dialog.dart';
import '../../domain/model/app_pig.dart';
import '../cubits/pig_cubit.dart';

enum PigMenuAction { info, updateWeight }

class PigProfileCard extends StatelessWidget {
  final AppPig pig;
  final Color accentColor;
  final bool isDarkMode;

  const PigProfileCard({
    super.key,
    required this.pig,
    required this.accentColor,
    required this.isDarkMode,
  });

  // Helper to calculate age from birthDate
  String _calculateAge(DateTime birthDate) {
    final days = DateTime.now().difference(birthDate).inDays;
    if (days < 30) return '$days days';
    final months = days ~/ 30;
    return '$months months';
  }

  // 👇 MOVED INSIDE THE CLASS: Helper to determine status color
  Color _getStatusColor(String status, bool isDarkMode) {
    final lowerStatus = status.toLowerCase();

    if (lowerStatus == 'normal/healthy' || lowerStatus == 'sold') {
      return isDarkMode ? Colors.greenAccent : Colors.green.shade700;
    } else if (lowerStatus == 'abnormal/sick') {
      return isDarkMode ? Colors.redAccent : Colors.red.shade700;
    } else if (lowerStatus == 'deceased') {
      return isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;
    }

    // Default color if it doesn't match the above
    return isDarkMode ? Colors.orangeAccent : Colors.orange.shade800;
  }

  // Action menu (the 3 dots on the right side)
  void _handleMenuAction(BuildContext context, PigMenuAction action) async {
    final pigCubit = context.read<PigCubit>();

    switch (action) {
      case PigMenuAction.info:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PigInformationScreen(existingPig: pig),
          ),
        );
        break;

      case PigMenuAction.updateWeight:
        final newWeight = await showDialog<double>(
          context: context,
          builder: (_) => UpdatePigWeightDialog(
            pigLabel: '${pig.breed} | ${pig.displayId}',
            currentWeight: pig.currentWeightKg,
            accentColor: accentColor,
          ),
        );

        if (newWeight != null) {
          pigCubit.updateWeight(pig.pigId, newWeight);

          // VERY IMPORTANT: Check if the widget is still on screen!
          if (!context.mounted) return;
          CustomSnackbar.show(
            context: context,
            message: "Weight updated to $newWeight kg",
          );
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final labelColor = isDarkMode ? Colors.white70 : Colors.black54;

    // Check if the pig is inactive based on status
    final statusLower = pig.status.toLowerCase();
    final isInactive = statusLower == 'sold' || statusLower == 'deceased';

    final displayAccentColor = isInactive ? Colors.grey.shade600 : accentColor;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Dynamic Accent Color Stripe
              Container(width: 12, color: displayAccentColor),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 12, bottom: 16, right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${pig.breed} | ${pig.displayId}',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor),
                          ),
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: PopupMenuButton<PigMenuAction>(
                              padding: EdgeInsets.zero,
                              icon: Icon(Icons.more_vert, color: textColor),
                              onSelected: (action) => _handleMenuAction(context, action),
                              itemBuilder: (BuildContext context) {
                                if (isInactive) {
                                  // Show ONLY "View Pig Information" if inactive
                                  return [
                                    const PopupMenuItem(
                                      value: PigMenuAction.info,
                                      child: Text('View Pig Information'),
                                    ),
                                  ];
                                }
                                // Show both if active
                                return [
                                  const PopupMenuItem(
                                    value: PigMenuAction.info,
                                    child: Text('Edit Pig Information'),
                                  ),
                                  const PopupMenuItem(
                                    value: PigMenuAction.updateWeight,
                                    child: Text('Update Pig Weight'),
                                  ),
                                ];
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoText('Stage:', pig.stage, labelColor, textColor),
                                const SizedBox(height: 4),
                                _buildInfoText('Sex:', pig.sex, labelColor, textColor),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoText('Age:', _calculateAge(pig.birthDate), labelColor, textColor),
                                const SizedBox(height: 4),
                                _buildInfoText('Weight:', '${pig.currentWeightKg} kg', labelColor, textColor),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      Row(
                        children: [
                          Icon(Icons.edit_square, size: 14, color: textColor),
                          const SizedBox(width: 4),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'NOTE:  ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: textColor, // Keeps standard color
                                  ),
                                ),
                                TextSpan(
                                  text: pig.status,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _getStatusColor(pig.status, isDarkMode), // Applies dynamic color!
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: double.infinity,
                        constraints: const BoxConstraints(minHeight: 40),
                        margin: const EdgeInsets.only(right: 12),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDarkMode ? const Color(0xFF2A2A2A) : const Color(0xFFE0E0E0),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Text(
                          pig.notes,
                          style: TextStyle(fontSize: 13, color: textColor),
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

  Widget _buildInfoText(String label, String value, Color labelColor, Color textColor) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: '$label ', style: TextStyle(fontSize: 12, color: labelColor)),
          TextSpan(text: value, style: TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}