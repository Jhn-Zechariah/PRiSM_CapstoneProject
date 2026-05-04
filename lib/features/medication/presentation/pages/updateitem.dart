import 'package:flutter/material.dart';
import 'package:prism_app/core/widgets/button.dart';
import 'package:prism_app/core/widgets/snackbar.dart';

import '../../../../core/widgets/confirmation_box.dart';
import '../../../../core/widgets/dropdown.dart';
import '../../../../core/widgets/textfield.dart';

/// A dialog widget for editing an existing inventory item.
/// Requires an [item] map pre-populated with the item's current data.
/// Returns an updated Map of the item's data when saved, or null if dismissed.
class UpdateItemDialog extends StatefulWidget {
  final Color accentColor;

  /// The existing item data used to pre-fill the form fields.
  final Map<String, dynamic> item;

  const UpdateItemDialog({
    super.key,
    this.accentColor = const Color(0xFF002D44),
    required this.item,
  });

  @override
  State<UpdateItemDialog> createState() => _UpdateItemDialogState();
}

class _UpdateItemDialogState extends State<UpdateItemDialog> {
  // ── Text controllers — initialized with existing item values in initState ──
  late final TextEditingController _nameController;
  late final TextEditingController _qtyController;
  late final TextEditingController _mgController;     // dosage/unit amount
  late final TextEditingController _expiryController;
  late final TextEditingController _reorderController;
  late final TextEditingController _descController;

  // Focus node used to detect when the dosage field is active (for border highlight)
  final _mgFocusNode = FocusNode();

  // ── Dropdown state — pre-seeded from the existing item ────────────────────
  late String selectedCategory;
  late String selectedType;

  // ── Labels that change based on category/type ─────────────────────────────
  late String _unitLabel; // dosage unit shown inside the compact box
  late String _perLabel;  // per-unit label shown beside the dosage box

  @override
  void initState() {
    super.initState();

    // Pre-fill category and type from the item, falling back to safe defaults
    selectedCategory = widget.item['category'] ?? 'Medicine';
    selectedType     = widget.item['type'] ?? 'Capsule';

    // Pre-fill each text controller with the item's existing values
    _nameController    = TextEditingController(text: widget.item['name'] ?? '');
    _qtyController     = TextEditingController(text: widget.item['stock']?.toString() ?? '');
    _mgController      = TextEditingController(text: widget.item['dosage'] ?? '');
    _expiryController  = TextEditingController(text: widget.item['expiry'] ?? '');
    _reorderController = TextEditingController(text: widget.item['reorder']?.toString() ?? '');
    _descController    = TextEditingController(text: widget.item['description'] ?? '');

    // Rebuild UI when the dosage field gains or loses focus (border color update)
    _mgFocusNode.addListener(() => setState(() {}));

    // Set initial unit/per labels to match the pre-loaded category and type
    _syncLabels();
  }

  @override
  void dispose() {
    // Dispose all controllers and focus nodes to free resources
    _nameController.dispose();
    _qtyController.dispose();
    _mgController.dispose();
    _expiryController.dispose();
    _reorderController.dispose();
    _descController.dispose();
    _mgFocusNode.dispose();
    super.dispose();
  }

  /// Updates [_unitLabel] and [_perLabel] to match the current category/type.
  void _syncLabels() {
    if (selectedCategory == 'Vitamins') {
      _unitLabel = 'g';
      _perLabel  = '/ Sachet';
    } else if (selectedCategory == 'Vaccine' || selectedType == 'Fluid') {
      _unitLabel = 'mL';
      _perLabel  = '/ Bottle';
    } else {
      // Default: Medicine Capsule
      _unitLabel = 'mg';
      _perLabel  = '/ Tablet';
    }
  }

  // ── Computed label for the name display based on selected category ─────────
  String get _nameLabel {
    if (selectedCategory == 'Vitamins') return 'Vitamins Name:';
    if (selectedCategory == 'Vaccine')  return 'Vaccine Name:';
    return 'Medicine Name:';
  }

  // ── Dialog title changes to reflect what category is being updated ─────────
  String get _dialogTitle {
    if (selectedCategory == 'Vitamins') return 'Update Vitamins';
    if (selectedCategory == 'Vaccine')  return 'Update Vaccine';
    return 'Update Medicine';
  }

  // ── Available type options depend on the selected category ─────────────────
  List<String> get _typeOptions {
    if (selectedCategory == 'Vitamins') return ['Powder'];
    return ['Capsule', 'Fluid'];
  }

  /// Called when the user picks a new type from the dropdown (Medicine only).
  void _onTypeChanged(String? newType) {
    if (newType == null) return;
    setState(() {
      selectedType = newType;
      _syncLabels();
    });
  }

  /// Opens the platform date picker, pre-set to the item's existing expiry date.
  /// Writes the selected date to [_expiryController] formatted as YYYY-MM-DD.
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      // Try to parse the existing expiry date; fall back to today if invalid
      initialDate: DateTime.tryParse(_expiryController.text) ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      // Apply the dialog's accent color to the date picker theme
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(
            primary: widget.accentColor,
            onPrimary: Colors.white,
            onSurface: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        // Format date as YYYY-MM-DD
        _expiryController.text = "${picked.toLocal()}".split(' ')[0];
      });
    }
  }

  /// Shows a confirmation dialog before saving.
  /// On confirmation, pops the dialog and returns the updated item data.
  Future<void> _onSave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const CustomConfirmDialog(
        title: 'Update Item',
        content: 'Are you sure you want to update this item?',
        confirmText: 'Update',
        cancelText: 'Cancel',
        confirmColor: Color(0xFF002D44),
      ),
    );

    if (confirmed == true && mounted) {
      // Return the updated item data to the caller
      Navigator.pop(context, {
        'name':        _nameController.text,
        'stock':       int.tryParse(_qtyController.text) ?? 0,
        'dosage':      _mgController.text,
        'expiry':      _expiryController.text,
        'reorder':     int.tryParse(_reorderController.text) ?? 0,
        'description': _descController.text,
        'category':    selectedCategory,
        'type':        selectedType,
      });

      // Show success feedback after the dialog is closed
      CustomSnackbar.show(
        context: context,
        message: 'Item updated successfully!',
      );
    }
  }

  // ── Shared label style — identical to AddNewItemDialog ─────────────────────
  TextStyle _labelStyle(BuildContext context) {
    return TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Theme.of(context).textTheme.bodySmall?.color,
    );
  }

  /// Builds the compact dosage input box that shows a numeric field and a unit label
  /// side by side, separated by a thin divider. Highlights border when focused.
  /// Identical in behavior to AddNewItemDialog._compactUnitBox.
  Widget _compactUnitBox({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String unit,
  }) {
    final isDarkMode   = Theme.of(context).brightness == Brightness.dark;
    final fillColor    = isDarkMode ? const Color(0xFF2A2A2A) : Colors.white;
    final borderColor  = isDarkMode ? Colors.white24 : Colors.black26;
    final dividerColor = isDarkMode ? Colors.white24 : Colors.black12;

    return Material(
      elevation: 5,
      color: Colors.transparent,
      shadowColor: Colors.grey,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 110,
        decoration: BoxDecoration(
          color: fillColor,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            // Blue border when focused, subtle border otherwise
            color: focusNode.hasFocus ? Colors.blue : borderColor,
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            // Numeric input area
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            // Divider between input and unit label
            Container(width: 1, height: 28, color: dividerColor),
            // Unit label (mg / g / mL)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                unit,
                style: _labelStyle(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a non-editable read-only type box used when the type is fixed
  /// (e.g., 'Fluid' for Vaccine, 'Powder' for Vitamins).
  Widget _staticTypeBox(String label) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 2,
      color: Colors.transparent,
      shadowColor: Colors.grey,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isDarkMode ? Colors.white12 : Colors.grey[300]!,
          ),
        ),
        child: Text(label, style: _labelStyle(context)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        // IntrinsicHeight ensures the dialog sizes to its content
        // instead of stretching to screen height — matches AddNewItemDialog
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Colored accent strip on the left edge of the dialog ────────
              // Uses yellow (0xFFFFC154) instead of navy to distinguish from Add dialog
              Container(width: 12, color: const Color(0xFFFFC154)),

              // ── Main form content ──────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // ── Dialog header: dynamic title + close button ───────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _dialogTitle, // e.g. 'Update Medicine', 'Update Vaccine'
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Theme.of(context).textTheme.bodyLarge?.color,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: Theme.of(context).iconTheme.color,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // ── Read-only item name display (not editable in update) ─
                        // Shows the category label and item name in bold
                        RichText(
                          text: TextSpan(
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(context).textTheme.bodyMedium?.color,
                            ),
                            children: [
                              TextSpan(text: '$_nameLabel '),
                              TextSpan(
                                text: _nameController.text,
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),

                        // ── Quantity + dosage row ────────────────────────────
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text('Qty:', style: _labelStyle(context)),
                            const SizedBox(width: 10),
                            // Quantity input (integer only)
                            SizedBox(
                              width: 70,
                              child: CustomTextField(
                                controller: _qtyController,
                                border: 8,
                                keyboardType: TextInputType.number,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            // Dosage amount + unit (mg / g / mL)
                            _compactUnitBox(
                              controller: _mgController,
                              focusNode: _mgFocusNode,
                              unit: _unitLabel,
                            ),
                            const SizedBox(width: 8),
                            // Per-unit label (/ Tablet, / Sachet, / Bottle)
                            Text(_perLabel, style: _labelStyle(context)),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // ── Type selector ────────────────────────────────────
                        // Fixed static box for Vaccine/Vitamins; dropdown for Medicine
                        Text('Type:', style: _labelStyle(context)),
                        const SizedBox(height: 6),
                        selectedCategory == 'Vaccine'
                            ? _staticTypeBox('Fluid')
                            : selectedCategory == 'Vitamins'
                                ? _staticTypeBox('Powder')
                                : CustomDropdown(
                                    value: selectedType,
                                    items: _typeOptions,
                                    border: 8,
                                    onChanged: _onTypeChanged,
                                  ),

                        const SizedBox(height: 14),

                        // ── Expiry date + Re-order alert row ─────────────────
                        Row(
                          children: [
                            Expanded(
                              child: CustomTextField(
                                controller: _expiryController,
                                label: 'Expiry date:',
                                border: 8,
                                readonly: true, // date is selected via picker, not typed
                                onTap: _selectDate,
                                suffixIcon: IconButton(
                                  icon: const Icon(
                                    Icons.calendar_month_outlined,
                                    size: 20,
                                  ),
                                  onPressed: _selectDate,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CustomTextField(
                                controller: _reorderController,
                                label: 'Re-order alert:',
                                border: 8,
                                keyboardType: TextInputType.number,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // ── Description (multi-line via tall content padding) ─
                        CustomTextField(
                          controller: _descController,
                          label: 'Description:',
                          border: 8,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 40,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Save button ──────────────────────────────────────
                        CustomButton(
                          text: 'Save',
                          border: 8,
                          backgroundColor: const Color(0xFFFFC154),
                          color: Colors.black,
                          borderColor: false,
                          onPressed: _onSave,
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
}