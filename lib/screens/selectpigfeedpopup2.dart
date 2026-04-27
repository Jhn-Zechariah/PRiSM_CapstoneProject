import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SelectPigFeedPopup2
// Individual pig feed popup — shown when a specific pig card is tapped.
// Usage:
//   showDialog(
//     context: context,
//     builder: (_) => SelectPigFeedPopup2(
//       pigName: name,
//       pigColor: color,
//     ),
//   );
// ─────────────────────────────────────────────────────────────────────────────

class SelectPigFeedPopup2 extends StatefulWidget {
  // Display name of the specific pig shown in the dialog title
  final String pigName;

  // Accent color used for the left strip of the dialog card
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
  // Controller for the feed type text input
  final TextEditingController _feedTypeController = TextEditingController();

  // Controller for the amount text input
  final TextEditingController _amountController = TextEditingController();

  // Internal integer tracker for the spinner; synced to _amountController
  int _amount = 0;

  @override
  void dispose() {
    // Dispose controllers to free resources when the dialog is closed
    _feedTypeController.dispose();
    _amountController.dispose();
    super.dispose();
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
              // ── Left colored accent strip matching the pig's color ────────
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

              // ── Main dialog content ───────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // ── Title row: pig name + close button ────────────────
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // Display the specific pig's name as the dialog title
                          Text(
                            widget.pigName,
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

                      const SizedBox(height: 10),

                      // ── Read-only info labels in a 2-column grid ──────────
                      Row(
                        children: [
                          // Left column: Breed and Type of feeds
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
                          // Right column: Stage and Amount of feeds
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

                      // ── Feed Type and Amount input fields (side by side) ───
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Feed Type free-text input
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
                                  height: 44,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white24
                                          : Colors.grey.shade400,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    // Slightly elevated background for input fields in dark mode
                                    color: isDark
                                        ? const Color(0xFF3A3A3A)
                                        : Colors.white,
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
                                        horizontal: 10,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(width: 12),

                          // Amount input with tap-to-increment / long-press-to-decrement spinner
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
                                  height: 44,
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: isDark
                                          ? Colors.white24
                                          : Colors.grey.shade400,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                    color: isDark
                                        ? const Color(0xFF3A3A3A)
                                        : Colors.white,
                                  ),
                                  child: Row(
                                    children: [
                                      // Numeric text input (also editable directly)
                                      Expanded(
                                        child: TextField(
                                          controller: _amountController,
                                          keyboardType: TextInputType.number,
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: isDark
                                                ? Colors.white
                                                : Colors.black87,
                                          ),
                                          decoration: const InputDecoration(
                                            border: InputBorder.none,
                                            contentPadding:
                                                EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                      // Spinner icon: tap = increment, long press = decrement
                                      Padding(
                                        padding:
                                            const EdgeInsets.only(right: 8),
                                        child: GestureDetector(
                                          // Single tap increments the amount by 1
                                          onTap: () {
                                            setState(() {
                                              _amount++;
                                              _amountController.text =
                                                  _amount.toString();
                                            });
                                          },
                                          // Long press decrements the amount (minimum 0)
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
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),

                      // ── Save button ───────────────────────────────────────
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

  /// Builds a small muted label used in the read-only pig info grid
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