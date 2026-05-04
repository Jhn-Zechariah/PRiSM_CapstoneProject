import 'package:flutter/material.dart';
import '../../../auth/presentation/components/textfield.dart';
import '../../../auth/presentation/components/button.dart';
import '../../../../core/widgets/snackbar.dart';
import '../../../auth/presentation/components/confirmation_box.dart';

class SelectPigFeedPopup2 extends StatefulWidget {
  final String pigName;
  final Color pigColor;

  const SelectPigFeedPopup2({
    super.key,
    required this.pigName,
    required this.pigColor,
  });

  @override
  State<SelectPigFeedPopup2> createState() => _SelectPigFeedPopup2State();
}

class _SelectPigFeedPopup2State extends State<SelectPigFeedPopup2> {
  final TextEditingController _feedTypeController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  int _amount = 0;

  @override
  void dispose() {
    _feedTypeController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => CustomConfirmDialog(
        title: 'Confirm Feeding',
        content: 'Save feeding record for ${widget.pigName}?',
        confirmText: 'Save',
        cancelText: 'Cancel',
        confirmColor: const Color(0xFFF5A623),
      ),
    );

    if (confirmed != true) return;

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

    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    Navigator.pop(context); // close loading
    Navigator.pop(context); // close popup

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
                            widget.pigName,
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
                                _buildInfoLabel('Stage:', isDark),
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
                              suffixIcon: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _amount++;
                                      _amountController.text =
                                          _amount.toString();
                                    });
                                  },
                                  onLongPress: () {
                                    setState(() {
                                      if (_amount > 0) _amount--;
                                      _amountController.text =
                                          _amount.toString();
                                    });
                                  },
                                  child: Icon(
                                    Icons.expand_circle_down_outlined,
                                    size: 22,
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black45,
                                  ),
                                ),
                              ),
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