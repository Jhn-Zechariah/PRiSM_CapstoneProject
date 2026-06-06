import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/widgets/textfield.dart';
import '../../../../core/widgets/dropdown.dart'; // Ensure CustomDropdown is imported
import '../../domain/model/app_medicine.dart';
import '../../domain/model/app_medicine_stock.dart';
import '../cubits/medicine_cubit.dart';
import 'meds_combo_box.dart'; // The new component we just made

class MedicineIntakeDialog extends StatefulWidget {
  final Color accentColor;
  final String intakeType;
  final List<Medicine> availableMedicines;

  const MedicineIntakeDialog({
    super.key,
    required this.accentColor,
    required this.intakeType,
    required this.availableMedicines,
  });

  @override
  State<MedicineIntakeDialog> createState() => _MedicineIntakeDialogState();
}

class _MedicineIntakeDialogState extends State<MedicineIntakeDialog> {
  final _dosageController = TextEditingController();
  final _scheduleController = TextEditingController();
  final _purposeController = TextEditingController();

  static const _fieldPadding = EdgeInsets.symmetric(horizontal: 12, vertical: 13);

  String _selectedStatus = 'Ongoing';
  final List<String> _statusOptions = ['Ongoing', 'Completed', 'Discontinued'];

  Medicine? _selectedMedicine;
  MedicineStock? _selectedStockBatch;
  List<MedicineStock> _fetchedBatches = [];
  bool _isLoadingSubStocks = false;

  @override
  void dispose() {
    _dosageController.dispose();
    _scheduleController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  List<Medicine> get _filteredMedicines {
    String targetCategory = '';
    final type = widget.intakeType.toLowerCase();

    if (type == 'medicine') targetCategory = 'medicine';
    else if (type == 'vitamin') targetCategory = 'vitamins';
    else if (type == 'vaccine') targetCategory = 'vaccine';

    return widget.availableMedicines.where((med) {
      final matchesCategory = med.category.toLowerCase() == targetCategory;
      // 🔹 Check if totalStock is greater than 0 (Adjust property name if your model uses 'qty' or 'amount')
      final hasStock = med.totalStock > 0;

      return matchesCategory && hasStock;
    }).toList();
  }

  String get _dosageUnit {
    if (_selectedMedicine == null) return 'unit';
    final medType = (_selectedMedicine?.type ?? '').toLowerCase();
    switch (medType) {
      case 'fluid': return 'ml';
      case 'powder': return 'g';
      case 'capsule': return 'tablet';
      default: return 'unit';
    }
  }

  // Helper to format dropdown strings consistently
  String _formatBatch(MedicineStock batch) => '${batch.expiryDate} (Qty: ${batch.amount})';

  Future<void> _selectDate() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime(2101),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: ColorScheme.light(primary: widget.accentColor),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() => _scheduleController.text = "${picked.toLocal()}".split(' ')[0]);
    }
  }

  void _onSave() {
    Navigator.pop(context, {
      'type': widget.intakeType.toLowerCase(),
      'medicineId': _selectedMedicine?.medId,
      'stockDocId': _selectedStockBatch?.id,
      'expiryDate': _selectedStockBatch?.expiryDate ?? 'Manual Input',
      'dosage': _dosageController.text,
      'status': _selectedStatus,
      'nextSchedule': _scheduleController.text,
      'purpose': _purposeController.text,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final batchOptions = _fetchedBatches.map(_formatBatch).toList();
    final selectedBatchString = _selectedStockBatch != null ? _formatBatch(_selectedStockBatch!) : '';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 10, color: widget.accentColor),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${widget.intakeType} Intake', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: theme.textTheme.bodyLarge?.color)),
                          GestureDetector(onTap: () => Navigator.pop(context), child: Icon(Icons.close, size: 20, color: theme.textTheme.bodyMedium?.color)),
                        ],
                      ),
                      const SizedBox(height: 16),

                      MedicineSearchComboBox(
                        label: '${widget.intakeType}:',
                        medicines: _filteredMedicines,
                        onCleared: () => setState(() {
                          _selectedMedicine = null;
                          _fetchedBatches = [];
                          _selectedStockBatch = null;
                        }),
                        onSelected: (selection) async {
                          final medId = selection.medId;
                          if (medId == null) return;

                          setState(() {
                            _selectedMedicine = selection;
                            _isLoadingSubStocks = true;
                            _selectedStockBatch = null;
                          });

                          final stocks = await context.read<MedicineCubit>().getStocksForMedicine(medId);
                          setState(() {
                            _fetchedBatches = stocks;
                            _isLoadingSubStocks = false;
                            if (_fetchedBatches.isNotEmpty) _selectedStockBatch = _fetchedBatches.first;
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      _isLoadingSubStocks
                          ? const Center(child: CircularProgressIndicator())
                          : CustomDropdown(
                        label: 'Select Batch (Expiry Date):',
                        value: selectedBatchString,
                        border: 8,
                        contentPadding: _fieldPadding,
                        items: batchOptions,
                        onChanged: (val) {
                          setState(() {
                            _selectedStockBatch = _fetchedBatches.firstWhere((b) => _formatBatch(b) == val);
                          });
                        },
                      ),
                      const SizedBox(height: 12),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            flex: 3,
                            child: CustomTextField(
                              label: 'Dosage:',
                              controller: _dosageController,
                              border: 8,
                              keyboardType: TextInputType.number,
                              contentPadding: _fieldPadding,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Text(_dosageUnit, style: TextStyle(fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            flex: 5,
                            child: CustomDropdown(
                              label: 'Status:',
                              value: _selectedStatus,
                              border: 8,
                              contentPadding: _fieldPadding,
                              items: _statusOptions,
                              onChanged: (val) => setState(() => _selectedStatus = val!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _selectDate,
                              child: IgnorePointer(
                                child: CustomTextField(
                                  label: 'Next Schedule:',
                                  controller: _scheduleController,
                                  border: 8,
                                  contentPadding: _fieldPadding,
                                  suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Label
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    'Previous Record:',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.white54
                                          : Colors.grey[600],
                                    ),
                                  ),
                                ),
                                // The Display Box
                                Container(
                                  width: double.infinity,
                                  padding: _fieldPadding,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? const Color(0xFF2A2A2A)
                                        : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.white12
                                          : Colors.grey[300]!,
                                    ),
                                  ),
                                  child: Text(
                                    '—', // 🔹 Put your actual record data here later
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Theme.of(context).brightness == Brightness.dark
                                          ? Colors.white54
                                          : Colors.grey[500],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      CustomTextField(
                        label: 'Purpose: (Optional)',
                        controller: _purposeController,
                        border: 8,
                        maxLines: 2,
                        contentPadding: _fieldPadding,
                      ),
                      const SizedBox(height: 20),

                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _onSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('Save Record', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
}