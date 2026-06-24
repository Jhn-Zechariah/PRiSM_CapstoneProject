import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// --- Core Widgets ---
import '../../../../core/widgets/button.dart';
import '../../../../core/widgets/confirmation_box.dart';
import '../../../../core/widgets/snackbar.dart';
import '../../../../core/widgets/textfield.dart';
import '../../../pig_management/domain/model/app_pig.dart';
import '../../domain/model/app_feeding_record.dart';
import '../cubits/feeding_record_cubit.dart';
import '../cubits/feeding_record_states.dart';

class PigFeedCardPopUp extends StatefulWidget {
  final AppPig pig;
  final Color pigColor;

  const PigFeedCardPopUp({
    super.key,
    required this.pig,
    required this.pigColor,
  });

  @override
  State<PigFeedCardPopUp> createState() => _PigFeedCardPopUpState();
}

class _PigFeedCardPopUpState extends State<PigFeedCardPopUp> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _feedTypeController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context
            .read<FeedingRecordCubit>()
            .loadLatestRecord(widget.pig.pigId);
      }
    });
  }

  @override
  void dispose() {
    _feedTypeController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;

    final amount = double.tryParse(_amountController.text.trim());
    // 🔹 FIXED: Added a protective layer guarding against 0 or negative numbers
    if (amount == null || amount <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => CustomConfirmDialog(
        title: 'Confirm Feeding',
        content:
        'Save feeding record for ${widget.pig.breed} | ${widget.pig.displayId}?',
        confirmText: 'Save',
        cancelText: 'Cancel',
        confirmColor: const Color(0xFF2563EB),
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        child: Center(
          child: CircularProgressIndicator(color: Color(0xFFF5A623)),
        ),
      ),
    );

    final recordToSave = AppFeedingRecord(
      id: '',
      userId: widget.pig.userId,
      pigId: widget.pig.pigId,
      feedType: _feedTypeController.text.trim(),
      amount: amount,
      timestamp: DateTime.now(),
    );

    final success =
    await context.read<FeedingRecordCubit>().addRecord(recordToSave);

    if (!mounted) return;
    Navigator.pop(context); // Close loading spinner

    if (success) {
      Navigator.pop(context); // Close popup
      CustomSnackbar.show(
        context: context,
        message: 'Feeding record saved successfully!',
      );
    } else {
      CustomSnackbar.show(
        context: context,
        message: 'Failed to save. Please try again.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF2C2C2C) : Colors.white;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(16),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 10,
                decoration: BoxDecoration(
                  color: widget.pigColor,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Feeding Record',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 22),
                              onPressed: () => Navigator.pop(context),
                              color:
                              isDark ? Colors.white60 : Colors.black54,
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // ── Latest record preview ──────────────────────────
                        BlocBuilder<FeedingRecordCubit, FeedingRecordState>(
                          buildWhen: (previous, current) =>
                          (current is LatestFeedingRecordLoading &&
                              current.pigId == widget.pig.pigId) ||
                              (current is LatestFeedingRecordLoaded &&
                                  current.pigId == widget.pig.pigId) ||
                              (current is LatestFeedingRecordError &&
                                  current.pigId == widget.pig.pigId),
                          builder: (context, state) {
                            String recentFeed = 'No data';
                            String recentAmount = '0';

                            if (state is LatestFeedingRecordLoading &&
                                state.pigId == widget.pig.pigId) {
                              recentFeed = '...';
                              recentAmount = '...';
                            } else if (state is LatestFeedingRecordLoaded &&
                                state.pigId == widget.pig.pigId) {
                              final AppFeedingRecord? record = state.record;
                              if (record != null) {
                                recentFeed = record.feedType;
                                recentAmount = record.amount.toString();
                              }
                            }

                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      _buildInfoText(
                                          'Breed:', widget.pig.breed, isDark),
                                      const SizedBox(height: 6),
                                      _buildInfoText(
                                          'Recent type:', recentFeed, isDark),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      _buildInfoText(
                                          'Stage:', widget.pig.stage, isDark),
                                      const SizedBox(height: 6),
                                      _buildInfoText(
                                          'Recent amount:', recentAmount, isDark),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        // ── Input fields ───────────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: CustomTextField(
                                controller: _feedTypeController,
                                label: 'Feed Type:',
                                border: 6,
                                validator: (value) =>
                                (value == null || value.trim().isEmpty)
                                    ? 'Required'
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CustomTextField(
                                controller: _amountController,
                                label: 'Amount (kg):',
                                border: 6,
                                keyboardType: TextInputType.number,
                                // 🔹 FIXED: Modified validator logic to block values <= 0
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Required';
                                  }

                                  final parsedAmount = double.tryParse(value);
                                  if (parsedAmount == null) {
                                    return 'Invalid';
                                  }
                                  if (parsedAmount <= 0) {
                                    return 'Invalid amount';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        CustomButton(
                          text: 'Save Record',
                          onPressed: _onSave,
                          backgroundColor: widget.pigColor,
                          color: Colors.white,
                          border: 10,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoText(String label, String value, bool isDark) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.white60 : Colors.grey,
            ),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}