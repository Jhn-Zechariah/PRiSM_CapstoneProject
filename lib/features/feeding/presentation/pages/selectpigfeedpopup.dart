import 'package:flutter/material.dart';
import '../../../auth/presentation/components/textfield.dart';
import '../../../auth/presentation/components/button.dart';
import '../../../../core/widgets/snackbar.dart';
import '../../../auth/presentation/components/confirmation_box.dart';

class SelectPigFeedPopup extends StatefulWidget {
  final List<Map<String, dynamic>> pigs;
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
  late List<bool> _checked;
  final TextEditingController _feedTypeController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checked = List<bool>.filled(widget.pigs.length + 1, false);
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

  void _onPigChecked(int index, bool? value) {
    setState(() {
      _checked[index + 1] = value ?? false;
      _checked[0] = _checked.skip(1).every((c) => c);
    });
  }

  Future<void> _onSave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => CustomConfirmDialog(
        title: 'Confirm Feeding',
        content: 'Save feeding record for selected pigs?',
        confirmText: 'Save',
        cancelText: 'Cancel',
        confirmColor: const Color(0xFFF5A623),
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
          child: CircularProgressIndicator(
            color: Color(0xFFF5A623),
          ),
        ),
      ),
    );

    await Future.delayed(const Duration(seconds: 1)); // replace with actual save logic

    if (!mounted) return;

    Navigator.pop(context); // close loading
    Navigator.pop(context); // close popup

    if (!mounted) return;
    CustomSnackbar.show(
      context: context,
      message: 'Feeding record saved successfully!',
    );
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
                              color: isDark ? Colors.white60 : Colors.black54,
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
                              return Column(
                                children: [
                                  _buildCheckRow(
                                    label: '${pig["name"]} - Stage',
                                    checked: _checked[i + 1],
                                    isSelectAll: false,
                                    isDark: isDark,
                                    onChanged: (val) => _onPigChecked(i, val),
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
                                  horizontal: 10, vertical: 12),
                            ),
                          ),

                          const SizedBox(width: 12),

                          Expanded(
                            child: CustomTextField(
                              controller: _amountController,
                              label: 'Amount:',
                              border: 6,
                              keyboardType: TextInputType.number,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 12),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

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
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelectAll ? FontWeight.w600 : FontWeight.normal,
              color: isSelectAll
                  ? const Color(0xFF2563EB)
                  : (isDark ? Colors.white : Colors.black87),
            ),
          ),
        ],
      ),
    );
  }
}