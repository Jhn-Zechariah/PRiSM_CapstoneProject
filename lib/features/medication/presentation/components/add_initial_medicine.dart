import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:prism_app/core/widgets/button.dart';
import 'package:prism_app/core/widgets/snackbar.dart';

import '../../../../core/widgets/confirmation_box.dart';
import '../../../../core/widgets/dropdown.dart';
import '../../../../core/widgets/error_dialog.dart';
import '../../../../core/widgets/textfield.dart';
import '../../domain/model/app_medicine.dart';
import '../../domain/model/app_medicine_stock.dart';
import '../cubits/medicine_cubit.dart';
import '../cubits/medicine_states.dart';

class AddNewMedDialog extends StatefulWidget {
  final Color accentColor;

  const AddNewMedDialog({
    super.key,
    this.accentColor = const Color(0xFF002D44),
  });

  @override
  State<AddNewMedDialog> createState() => _AddNewMedDialogState();
}

class _AddNewMedDialogState extends State<AddNewMedDialog> {
  bool _isLoading = false;
  static const _fieldPadding = EdgeInsets.symmetric(
    horizontal: 12,
    vertical: 13,
  );

  final _nameController = TextEditingController();
  final _qtyController = TextEditingController();
  final _expiryController = TextEditingController();
  final _reorderController = TextEditingController();
  final _descController = TextEditingController();
  final _mgFocusNode = FocusNode();

  String selectedCategory = 'Medicine';
  String selectedType = 'Capsule';
  String _unitLabel = 'tablet';

  @override
  void initState() {
    super.initState();
    _mgFocusNode.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _nameController.dispose();
    _qtyController.dispose();
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

  String get _amount {
    if (selectedType == 'Capsule') return 'Tablet/s:';
    if (selectedType == 'Fluid') return 'Amount (mL):';
    return 'Amount (g):';
  }

  List<String> get _typeOptions {
    if (selectedCategory == 'Vitamins') return ['Powder', 'Fluid'];
    return ['Capsule', 'Fluid'];
  }

  void _syncLabels() {
    if (selectedCategory == 'Vaccine' || selectedType == 'Fluid') {
      _unitLabel = 'mL';
    } else if (selectedCategory == 'Vitamins') {
      _unitLabel = 'g   ';
    } else {
      _unitLabel = 'tablet';
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
    final DateTime now = DateTime.now(); // 🔹 Get the current date and time

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now, // Default to today
      firstDate: now,   // 🔹 This disables all past dates!
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
    // 🔹 1. Validate required fields before proceeding
    if (_nameController.text.trim().isEmpty) {
      CustomErrorDialog.show(
          context: context,
          message: 'Please enter a ${_nameLabel.replaceAll(':', '').toLowerCase()}.'
      );
      return;
    }

    if (_qtyController.text.trim().isEmpty) {
      CustomErrorDialog.show(context: context, message: 'Please enter a valid amount.');
      return;
    }

    final double parsedQty = double.tryParse(_qtyController.text) ?? -1.0;
    if (parsedQty < 0) {
      CustomErrorDialog.show(context: context, message: 'Amount cannot be a negative number.');
      return;
    }

    final double parsedReorder = double.tryParse(_reorderController.text) ?? 0.0;
    if (parsedReorder < 0) {
      CustomErrorDialog.show(context: context, message: 'Re-order alert level cannot be a negative number.');
      return;
    }

    // 🔹 2. Show confirmation dialog only if validation passes
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
      // Get the current logged-in user's ID
      final currentUser = FirebaseAuth.instance.currentUser;
      final currentUserId = currentUser?.uid ?? 'unknown_user';

      // Pre-generate unique cross-linked reference document ID
      final generatedMedicineId = FirebaseFirestore.instance.collection('medicines').doc().id;

      // Build the Medicine Profile model structure
      final newMedicine = Medicine(
        medId: generatedMedicineId,
        userId: currentUserId,
        name: _nameController.text.trim(),
        category: selectedCategory,
        type: selectedType,
        measurementUnit: _unitLabel.trim(),
        reorderLevel: parsedReorder, // 👈 Using the safely parsed variable here
        totalStock: parsedQty,
      );

      // Build the nested Subcollection Item structural model
      final initialStockBatch = MedicineStock(
        medicineId: generatedMedicineId,
        expiryDate: _expiryController.text.trim().isEmpty ? 'No Expiry Date Set' : _expiryController.text.trim(),
        amount: parsedQty,
      );

      // Dispatch execution request down through Cubit plumbing layers
      if (mounted) {
        context.read<MedicineCubit>().saveMedicineWithStock(
          medicine: newMedicine,
          initialBatch: initialStockBatch,
        );
      }
    }
  }

  TextStyle _labelStyle(BuildContext context) {
    return TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      color: Theme.of(context).textTheme.bodySmall?.color,
    );
  }

  Widget _labeledField({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _labelStyle(context)),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<MedicineCubit, MedicineState>(
      listener: (context, state) {
        if (state is MedicineLoading) {
          setState(() => _isLoading = true);
        } else if (state is MedicineSaveSuccess) {
          setState(() => _isLoading = false);
          Navigator.pop(context);
          CustomSnackbar.show(
            context: context,
            message: 'Item added successfully!',
          );
        } else if (state is MedicineError) {
          setState(() => _isLoading = false);
          CustomSnackbar.show(
            context: context,
            isError: true,
            message: state.message,
          );
        }
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 12, color: const Color(0xFF002D44)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Add new item',
                                style: TextStyle(
                                  fontSize: 20,
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

                          CustomTextField(
                            label: _nameLabel,
                            controller: _nameController,
                            border: 8,
                            contentPadding: _fieldPadding,
                          ),

                          const SizedBox(height: 12),

                          Row(
                            children: [
                              Expanded(
                                child: CustomDropdown(
                                  label: 'Category:',
                                  value: selectedCategory,
                                  border: 8,
                                  contentPadding: _fieldPadding,
                                  items: const ['Medicine', 'Vitamins', 'Vaccine'],
                                  onChanged: _onCategoryChanged,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: CustomDropdown(
                                  label: 'Type:',
                                  key: ValueKey(selectedCategory),
                                  value: selectedType,
                                  border: 8,
                                  enabled: selectedCategory != 'Vaccine',
                                  contentPadding: _fieldPadding,
                                  items: _typeOptions,
                                  onChanged: _onTypeChanged,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: CustomTextField(
                                  label: _amount,
                                  controller: _qtyController,
                                  border: 8,
                                  keyboardType: TextInputType.number,
                                  contentPadding: _fieldPadding,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _labeledField(
                                  label: 'Expiry date:',
                                  child: CustomTextField(
                                    controller: _expiryController,
                                    border: 8,
                                    readonly: true,
                                    onTap: _selectDate,
                                    contentPadding: _fieldPadding,
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.calendar_month_outlined, size: 20),
                                      onPressed: _selectDate,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: _labeledField(
                                  label: 'Re-order stock alert:',
                                  child: CustomTextField(
                                    controller: _reorderController,
                                    border: 8,
                                    keyboardType: TextInputType.number,
                                    contentPadding: _fieldPadding,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Padding(
                                padding: const EdgeInsets.only(bottom: 14),
                                child: Text(
                                  _unitLabel,
                                  style: _labelStyle(context),
                                ),
                              ),
                              const SizedBox(width: 135),
                            ],
                          ),
                          const SizedBox(height: 20),
                          CustomButton(
                            text: _isLoading ? 'Saving...' : 'Save Item',
                            border: 8,
                            backgroundColor: const Color(0xFF2563EB),
                            color: Colors.white,
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
      ),
    );
  }
}