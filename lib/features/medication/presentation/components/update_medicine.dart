import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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

class UpdateMedicineDialog extends StatefulWidget {
  final Color accentColor;
  final Medicine medicine;

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

  List<MedicineStock> _availableStocks = [];
  MedicineStock? _selectedStock;
  String? _selectedExpiryDate;
  bool _isFetchingStocks = true;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.medicine.name;
    _reorderController.text = widget.medicine.reorderLevel.round().toString();
    _unitLabel = widget.medicine.measurementUnit;

    _fetchStocks();
  }

  String get _amount {
    if (widget.medicine.measurementUnit == 'tablet') return 'Tablet/s:';
    if (widget.medicine.measurementUnit == 'mL') return 'Amount (mL):';
    return 'Amount (g):';
  }

  Future<void> _fetchStocks() async {
    final stocks = await context.read<MedicineCubit>().getStocksForMedicine(widget.medicine.medId ?? '');

    if (mounted) {
      setState(() {
        _availableStocks = stocks;
        _isFetchingStocks = false;

        if (stocks.isNotEmpty) {
          // 🔹 Map empty string to 'No Expiry Date' for the initial selection
          final initialExpiry = stocks.last.expiryDate;
          _onStockSelected(initialExpiry);
        }
      });
    }
  }

  void _onStockSelected(String? displayValue) {
    if (displayValue == null || displayValue == 'No Stock') return;

    // 🔹 Swap 'No Expiry Date' back to '' to find the exact merged batch
    final searchValue = displayValue;
    final stock = _availableStocks.firstWhere((s) => s.expiryDate == searchValue);

    setState(() {
      _selectedExpiryDate = displayValue;
      _selectedStock = stock;
      _qtyController.text = stock.amount.round().toString();
      _expiryController.text = stock.expiryDate == 'No Expiry Date Set' ? '' : stock.expiryDate;
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

  Future<void> _onSave() async {
    if (_nameController.text.trim().isEmpty) {
      CustomErrorDialog.show(context: context, message: 'Please enter a medicine name.');
      return;
    }

    if (_selectedStock == null) {
      CustomErrorDialog.show(context: context, message: 'No stock batch selected to update.');
      return;
    }

    if (_qtyController.text.trim().isEmpty) {
      CustomErrorDialog.show(context: context, message: 'Please enter the stock amount.');
      return;
    }

    final double parsedQty = double.tryParse(_qtyController.text) ?? -1.0;
    if (parsedQty <= 0) {
      CustomErrorDialog.show(context: context, message: 'Amount must be greater than zero.');
      return;
    }

    final double parsedReorder = double.tryParse(_reorderController.text) ?? 0.0;
    if (parsedReorder < 0) {
      CustomErrorDialog.show(context: context, message: 'Re-order alert level cannot be negative.');
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
      final updatedMedicine = widget.medicine.copyWith(
        name: _nameController.text.trim(),
        reorderLevel: parsedReorder,
      );

      final updatedStock = _selectedStock!.copyWith(
        amount: parsedQty,
        expiryDate: _expiryController.text.trim(),
      );

      final stockDocId = _selectedStock!.id ?? '';
      final oldStockAmount = _selectedStock!.amount;

      context.read<MedicineCubit>().updateMedicineItem(
        medicine: updatedMedicine,
        updatedStock: updatedStock,
        stockDocId: stockDocId,
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
    final bool hasStocks = _availableStocks.isNotEmpty;

    // 🔹 Map empty dates to 'No Expiry Date' for the Dropdown items
    final List<String> dropdownItems = hasStocks
        ? _availableStocks.map((s) => s.expiryDate.trim().isEmpty ? 'No Expiry Date' : s.expiryDate).toList()
        : ['No Stock'];

    final String dropdownValue = hasStocks && _selectedExpiryDate != null
        ? _selectedExpiryDate!
        : 'No Stock';

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
          CustomErrorDialog.show(context: context, message: state.message);
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
                                Expanded(
                                  flex: 3,
                                  child: CustomDropdown(
                                    label: 'Select Batch (Expiry Date):',
                                    value: dropdownValue,
                                    border: 8,
                                    enabled: hasStocks,
                                    contentPadding: _fieldPadding,
                                    items: dropdownItems,
                                    onChanged: hasStocks ? _onStockSelected : (val) {},
                                  ),
                                ),
                                const SizedBox(width: 12),
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
                                    label: _amount,
                                    controller: _qtyController,
                                    border: 8,
                                    enabled: hasStocks,
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
                                    enabled: hasStocks,
                                    readonly: true,
                                    onTap: hasStocks ? _selectDate : () {},
                                    contentPadding: _fieldPadding,
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.calendar_month_outlined, size: 20),
                                      onPressed: hasStocks ? _selectDate : null,
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
                          ],
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