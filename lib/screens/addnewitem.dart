import 'package:flutter/material.dart';
import 'package:prism_app/features/auth/presentation/components/textfield.dart';
import 'package:prism_app/features/auth/presentation/components/dropdown.dart';
import 'package:prism_app/features/auth/presentation/components/button.dart';
import 'package:prism_app/features/auth/presentation/components/confirmation_box.dart';
import 'package:prism_app/features/auth/presentation/components/snackbar.dart';

/// A dialog widget for adding a new inventory item (Medicine, Vitamins, or Vaccine).
/// Returns a Map of the item's data when saved, or null if dismissed.
class AddNewItemDialog extends StatefulWidget {
  final Color accentColor;

  const AddNewItemDialog({
    super.key,
    this.accentColor = const Color(0xFF002D44),
  });

  @override
  State<AddNewItemDialog> createState() => _AddNewItemDialogState();
}

class _AddNewItemDialogState extends State<AddNewItemDialog> {
  // ── Text controllers for each form field ──────────────────────────────────
  final _nameController    = TextEditingController();
  final _qtyController     = TextEditingController();
  final _mgController      = TextEditingController(); // dosage/unit amount
  final _expiryController  = TextEditingController();
  final _reorderController = TextEditingController();
  final _descController    = TextEditingController();

  // Focus node used to detect when the dosage field is active (for border highlight)
  final _mgFocusNode = FocusNode();

  // ── Default dropdown selections ────────────────────────────────────────────
  String selectedCategory = 'Medicine';
  String selectedType     = 'Capsule';

  // ── Labels that change based on selected category/type ────────────────────
  String _unitLabel = 'mg';      // dosage unit shown inside the compact box
  String _perLabel  = '/ Tablet'; // per-unit label shown beside the dosage box

  @override
  void initState() {
    super.initState();
    // Rebuild UI when the dosage field gains or loses focus (border color update)
    _mgFocusNode.addListener(() => setState(() {}));
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

  // ── Computed label for the name field based on the selected category ───────
  String get _nameLabel {
    if (selectedCategory == 'Vitamins') return 'Vitamins Name:';
    if (selectedCategory == 'Vaccine')  return 'Vaccine Name:';
    return 'Medicine Name:';
  }

  // ── Available type options depend on the selected category ─────────────────
  List<String> get _typeOptions {
    if (selectedCategory == 'Vitamins') return ['Powder'];
    return ['Capsule', 'Fluid'];
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

  /// Called when the user picks a new category from the dropdown.
  /// Resets the type to the appropriate default and syncs unit labels.
  void _onCategoryChanged(String? newCategory) {
    if (newCategory == null) return;
    setState(() {
      selectedCategory = newCategory;
      // Auto-select the only valid type for Vitamins and Vaccine
      if (newCategory == 'Vitamins') {
        selectedType = 'Powder';
      } else if (newCategory == 'Vaccine') {
        selectedType = 'Fluid';
      } else {
        selectedType = 'Capsule';
      }
      _syncLabels();
    });
  }

  /// Called when the user picks a new type from the dropdown (Medicine only).
  void _onTypeChanged(String? newType) {
    if (newType == null) return;
    setState(() {
      selectedType = newType;
      _syncLabels();
    });
  }

  /// Opens the platform date picker and writes the selected date to [_expiryController].
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
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
  /// On confirmation, pops the dialog and returns the collected item data.
  Future<void> _onSave() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const CustomConfirmDialog(
        title: 'Save Item',
        content: 'Are you sure you want to add this item to the inventory?',
        confirmText: 'Save',
        cancelText: 'Cancel',
        confirmColor: Color(0xFF002D44),
      ),
    );

    if (confirmed == true && mounted) {
      // Return the filled-in item data to the caller
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
        message: 'Item added successfully!',
      );
    }
  }

  // ── Shared label style used across all form labels ─────────────────────────
  TextStyle _labelStyle(BuildContext context) {
    return TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Theme.of(context).textTheme.bodySmall?.color,
    );
  }

  /// Builds the compact dosage input box that shows a numeric field and a unit label
  /// side by side, separated by a thin divider. Highlights border when focused.
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
        child: Text(
          label,
          style: _labelStyle(context),
        ),
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
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Colored accent strip on the left edge of the dialog ────────
              Container(width: 12, color: const Color(0xFF002D44)),

              // ── Main form content ──────────────────────────────────────────
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        // ── Dialog header: title + close button ──────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Add new item',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Theme.of(context).textTheme.bodyLarge?.color,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: Theme.of(context).textTheme.bodyMedium?.color,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ── Item name field (label changes with category) ─────
                        CustomTextField(
                          controller: _nameController,
                          label: _nameLabel,
                          border: 8,
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

                        // ── Category + Type dropdowns ────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: CustomDropdown(
                                label: 'Category:',
                                value: selectedCategory,
                                border: 8,
                                items: const ['Medicine', 'Vitamins', 'Vaccine'],
                                onChanged: _onCategoryChanged,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Type:', style: _labelStyle(context)),
                                  const SizedBox(height: 4),
                                  // Show a static box for fixed types, dropdown otherwise
                                  if (selectedCategory == 'Vaccine')
                                    _staticTypeBox('Fluid')
                                  else if (selectedCategory == 'Vitamins')
                                    _staticTypeBox('Powder')
                                  else
                                    CustomDropdown(
                                      key: ValueKey(selectedCategory),
                                      value: selectedType,
                                      border: 8,
                                      items: _typeOptions,
                                      onChanged: _onTypeChanged,
                                    ),
                                ],
                              ),
                            ),
                          ],
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