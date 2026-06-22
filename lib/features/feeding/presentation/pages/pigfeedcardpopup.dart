import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/widgets/button.dart';
import '../../../../core/widgets/confirmation_box.dart';
import '../../../../core/widgets/snackbar.dart';
import '../../../../core/widgets/textfield.dart';
import '../../../pig_management/domain/model/app_pig.dart';
import '../../domain/model/app_feeding_record.dart';
import '../cubits/feeding_record_cubit.dart';

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

  // 🔹 Cache the stream in a variable to prevent infinite read loops
  late Stream<AppFeedingRecord?> _latestFeedingStream;

  @override
  void initState() {
    super.initState();
    // 🔹 Initialize the stream ONCE in initState
    _latestFeedingStream = FirebaseFirestore.instance
        .collection('pigs')
        .doc(widget.pig.pigId)
        .collection('feeding_records')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isNotEmpty) {
        try {
          return AppFeedingRecord.fromMap(snapshot.docs.first.data());
        } catch (e) {
          debugPrint(" ERROR PARSING FEEDING RECORD: $e");
          return null;
        }
      }
      return null;
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

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => CustomConfirmDialog(
        title: 'Confirm Feeding',
        content: 'Save feeding record for ${widget.pig.breed} | ${widget.pig.displayId}?',
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
        child: Center(child: CircularProgressIndicator(color: Color(0xFFF5A623))),
      ),
    );

    final recordToSave = AppFeedingRecord(
      id: '', 
      pigId: widget.pig.pigId,
      feedType: _feedTypeController.text.trim(),
      amount: double.parse(_amountController.text.trim()),
      timestamp: DateTime.now(),
    );

    final success = await context.read<FeedingRecordCubit>().addRecord(recordToSave);

    if (!mounted) return;
    Navigator.pop(context); // Close loading spinner

    if (success) {
      Navigator.pop(context); // Close popup
      CustomSnackbar.show(context: context, message: 'Feeding record saved successfully!');
    } else {
      CustomSnackbar.show(context: context, message: 'Failed to save. Please try again.');
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
        decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(16)),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 10,
                decoration: BoxDecoration(
                  color: widget.pigColor,
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), bottomLeft: Radius.circular(16)),
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
                            Text("Feeding Record", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black)),
                            IconButton(
                              icon: const Icon(Icons.close, size: 22),
                              onPressed: () => Navigator.pop(context),
                              color: isDark ? Colors.white60 : Colors.black54,
                            ),
                          ],
                        ),

                        const SizedBox(height: 12),

                        StreamBuilder<AppFeedingRecord?>(
                          stream: _latestFeedingStream, // 🔹 Uses the cached stream
                          builder: (context, snapshot) {
                            String recentFeed = 'No data';
                            String recentAmount = '0';

                            if (snapshot.hasData && snapshot.data != null) {
                              recentFeed = snapshot.data!.feedType;
                              recentAmount = snapshot.data!.amount.toString();
                            } else if (snapshot.connectionState == ConnectionState.waiting) {
                              recentFeed = '...';
                              recentAmount = '...';
                            }

                            return Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildInfoText('Breed:', widget.pig.breed, isDark),
                                      const SizedBox(height: 6),
                                      _buildInfoText('Recent type:', recentFeed, isDark),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildInfoText('Stage:', widget.pig.stage, isDark),
                                      const SizedBox(height: 6),
                                      _buildInfoText('Recent amount:', recentAmount, isDark),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          },
                        ),

                        const SizedBox(height: 16),

                        Row(
                          children: [
                            Expanded(
                              child: CustomTextField(
                                controller: _feedTypeController,
                                label: 'Feed Type:',
                                border: 6,
                                validator: (value) => (value == null || value.trim().isEmpty) ? 'Required' : null,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CustomTextField(
                                controller: _amountController,
                                label: 'Amount (kg):',
                                border: 6,
                                keyboardType: TextInputType.number,
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) return 'Required';
                                  if (double.tryParse(value) == null) return 'Invalid';
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
          TextSpan(text: '$label ', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.grey)),
          TextSpan(text: value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isDark ? Colors.white : Colors.black87)),
        ],
      ),
    );
  }
}
