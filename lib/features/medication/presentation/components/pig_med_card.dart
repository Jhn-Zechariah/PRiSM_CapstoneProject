import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/medication/presentation/components/medicine_intake_dialog.dart';

import '../../domain/model/app_medicine_stock.dart';
import '../../domain/model/app_medicine_intake.dart';
import '../cubits/medicine_cubit.dart';


enum PigMedAction { medicine, vaccine, vitamin }

class PigMedCard extends StatelessWidget {
  final dynamic pig;
  final Color accentColor;
  final VoidCallback onAdd;
  final MedicineIntake? recentIntake; // 🔹 Added this to accept the recent intake data

  const PigMedCard({
    super.key,
    required this.pig,
    required this.accentColor,
    required this.onAdd,
    this.recentIntake, // 🔹 Optional, so it defaults to null if there are no records
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    final cardColor = theme.cardColor;
    final textColor = theme.textTheme.bodyLarge?.color;
    final labelColor = theme.textTheme.bodySmall?.color;
    final subtleTextColor = theme.textTheme.bodyMedium?.color;

    // + button colors adapt to theme
    final buttonBg = isDarkMode
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.06);
    final buttonIconColor = isDarkMode ? Colors.white : Colors.black87;
    final buttonSplashColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.black.withValues(alpha: 0.06);

    // 🔹 Logic to format the recent intake display
    String recentIntakeDisplay = 'None';
    if (pig.lastIntakeDate != null && pig.lastIntakeName != null) {
      final dateString = "${pig.lastIntakeDate!.toLocal()}".split(' ')[0];
      recentIntakeDisplay = '$dateString • ${pig.lastIntakeName}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkMode ? theme.dividerColor : Colors.grey.shade200,
        ),
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
              // Left accent stripe
              Container(width: 8, color: accentColor),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      // Pig name + recent intake
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${pig.breed} | ${pig.displayId}',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
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
                                    text: recentIntakeDisplay, // 🔹 Now displays the formatted data
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: subtleTextColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // + button — fully theme-aware
                      PopupMenuButton<PigMedAction>(
                        onSelected: (action) async {
                          String selectedType = '';
                          if (action == PigMedAction.medicine) selectedType = 'Medicine';
                          if (action == PigMedAction.vitamin) selectedType = 'Vitamin';
                          if (action == PigMedAction.vaccine) selectedType = 'Vaccine';



                          // Open the dialog and await the result map
                          final result = await showDialog<Map<String, dynamic>>(
                            context: context,
                            builder: (dialogContext) => BlocProvider.value(
                              value: context.read<MedicineCubit>(),
                              child: MedicineIntakeDialog(
                                accentColor: accentColor,
                                intakeType: selectedType,
                                pigId: pig.pigId,
                              ),
                            ),
                          );

                          // If the dialog returned data (user hit Save), trigger the Cubit
                          if (result != null && context.mounted) {
                            context.read<MedicineCubit>().addIntakeAndReduceStock(
                              intake: result['intake'] as MedicineIntake,
                              selectedStock: result['selectedStock'] as MedicineStock,
                              medicineId: result['medicineId'] as String,
                            );
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: PigMedAction.medicine,
                            child: Text('Medicine'),
                          ),
                          const PopupMenuItem(
                            value: PigMedAction.vitamin,
                            child: Text('Vitamins'),
                          ),
                          const PopupMenuItem(
                            value: PigMedAction.vaccine,
                            child: Text('Vaccine'),
                          ),
                        ],
                        child: Material(
                          color: buttonBg,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            splashColor: buttonSplashColor,
                            highlightColor: buttonSplashColor,
                            child: SizedBox(
                              width: 40,
                              height: 40,
                              child: Icon(
                                Icons.add,
                                size: 24,
                                color: buttonIconColor,
                              ),
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