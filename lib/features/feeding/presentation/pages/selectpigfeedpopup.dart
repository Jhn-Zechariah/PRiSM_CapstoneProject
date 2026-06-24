import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../pig_management/domain/model/app_pig.dart';
import '../../../../core/widgets/textfield.dart';
import '../../../../core/widgets/button.dart';
import '../../../../core/widgets/snackbar.dart';
import '../../../../core/widgets/confirmation_box.dart';
import '../../domain/model/app_feeding_record.dart';
import '../cubits/feeding_record_cubit.dart';

class SelectPigFeedPopup extends StatefulWidget {
  final List<AppPig> pigs;
  final Color pigColor;

  const SelectPigFeedPopup({
    super.key,
    required this.pigs,
    required this.pigColor,
  });

  @override
  State<SelectPigFeedPopup> createState() => _SelectPigFeedPopupState();
}

class _SelectPigFeedPopupState extends State<SelectPigFeedPopup> {
  final _formKey = GlobalKey<FormState>();

  late List<bool> _checked;
  final TextEditingController _feedTypeController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  static const double _minAmount = 0.1;
  static const double _maxAmount = 500.0;

  @override
  void initState() {
    super.initState();
    _checked = List<bool>.filled(widget.pigs.length + 1, false);
  }

  @override
  void didUpdateWidget(SelectPigFeedPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pigs.length != widget.pigs.length) {
      final newChecked = List<bool>.filled(widget.pigs.length + 1, false);
      for (int i = 1; i < newChecked.length && i < _checked.length; i++) {
        newChecked[i] = _checked[i];
      }
      newChecked[0] =
          newChecked.length > 1 && newChecked.skip(1).every((c) => c);
      _checked = newChecked;
    }
  }

  @override
  void dispose() {
    _feedTypeController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _onSelectAll(bool? value) {
    setState(() {
      for (int i = 0; i < _checked.length; i++) {
        _checked[i] = value ?? false;
      }
    });
  }

  // FIX (High): Recompute the select-all checkbox state when any individual
  // pig checkbox changes. Previously _checked[0] was only written during
  // _onSelectAll — so unchecking a pig after "Select All" left the select-all
  // box permanently ticked.
  void _onPigChecked(int index, bool? value) {
    setState(() {
      _checked[index + 1] = value ?? false;
      // Select-all is true only when every individual pig is checked.
      _checked[0] = _checked.skip(1).every((c) => c);
    });
  }

  Future<void> _onSave() async {
    if (!_formKey.currentState!.validate()) return;

    final hasSelection = _checked.skip(1).any((isChecked) => isChecked);
    if (!hasSelection) {
      CustomSnackbar.show(
        context: context,
        message: 'Please select at least one pig.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const CustomConfirmDialog(
        title: 'Confirm Feeding',
        content: 'Save feeding record for selected pigs?',
        confirmText: 'Save',
        cancelText: 'Cancel',
        confirmColor: Colors.blue,
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        backgroundColor: Colors.transparent,
        child: Center(child: CircularProgressIndicator()),
      ),
    );

    final feedType = _feedTypeController.text.trim();

    final amount = double.tryParse(_amountController.text.trim());
    if (amount == null) {
      if (mounted) Navigator.pop(context);
      return;
    }

    final selectedPigs = <AppPig>[];
    for (int i = 0; i < widget.pigs.length; i++) {
      if (_checked[i + 1]) selectedPigs.add(widget.pigs[i]);
    }

    final recordsToSave = selectedPigs
        .map(
          (pig) => AppFeedingRecord(
        id: '',
        userId: pig.userId,
        pigId: pig.pigId,
        feedType: feedType,
        amount: amount,
        timestamp: DateTime.now(),
      ),
    )
        .toList();

    final success =
    await context.read<FeedingRecordCubit>().addBatchRecords(recordsToSave);

    if (!mounted) return;
    Navigator.pop(context); // Close spinner

    if (success) {
      Navigator.pop(context); // Close popup
      CustomSnackbar.show(
        context: context,
        message:
        'Successfully saved feeding records for ${selectedPigs.length} pig(s)!',
      );
    } else {
      CustomSnackbar.show(
        context: context,
        message: 'Failed to save records. Please try again.',
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
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Pigs to feed:',
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
                                color:
                                isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Select:',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: isDark
                                  ? Colors.white12
                                  : Colors.grey.shade300,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            children: [
                              _buildCheckRow(
                                label: 'Select All',
                                checked: _checked[0],
                                isSelectAll: true,
                                isDark: isDark,
                                onChanged: _onSelectAll,
                              ),
                              Divider(
                                height: 1,
                                color: isDark
                                    ? Colors.white12
                                    : Colors.grey.shade200,
                              ),
                              ...List.generate(widget.pigs.length, (i) {
                                final pig = widget.pigs[i];
                                final displayLabel =
                                    '${pig.breed} | ${pig.displayId} - ${pig.stage}';

                                return Column(
                                  children: [
                                    _buildCheckRow(
                                      label: displayLabel,
                                      checked: _checked[i + 1],
                                      isSelectAll: false,
                                      isDark: isDark,
                                      onChanged: (val) =>
                                          _onPigChecked(i, val),
                                    ),
                                    if (i < widget.pigs.length - 1)
                                      Divider(
                                        height: 1,
                                        color: isDark
                                            ? Colors.white12
                                            : Colors.grey.shade200,
                                      ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: CustomTextField(
                                controller: _feedTypeController,
                                label: 'Feed Type:',
                                border: 6,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CustomTextField(
                                controller: _amountController,
                                label: 'Amount (kg):',
                                border: 6,
                                keyboardType:
                                const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                validator: (value) {
                                  if (value == null || value.trim().isEmpty) {
                                    return 'Required';
                                  }
                                  final val = double.tryParse(value.trim());
                                  if (val == null) return 'Invalid number';
                                  if (val < _minAmount) {
                                    return 'Min ${_minAmount}kg';
                                  }
                                  if (val > _maxAmount) {
                                    return 'Max ${_maxAmount.toInt()}kg';
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        CustomButton(
                          text: 'Save Records',
                          onPressed: _onSave,
                          backgroundColor: const Color(0xFF2563EB),
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

  Widget _buildCheckRow({
    required String label,
    required bool checked,
    required bool isSelectAll,
    required bool isDark,
    required ValueChanged<bool?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          Checkbox(
            value: checked,
            onChanged: onChanged,
            activeColor: const Color(0xFF2563EB),
            side: BorderSide(
              color: isDark ? Colors.white38 : Colors.grey.shade400,
            ),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                isSelectAll ? FontWeight.w600 : FontWeight.normal,
                color: isSelectAll
                    ? const Color(0xFF2563EB)
                    : (isDark ? Colors.white : Colors.black87),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}