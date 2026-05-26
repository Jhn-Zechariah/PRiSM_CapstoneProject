import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/widgets/button.dart';
import '../../../../core/widgets/confirmation_box.dart';
import '../../../../core/widgets/snackbar.dart';
import '../../../../core/widgets/textfield.dart';
import '../../domain/model/app_feeding_record.dart';
import '../cubits/feeding_record_cubit.dart';

class PigFeedCardPopUp extends StatefulWidget {
  final String pigId;
  final Color pigColor;

  const PigFeedCardPopUp({
    super.key,
    required this.pigId,
    required this.pigColor,
  });

  @override
  State<PigFeedCardPopUp> createState() => _PigFeedCardPopUpState();
}

class _PigFeedCardPopUpState extends State<PigFeedCardPopUp> {
  // 👇 1. Add a FormKey to manage validation
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _feedTypeController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  @override
  void dispose() {
    _feedTypeController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    // 1. Validate Form
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // 2. Show Confirmation Dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => CustomConfirmDialog(
        title: 'Confirm Feeding',
        content: 'Save feeding record for ${widget.pigId}?',
        confirmText: 'Save',
        cancelText: 'Cancel',
        confirmColor: const Color(0xFFF5A623),
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    // 3. Show Loading Spinner
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        child: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFF5A623),
          ),
        ),
      ),
    );

    // 4. Extract Data
    final feedType = _feedTypeController.text.trim();
    final amount = double.parse(_amountController.text.trim());

    // 5. Prepare Record
    final recordToSave = AppFeedingRecord(
      id: '', // Handled by repo
      pigId: widget.pigId, // 👈 Make sure widget.pigId exists!
      feedType: feedType,
      amount: amount,
      timestamp: DateTime.now(),
    );

    // 6. Call Cubit
    final success = await context.read<FeedingRecordCubit>().addRecord(recordToSave);

    if (!mounted) return;

    // 7. Close loading indicator
    Navigator.pop(context);

    // 8. Handle Result
    if (success) {
      Navigator.pop(context); // Close popup entirely
      CustomSnackbar.show(
        context: context,
        message: 'Feeding record saved successfully!',
      );
    } else {
      CustomSnackbar.show(
        context: context,
        message: 'Failed to save feeding record. Please try again.',
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
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Form(
                    // 👇 3. Wrap the Column in a Form and attach the key
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "Feeding Record",
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.pop(context),
                              child: Icon(
                                Icons.close,
                                size: 22,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildInfoLabel('Breed:', isDark),
                                  const SizedBox(height: 6),
                                  _buildInfoLabel('Type of feeds:', isDark),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildInfoLabel('Stage: ', isDark),
                                  const SizedBox(height: 6),
                                  _buildInfoLabel('Amount of feeds:', isDark),
                                ],
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // ── Feed Type — CustomTextField ────────────────
                            Expanded(
                              child: CustomTextField(
                                controller: _feedTypeController,
                                label: 'Feed Type:',
                                border: 6,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                // 👇 4. Add validator for Feed Type
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  return null;
                                },
                              ),
                            ),

                            const SizedBox(width: 12),

                            // ── Amount — CustomTextField with spinner ──────
                            Expanded(
                              child: CustomTextField(
                                controller: _amountController,
                                label: 'Amount:',
                                border: 6,
                                keyboardType: TextInputType.number,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                // 👇 5. Add validator for Amount
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  // Optional: verify it's an actual number greater than 0
                                  final val = num.tryParse(value);
                                  if (val == null || val <= 0) {
                                    return 'Invalid';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 16),

                        // ── Save — CustomButton ────────────────────────────
                        CustomButton(
                          text: 'Save',
                          onPressed: _onSave,
                          backgroundColor: const Color(0xFFF5A623),
                          color: Colors.white,
                          border: 10,
                          borderColor: false,
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

  Widget _buildInfoLabel(String label, bool isDark) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: isDark ? Colors.white60 : Colors.grey,
      ),
    );
  }
}