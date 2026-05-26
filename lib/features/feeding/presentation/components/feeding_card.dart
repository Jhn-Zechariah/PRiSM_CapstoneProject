import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../pig_management/domain/model/app_pig.dart';
import '../cubits/feeding_record_cubit.dart';
import '../pages/pigfeedcardpopup.dart';
import '../pages/extendedfeedingrecord.dart';

class FeedingCard extends StatelessWidget {
  final AppPig pig;
  final Color color;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const FeedingCard({
    super.key,
    required this.pig,
    required this.color,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        // Matching the PigProfileCard shadow!
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      // Using ClipRRect to properly clip the color stripe just like PigProfileCard
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Matching the 12px width stripe
              Container(width: 12, color: color),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 12, bottom: 16, right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // TOP ROW: Name and Icons
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${pig.breed} | ${pig.displayId}',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          Row(
                            children: [
                              // Only show the "+" add button if the card is expanded
                              if (isExpanded) ...[
                                GestureDetector(
                                  onTap: () {
                                    // 1. Grab the Cubit FIRST
                                    final feedingCubit = context.read<FeedingRecordCubit>();

                                    showDialog(
                                      context: context,
                                      builder: (dialogContext) {
                                        // 2. Pass it into the dialog
                                        return BlocProvider.value(
                                          value: feedingCubit,
                                          child: PigFeedCardPopUp(
                                            pigId: pig.pigId,
                                            pigColor: color,
                                          ),
                                        );
                                      },
                                    );
                                  },
                                  child: Icon(Icons.add, size: 26, color: textColor),
                                ),
                                const SizedBox(width: 12),
                              ],
                              // Expand/Collapse Chevron
                              GestureDetector(
                                onTap: onToggleExpand,
                                child: Icon(
                                  isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                  size: 28,
                                  color: textColor,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),

                      // EXPANDED CONTENT
                      if (isExpanded) ...[
                        const SizedBox(height: 12),
                        FeedingRecordExpandedPreview(
                          pig: pig,
                          pigColor: color,
                        ),
                      ],
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