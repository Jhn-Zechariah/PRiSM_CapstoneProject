import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SelectPigFeedPopup
// Call via showDialog() from feedingrecord.dart when + is tapped.
// Usage:
//   showDialog(
//     context: context,
//     builder: (_) => SelectPigFeedPopup(
//       pigs: _pigs,
//       pigColor: color,
//     ),
//   );
// ─────────────────────────────────────────────────────────────────────────────

class SelectPigFeedPopup extends StatefulWidget {
  // List of pig data maps passed from the parent screen
  final List<Map<String, dynamic>> pigs;

  // Accent color used for the left strip of the dialog card
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
  // Index 0 = Select All checkbox; indices 1..n = individual pig checkboxes
  late List<bool> _checked;

  // Controllers for the feed type and amount input fields
  final TextEditingController _feedTypeController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Initialize all checkboxes as unchecked (pigs.length + 1 for Select All)
    _checked = List<bool>.filled(widget.pigs.length + 1, false);
  }

  @override
  void dispose() {
    // Dispose controllers to free resources when the dialog is dismissed
    _feedTypeController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  /// Toggles all checkboxes when the "Select All" checkbox is changed
  void _onSelectAll(bool? value) {
    setState(() {
      for (int i = 0; i < _checked.length; i++) {
        _checked[i] = value ?? false;
      }
    });
  }

  /// Toggles an individual pig checkbox and syncs the "Select All" state
  void _onPigChecked(int index, bool? value) {
    setState(() {
      _checked[index + 1] = value ?? false;
      // Mark "Select All" as checked only if every individual pig is checked
      _checked[0] = _checked.skip(1).every((c) => c);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Detect theme brightness for conditional styling
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
              // ── Left colored accent strip matching the pig's color ──────
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

              // ── Main dialog content ─────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Title row with close button ─────────────────────
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
                          // Close icon dismisses the dialog without saving
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

                      // ── Instructional "Select:" label ───────────────────
                      Text(
                        'Select:',
                        style: TextStyle(
                          fontSize: 13,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                      ),

                      const SizedBox(height: 6),

                      // ── Bordered checkbox list container ────────────────
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
                            // "Select All" checkbox at the top of the list
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
                            // Individual pig rows generated from the pigs list
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
                                  // Divider between pig rows (skip after the last one)
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

                      // ── Feed Type and Amount input fields (side by side) ─
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Feed Type text input
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Feed Type:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white24
                                          : Colors.grey.shade400,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: TextField(
                                    controller: _feedTypeController,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Amount numeric input
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Amount:',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Container(
                                  height: 42,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white24
                                          : Colors.grey.shade400,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: TextField(
                                    controller: _amountController,
                                    // Restrict keyboard to numeric input only
                                    keyboardType: TextInputType.number,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: isDark
                                          ? Colors.white
                                          : Colors.black87,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      contentPadding: EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 12),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // ── Save button ─────────────────────────────────────
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFF5A623), // Amber
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            'Save',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
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

  /// Builds a single labeled checkbox row for either "Select All" or an individual pig.
  /// [isSelectAll] controls the font weight and color of the label.
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
            activeColor: const Color(0xFF2563EB), // Blue when checked
            side: BorderSide(
              color: isDark ? Colors.white38 : Colors.grey.shade400,
            ),
            // Reduces tap target size to keep rows compact
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              // "Select All" label is bold blue; individual pig labels are plain
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