import 'package:flutter/material.dart';
import 'package:prism_app/core/widgets/button.dart';
import 'package:prism_app/core/widgets/snackbar.dart';

import '../../../../core/widgets/confirmation_box.dart';
import '../../../../core/widgets/dropdown.dart';
import '../../../../core/widgets/textfield.dart';

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
  // ── Consistent padding for all fields ─────────────────────────────────────
  static const _fieldPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 13,
  );

  // ── Controllers ────────────────────────────────────────────────────────────
  final _nameController = TextEditingController();
  final _qtyController = TextEditingController();
  final _mgController = TextEditingController();
  final _expiryController = TextEditingController();
  final _reorderController = TextEditingController();
  final _descController = TextEditingController();
  final _mgFocusNode = FocusNode();

  // ── Dropdown state ─────────────────────────────────────────────────────────
  String selectedCategory = 'Medicine';
  String selectedType = 'Capsule';
  String _unitLabel = 'mg';
  String _perLabel = '/ Tablet';

  @override
  void initState() {
    super.initState();
    _mgFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _qtyController.dispose();
    _mgController.dispose();
    _expiryController.dispose();
    _reorderController.dispose();
    _descController.dispose();
    _mgFocusNode.dispose();
    super.dispose();
  }

  String get _nameLabel {
    if (selectedCategory == 'Vitamins') return 'Vitamins Name:';
    if (selectedCategory == 'Vaccine') return 'Vaccine Name:';
    return 'Medicine Name:';
  }

  List<String> get _typeOptions {
    if (selectedCategory == 'Vitamins') return ['Powder'];
    return ['Capsule', 'Fluid'];
  }

  void _syncLabels() {
    if (selectedCategory == 'Vitamins') {
      _unitLabel = 'g';
      _perLabel = '/ Sachet';
    } else if (selectedCategory == 'Vaccine' || selectedType == 'Fluid') {
      _unitLabel = 'mL';
      _perLabel = '/ Bottle';
    } else {
      _unitLabel = 'mg';
      _perLabel = '/ Tablet';
    }
  }

  void _onCategoryChanged(String? newCategory) {
    if (newCategory == null) return;
    setState(() {
      selectedCategory = newCategory;
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

  void _onTypeChanged(String? newType) {
    if (newType == null) return;
    setState(() {
      selectedType = newType;
      _syncLabels();
    });
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
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
        _expiryController.text = "${picked.toLocal()}".split(' ')[0];
      });
    }
  }

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
      Navigator.pop(context, {
        'name': _nameController.text,
        'stock': int.tryParse(_qtyController.text) ?? 0,
        'dosage': _mgController.text,
        'expiry': _expiryController.text,
        'reorder': int.tryParse(_reorderController.text) ?? 0,
        'description': _descController.text,
        'category': selectedCategory,
        'type': selectedType,
      });

      CustomSnackbar.show(
        context: context,
        message: 'Item added successfully!',
      );
    }
  }

  TextStyle _labelStyle(BuildContext context) {
    return TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w500,
      color: Theme.of(context).textTheme.bodySmall?.color,
    );
  }

  // ── Compact dosage box ─────────────────────────────────────────────────────
  Widget _compactUnitBox({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String unit,
  }) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final fillColor = isDarkMode ? const Color(0xFF2A2A2A) : Colors.white;
    final borderColor = isDarkMode ? Colors.white24 : Colors.black26;
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
            color: focusNode.hasFocus ? Colors.blue : borderColor,
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
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
                  // ✅ matches _fieldPadding vertical
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 13,
                  ),
                ),
              ),
            ),
            Container(width: 1, height: 28, color: dividerColor),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(unit, style: _labelStyle(context)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Static (read-only) type box ────────────────────────────────────────────
  Widget _staticTypeBox(String label) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Material(
      elevation: 2,
      color: Colors.transparent,
      shadowColor: Colors.grey,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        // ✅ matches _fieldPadding
        padding: _fieldPadding,
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
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent stripe
              Container(width: 12, color: const Color(0xFF002D44)),

              // Form content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Header ───────────────────────────────────────────
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Add new item',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyLarge?.color,
                              ),
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.close,
                                color: Theme.of(
                                  context,
                                ).textTheme.bodyMedium?.color,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ── Name field ───────────────────────────────────────
                        CustomTextField(
                          controller: _nameController,
                          label: _nameLabel,
                          border: 8,
                          contentPadding: _fieldPadding,
                        ),
                        const SizedBox(height: 14),

                        // ── Qty + Dosage row ─────────────────────────────────
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text('Qty:', style: _labelStyle(context)),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 50,
                              child: CustomTextField(
                                controller: _qtyController,
                                border: 8,
                                keyboardType: TextInputType.number,
                                contentPadding: _fieldPadding,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _compactUnitBox(
                              controller: _mgController,
                              focusNode: _mgFocusNode,
                              unit: _unitLabel,
                            ),
                            const SizedBox(width: 8),
                            Text(_perLabel, style: _labelStyle(context)),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // ── Category + Type row ──────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: CustomDropdown(
                                label: 'Category:',
                                value: selectedCategory,
                                border: 8,
                                contentPadding: _fieldPadding,
                                items: const [
                                  'Medicine',
                                  'Vitamins',
                                  'Vaccine',
                                ],
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
                                  if (selectedCategory == 'Vaccine')
                                    _staticTypeBox('Fluid')
                                  else if (selectedCategory == 'Vitamins')
                                    _staticTypeBox('Powder')
                                  else
                                    CustomDropdown(
                                      key: ValueKey(selectedCategory),
                                      value: selectedType,
                                      border: 8,
                                      contentPadding: _fieldPadding,
                                      items: _typeOptions,
                                      onChanged: _onTypeChanged,
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // ── Expiry + Reorder row ─────────────────────────────
                        Row(
                          children: [
                            Expanded(
                              child: CustomTextField(
                                controller: _expiryController,
                                label: 'Expiry date:',
                                border: 8,
                                readonly: true,
                                onTap: _selectDate,
                                contentPadding: _fieldPadding,
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
                                contentPadding: _fieldPadding,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // ── Description ──────────────────────────────────────
                        CustomTextField(
                          controller: _descController,
                          label: 'Description:',
                          border: 8,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 20,
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
