import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/snackbar.dart';
import '../pages/pig_information.dart';
import '../pages/update_pig_weight_dialog.dart';
import '../../domain/model/app_pig.dart';
import '../cubits/pig_cubit.dart';
import '../../../../core/services/ml_service.dart';
import '../../../assessment/domain/growth_request.dart';
import '../../../assessment/domain/model/assessment.dart';
import '../../../assessment/domain/model/assessment_ui_config.dart';
import '../../data/firestore_pig_repo.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;


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
  void didUpdateWidget(covariant PigProfileCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    final weightChanged =
        oldWidget.pig.currentWeightKg != widget.pig.currentWeightKg;

    final birthWeightChanged =
        oldWidget.pig.birthWeightKg != widget.pig.birthWeightKg;

    final birthDateChanged =
        oldWidget.pig.birthDate != widget.pig.birthDate;

    final statusChanged =
        oldWidget.pig.status != widget.pig.status;

    if (weightChanged ||
        birthWeightChanged ||
        birthDateChanged ||
        statusChanged) {
      // No setState needed: build() always runs after didUpdateWidget
      _mlLoading = true;
      _mlStatus = null;
      _mlClassification = null;
      _mlInsight = null;
      _mlRecommendation = null;

      _fetchMLInsights();
    }
  }

  @override
  bool get wantKeepAlive => true;

  String? _mlStatus; // API status key: no_flags | flags_raised | insufficient_data | not_configured
  String? _mlClassification; // status label shown on the badge
  String? _mlInsight;
  String? _mlRecommendation;
  bool _mlLoading = true;
  AssessmentUiConfig? _ui;

  String _uiText(String s, String k) => _ui?.t(s, k) ?? '';


  @override
  void initState() {
    super.initState();
    AssessmentUiConfig.cached().then((c) {
      if (mounted) setState(() => _ui = c);
    });
    _fetchMLInsights();
  }


  Future<void> _fetchMLInsights() async {
    // Only run ML for active pigs
    if (widget.pig.isInactive) {
      _mlLoading = false;
      return;
    }


    final ui = await AssessmentUiConfig.cached();
    try {
      // A1 growth trend from this pig's own MANUAL weigh-ins (rule-based, advisory).
      final records = await FirebasePigRepo().streamWeightHistory(widget.pig.pigId).first;
      final a = Assessment.fromApi(
          await MlService.assessPigGrowth(growthRequestBody(widget.pig, records)));
      if (!mounted) return;
      final latest = a.details['latest_adg_g_per_day'];
      final rolling = a.details['rolling_adg_g_per_day'];
      final unit = ui.t('card', 'unit_g_day');
      final flags = (a.details['flags'] as List? ?? const [])
          .map((f) => (f as Map)['message'].toString())
          .toList();
      setState(() {
        _mlStatus = a.status;
        _mlClassification = a.statusLabel;
        _mlInsight = latest == null
            ? (a.reasons.isNotEmpty ? a.reasons.first : null)
            : '${ui.t('card', 'adg_latest')}: ${(latest as num).round()} $unit'
                '${rolling == null ? '' : ' (${ui.t('card', 'adg_rolling')} ${(rolling as num).round()} $unit)'}';
        _mlRecommendation = flags.isNotEmpty ? flags.join(' ') : null;
        _mlLoading = false;
      });
    } catch (e) {
      // Say WHY it failed instead of one generic message.
      final code = e is MlServiceException ? e.statusCode : null;
      final key = switch (code) {
        401 || 403 || 503 => 'auth_rejected', // 503 = sign-in checking not configured on the server
        422 => 'rejected_input',
        null when e is FirebaseException => 'weights_unavailable',
        null => e is MlServiceException ? 'unavailable' : 'service_error',
        _ => 'service_error',
      };
      debugPrint('Growth check error: ${e.runtimeType} status=$code');
      if (!mounted) return;
      setState(() {
        _mlLoading = false;
        _mlStatus = null;
        _mlClassification = null;
        _mlInsight = ui.t('card', key);
      });
    }
  }


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


  Color _getClassificationColor(String? status) {
    switch (status) {
      case 'no_flags':
        return widget.isDarkMode ? Colors.greenAccent : Colors.green.shade700;
      case 'flags_raised':
        return widget.isDarkMode ? Colors.orangeAccent : Colors.orange.shade800;
      default:
        return Colors.grey;
    }
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


    final classificationColor = _getClassificationColor(_mlStatus);


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


                      // Notes box
                      const SizedBox(height: 10),


                      // ML Insights block
                      if (!isInactive) ...[
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(right: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF1A2A1A)
                                : const Color(0xFFF0FFF0),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: classificationColor.withValues(alpha: 0.4),
                            ),
                          ),
                          child: _mlLoading
                              ? Row(
                            children: [
                              SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: classificationColor,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _uiText('card', 'analyzing'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: labelColor,
                                ),
                              ),
                            ],
                          )
                              : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Classification badge
                              Row(
                                children: [
                                  const Icon(
                                    Icons.insights,
                                    size: 13,
                                    color: Colors.lightGreen,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _uiText('card', 'title'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                  ),
                                  const Spacer(),
                                  if (_mlClassification != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 7,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: classificationColor
                                            .withValues(alpha: 0.15),
                                        borderRadius:
                                        BorderRadius.circular(20),
                                        border: Border.all(
                                          color: classificationColor,
                                          width: 0.8,
                                        ),
                                      ),
                                      child: Text(
                                        _mlClassification!,
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: classificationColor,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              if (_mlInsight != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _mlInsight!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: labelColor,
                                  ),
                                ),
                              ],
                              if (_mlRecommendation != null) ...[
                                const SizedBox(height: 5),
                                Row(
                                  crossAxisAlignment:
                                  CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.arrow_right,
                                      size: 14,
                                      color: classificationColor,
                                    ),
                                    const SizedBox(width: 2),
                                    Expanded(
                                      child: Text(
                                        _mlRecommendation!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: labelColor,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
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