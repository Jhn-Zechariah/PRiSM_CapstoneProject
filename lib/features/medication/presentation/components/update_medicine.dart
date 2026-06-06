import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/button.dart';
import 'package:prism_app/core/widgets/snackbar.dart';

import '../../../../core/widgets/confirmation_box.dart';
import '../../../../core/widgets/dropdown.dart';
import '../../../../core/widgets/textfield.dart';
import '../../domain/model/app_medicine.dart';
import '../../domain/model/app_medicine_stock.dart';
import '../cubits/medicine_cubit.dart';
import '../cubits/medicine_states.dart';

class UpdateMedicineDialog extends StatefulWidget {
  final Color accentColor;
  final Medicine medicine; // 🔹 Passed from the MedicineCard click

  const UpdateMedicineDialog({
    super.key,
    required this.medicine,
    this.accentColor = const Color(0xFF002D44),
  });

  @override
  State<UpdateMedicineDialog> createState() => _UpdateMedicineDialogState();
}

class _UpdateMedicineDialogState extends State<UpdateMedicineDialog> {
  bool _isLoading = false;
  static const _fieldPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 13);

  final _nameController = TextEditingController();
  final _qtyController = TextEditingController();
  final _expiryController = TextEditingController();
  final _reorderController = TextEditingController();

  String _unitLabel = 'tablet';

  // State for fetching and selecting stocks
  List<MedicineStock> _availableStocks = [];
  MedicineStock? _selectedStock;
  String? _selectedExpiryDate;
  bool _isFetchingStocks = true;

  @override
  void initState() {
    super.initState();
    // 🔹 Pre-fill data from the parent Medicine object
    _nameController.text = widget.medicine.name;
    _reorderController.text = widget.medicine.reorderLevel.round().toString();
    _unitLabel = widget.medicine.measurementUnit;

    _fetchStocks();
  }

  Future<void> _fetchStocks() async {
    // 🔹 Added "?? ''" to safely handle the null check
    final stocks = await context.read<MedicineCubit>().getStocksForMedicine(widget.medicine.medId ?? '');

    if (mounted) {
      setState(() {
        _availableStocks = stocks;
        _isFetchingStocks = false;

        // Auto-select the first stock batch if available
        if (stocks.isNotEmpty) {
          _onStockSelected(stocks.last.expiryDate);
        }
      });
    }
  }

  void _onStockSelected(String? expiryDate) {
    if (expiryDate == null) return;

    // Find the actual stock object based on the selected expiry date
    final stock = _availableStocks.firstWhere((s) => s.expiryDate == expiryDate);

    setState(() {
      _selectedExpiryDate = expiryDate;
      _selectedStock = stock;
      // 🔹 Auto-fill the inputs with this specific batch's data
      _qtyController.text = stock.amount.round().toString();
      _expiryController.text = stock.expiryDate;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _qtyController.dispose();
    _expiryController.dispose();
    _reorderController.dispose();
    super.dispose();
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

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Invalid Input', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK', style: TextStyle(color: Color(0xFF002D44))),
          ),
        ],
      ),
    );
  }

  Future<void> _onSave() async {
    if (_nameController.text.trim().isEmpty) {
      _showErrorDialog('Please enter a medicine name.');
      return;
    }

    if (_selectedStock == null) {
      _showErrorDialog('No stock batch selected to update.');
      return;
    }

    final double parsedQty = double.tryParse(_qtyController.text) ?? -1.0;
    if (parsedQty < 0) {
      _showErrorDialog('Amount cannot be a negative number.');
      return;
    }

    final double parsedReorder = double.tryParse(_reorderController.text) ?? 0.0;
    if (parsedReorder < 0) {
      _showErrorDialog('Re-order alert level cannot be a negative number.');
      return;
    }

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
      // Create the updated objects
      final updatedMedicine = widget.medicine.copyWith(
        name: _nameController.text.trim(),
        reorderLevel: parsedReorder,
      );

      final updatedStock = _selectedStock!.copyWith(
        amount: parsedQty,
        expiryDate: _expiryController.text.trim(),
      );

      // We need the document ID of the specific stock batch (Assuming your model holds it as 'id')
      // If your model uses a different field name for the doc ID, change `.id` to that.
      final stockDocId = _selectedStock!.id ?? '';
      final oldStockAmount = _selectedStock!.amount;

      context.read<MedicineCubit>().updateMedicineItem(
        medicine: updatedMedicine,
        updatedStock: updatedStock,
        stockDocId: stockDocId, // 👈 Identifies which exact batch to update in Firestore
        oldStockAmount: oldStockAmount,
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

  @override
  Widget build(BuildContext context) {
    return BlocListener<MedicineCubit, MedicineState>(
      listener: (context, state) {
        if (state is MedicineLoading) {
          setState(() => _isLoading = true);
        } else if (state is MedicineSaveSuccess) {
          setState(() => _isLoading = false);
          Navigator.pop(context);
          CustomSnackbar.show(context: context, message: 'Item updated successfully!');
        } else if (state is MedicineError) {
          setState(() => _isLoading = false);
          _showErrorDialog(state.message);
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
                Container(width: 12, color: widget.accentColor),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 🔹 1. Header (Always visible so the user can close it)
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Update Medicine',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: Theme.of(context).textTheme.bodyLarge?.color,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.close, color: Theme.of(context).textTheme.bodyMedium?.color),
                                onPressed: () => Navigator.pop(context),
                              ),
                            ],
                          ),

                          // 🔹 2. Show a big loader if fetching, otherwise show the full form
                          if (_isFetchingStocks)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40.0),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else ...[
                            CustomTextField(
                              label: 'Medicine Name:',
                              controller: _nameController,
                              border: 8,
                              contentPadding: _fieldPadding,
                            ),

                            const SizedBox(height: 12),

                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Left Side: Dropdown (No longer needs its own loading check)
                                Expanded(
                                  flex: 3,
                                  child: CustomDropdown(
                                    label: 'Select Batch (Expiry Date):',
                                    value: _selectedExpiryDate ?? '',
                                    border: 8,
                                    contentPadding: _fieldPadding,
                                    items: _availableStocks.map((s) => s.expiryDate).toList(),
                                    onChanged: _onStockSelected,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                // Right Side: Re-order Alert & Unit
                                Expanded(
                                  flex: 2,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Expanded(
                                        child: CustomTextField(
                                          label: 'Re-order:',
                                          controller: _reorderController,
                                          border: 8,
                                          keyboardType: TextInputType.number,
                                          contentPadding: _fieldPadding,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 14),
                                        child: Text(_unitLabel, style: _labelStyle(context)),
                                      ),
                                    ],
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
                                    label: 'Amount:',
                                    controller: _qtyController,
                                    border: 8,
                                    keyboardType: TextInputType.number,
                                    contentPadding: _fieldPadding,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: CustomTextField(
                                    label: 'Expiry date:',
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
                              ],
                            ),

                            const SizedBox(height: 20),
                            CustomButton(
                              text: _isLoading ? 'Updating...' : 'Update Item',
                              border: 8,
                              backgroundColor: const Color(0xFF2563EB),
                              color: Colors.white,
                              borderColor: false,
                              onPressed: _onSave,
                            ),
                          ], // End of form spread
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