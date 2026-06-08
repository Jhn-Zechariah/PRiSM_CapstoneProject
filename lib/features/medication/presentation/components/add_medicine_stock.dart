import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/button.dart';
import 'package:prism_app/core/widgets/snackbar.dart';

import '../../../../core/widgets/confirmation_box.dart';
import '../../../../core/widgets/error_dialog.dart';
import '../../../../core/widgets/textfield.dart';
import '../../domain/model/app_medicine.dart';
import '../../domain/model/app_medicine_stock.dart';
import '../cubits/medicine_cubit.dart';
import '../cubits/medicine_states.dart';

class AddNewMedStockDialog extends StatefulWidget {
  final Color accentColor;
  final Medicine medicine;

  const AddNewMedStockDialog({
    super.key,
    this.accentColor = const Color(0xFF002D44),
    required this.medicine,
  });

  @override
  State<AddNewMedStockDialog> createState() => _AddNewMedStockDialogState();
}

class _AddNewMedStockDialogState extends State<AddNewMedStockDialog> {
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

  String get _amount {
    if (widget.medicine.measurementUnit == 'tablet') return 'Tablet/s:';
    if (widget.medicine.measurementUnit == 'mL') return 'Amount (mL):';
    return 'Amount (g):';
  }

  Future<void> _selectDate() async {
    final DateTime now = DateTime.now();

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
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
    if (_qtyController.text.trim().isEmpty) {
      CustomErrorDialog.show(
        context: context,
        message: 'Please enter the stock amount.',
      );
      return;
    }

    final double parsedQty = double.tryParse(_qtyController.text) ?? -1.0;
    if (parsedQty <= 0) {
      CustomErrorDialog.show(
        context: context,
        message: 'Amount must be greater than zero.',
      );
      return;
    }

    final double parsedReorder =
        double.tryParse(_reorderController.text) ?? 0.0;
    if (parsedReorder < 0) {
      CustomErrorDialog.show(
        context: context,
        message: 'Re-order alert level cannot be negative.',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => const CustomConfirmDialog(
        title: 'Add New Stock',
        content: 'Are you sure you want to add this stock batch?',
        confirmText: 'Add Stock',
        cancelText: 'Cancel',
        confirmColor: Color(0xFF002D44),
      ),
    );

    if (confirmed == true && mounted) {
      final newStock = MedicineStock(
        id: '',
        medicineId: widget.medicine.medId ?? '',
        amount: parsedQty,
        expiryDate: _expiryController.text.trim().isEmpty ? 'No Expiry Date Set' : _expiryController.text.trim(),
      );

      final updatedMedicine = widget.medicine.copyWith(
        reorderLevel: parsedReorder,
      );

      context.read<MedicineCubit>().addNewStockBatch(
        medicine: updatedMedicine,
        newStock: newStock,
      );
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
                                'Add new stock',
                                style: TextStyle(
                                  fontSize: 20,
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

                          const SizedBox(height: 12),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              // 🔹 Fixed narrow width for quantity field
                              SizedBox(
                                width: 110,
                                child: CustomTextField(
                                  label: _amount,
                                  controller: _qtyController,
                                  border: 8,
                                  keyboardType: TextInputType.number,
                                  contentPadding: _fieldPadding,
                                ),
                              ),
                              const SizedBox(width: 12),
                              // 🔹 Expiry date fills remaining space
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
                                      icon: const Icon(
                                        Icons.calendar_month_outlined,
                                        size: 20,
                                      ),
                                      onPressed: _selectDate,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          CustomButton(
                            text: _isLoading ? 'Adding...' : 'Add Stock',
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
