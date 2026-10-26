import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/snackbar.dart';
import '../pages/pig_information.dart';
import '../pages/update_pig_weight_dialog.dart';
import '../../domain/model/app_pig.dart';
import '../cubits/pig_cubit.dart';


enum PigMenuAction { info, updateWeight }


// Shared by the profiles list and weight history so a pig keeps the same
// color on both screens (indexed by its position in the filtered list).
const List<Color> pigAccentColors = [
  Colors.red,
  Color(0xFF003366),
  Colors.orange,
];

Color pigAccentColor(int index) => pigAccentColors[index % pigAccentColors.length];


class PigProfileCard extends StatefulWidget {
  final AppPig pig;
  final Color accentColor;
  final bool isDarkMode;


  const PigProfileCard({
    super.key,
    required this.pig,
    required this.accentColor,
    required this.isDarkMode,
  });


  @override
  State<PigProfileCard> createState() => _PigProfileCardState();

}

class _PigProfileCardState extends State<PigProfileCard>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;


  String _calculateAge(DateTime birthDate) {
    final days = DateTime.now().difference(birthDate).inDays;
    if (days < 30) return '$days days';
    final months = days ~/ 30;
    return '$months months';
  }


  Color _getStatusColor(String status, bool isDarkMode) {
    final lowerStatus = status.toLowerCase();
    if (lowerStatus == 'normal/healthy' || lowerStatus == 'sold') {
      return isDarkMode ? Colors.greenAccent : Colors.green.shade700;
    } else if (lowerStatus == 'abnormal/sick') {
      return isDarkMode ? Colors.redAccent : Colors.red.shade700;
    } else if (lowerStatus == 'deceased') {
      return isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;
    }
    return isDarkMode ? Colors.orangeAccent : Colors.orange.shade800;
  }



  void _handleMenuAction(BuildContext context, PigMenuAction action) async {
    final pigCubit = context.read<PigCubit>();


    switch (action) {
      case PigMenuAction.info:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => PigInformationScreen(existingPig: widget.pig),
          ),
        );
        break;


      case PigMenuAction.updateWeight:
        final newWeight = await showDialog<double>(
          context: context,
          builder: (_) => UpdatePigWeightDialog(
            pigLabel: '${widget.pig.breed} | ${widget.pig.displayId}',
            currentWeight: widget.pig.currentWeightKg,
            accentColor: widget.accentColor,
          ),
        );


        if (newWeight != null) {
          try {
            await pigCubit.updateWeight(widget.pig.pigId, newWeight);
            if (!context.mounted) return;
            CustomSnackbar.show(
              context: context,
              message: "Weight updated to $newWeight kg",
            );
          } catch (e) {
            if (!context.mounted) return;
            CustomSnackbar.show(
              context: context,
              isError: true,
              message: "Failed to update weight. Please try again.",
            );
          }
        }
        break;
    }
  }


  @override
  Widget build(BuildContext context) {
    // Required when using AutomaticKeepAliveClientMixin
    super.build(context);

    final isDarkMode = widget.isDarkMode;
    final pig = widget.pig;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final labelColor = isDarkMode ? Colors.white70 : Colors.black54;


    final isInactive = pig.isInactive;
    final displayAccentColor = isInactive
        ? Colors.grey.shade600
        : widget.accentColor;


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
              // Accent stripe
              Container(width: 12, color: displayAccentColor),


              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 12,
                    top: 12,
                    bottom: 16,
                    right: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
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
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: PopupMenuButton<PigMenuAction>(
                              padding: EdgeInsets.zero,
                              icon: Icon(Icons.more_vert, color: textColor),
                              onSelected: (action) =>
                                  _handleMenuAction(context, action),
                              itemBuilder: (BuildContext context) {
                                if (isInactive) {
                                  return [
                                    const PopupMenuItem(
                                      value: PigMenuAction.info,
                                      child: Text('View Pig Information'),
                                    ),
                                  ];
                                }
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


                      // Info rows
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoText(
                                  'Stage:',
                                  pig.stage,
                                  labelColor,
                                  textColor,
                                ),
                                const SizedBox(height: 4),
                                _buildInfoText(
                                  'Sex:',
                                  pig.sex,
                                  labelColor,
                                  textColor,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoText(
                                  'Age:',
                                  _calculateAge(pig.birthDate),
                                  labelColor,
                                  textColor,
                                ),
                                const SizedBox(height: 4),
                                _buildInfoText(
                                  'Weight:',
                                  '${pig.currentWeightKg} kg',
                                  labelColor,
                                  textColor,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 13),


                      // Status note row
                      Row(
                        children: [
                          Icon(Icons.edit_square, size: 14, color: textColor),
                          const SizedBox(width: 4),
                          RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'STATUS:  ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                ),
                                TextSpan(
                                  text: pig.status,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: _getStatusColor(
                                      pig.status,
                                      isDarkMode,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),
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


  Widget _buildInfoText(
      String label,
      String value,
      Color labelColor,
      Color textColor,
      ) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(fontSize: 12, color: labelColor),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}