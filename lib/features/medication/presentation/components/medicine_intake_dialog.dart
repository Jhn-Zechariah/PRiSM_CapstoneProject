import 'package:cloud_firestore/cloud_firestore.dart'; // 🔹 Added for one-time fetch
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart'; // 🔹 Added for date formatting
import '../../../../core/widgets/error_dialog.dart';
import '../../../../core/widgets/textfield.dart';
import '../../../../core/widgets/dropdown.dart';
import '../../domain/model/app_medicine.dart';
import '../../domain/model/app_medicine_stock.dart';
import '../../domain/model/app_medicine_intake.dart';
import '../cubits/medicine_cubit.dart';
import '../cubits/medicine_states.dart';
import 'meds_combo_box.dart';

class MedicineIntakeDialog extends StatefulWidget {
  final Color accentColor;
  final String intakeType;
  //final List<Medicine> availableMedicines;
  final String pigId;

  const MedicineIntakeDialog({
    super.key,
    required this.accentColor,
    required this.intakeType,
    //required this.availableMedicines,
    required this.pigId,
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

  // 🔹 Added state for previous record
  String _previousRecordText = '—';

  @override
  void dispose() {
    _dosageController.dispose();
    _scheduleController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  // 🔹 Logic to fetch the last time this medicine was given to this pig
  Future<void> _fetchPreviousRecord(String medName) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('pigs')
          .doc(widget.pigId)
          .collection('medicine_intakes')
          .where('medName', isEqualTo: medName)
          .orderBy('dateTaken', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.serverAndCache));

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data();
        final dateTaken = DateTime.parse(data['dateTaken']);
        final dosage = data['dosage'];
        final unit = data['unitOfMeasurement'];

        setState(() {
          _previousRecordText = "${DateFormat('MMM dd').format(dateTaken)} ($dosage$unit)";
        });
      } else {
        setState(() => _previousRecordText = 'No history');
      }
    } catch (e) {
      debugPrint("Error fetching previous record: $e");
      setState(() => _previousRecordText = '—');
    }
  }

  List<Medicine> _filteredMedicines(List<Medicine> allMedicines) {
    String targetCategory = '';
    final type = widget.intakeType.toLowerCase();
    if (type == 'medicine') targetCategory = 'medicine';
    else if (type == 'vitamin') targetCategory = 'vitamin';
    else if (type == 'vaccine') targetCategory = 'vaccine';
    return allMedicines.where((med) {
      return med.category.toLowerCase() == targetCategory && med.totalStock > 0;
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

  String _formatBatch(MedicineStock batch) => '${batch.expiryDate} | (${batch.amount.round()} ${_dosageUnit})';

  DateTime? _selectedNextSchedule; // 🔹 new field, replaces parsing the text controller

  Future<void> _selectDate() async {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final picked = await showDatePicker(
      context: context,
      initialDate: tomorrow,
      firstDate: tomorrow,
      lastDate: DateTime(2101),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(colorScheme: ColorScheme.light(primary: widget.accentColor)),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedNextSchedule = DateTime(picked.year, picked.month, picked.day);
        _scheduleController.text = "${picked.toLocal()}".split(' ')[0]; // display only
      });
    }
  }

  void _onSave() {
    if (_selectedMedicine == null || _selectedMedicine?.medId == null) {
      CustomErrorDialog.show(context: context, message: 'Please select a medicine first.');
      return;
    }
    if (_selectedStockBatch == null) {
      CustomErrorDialog.show(context: context, message: 'Please select a stock batch.');
      return;
    }
    final dosageAmount = double.tryParse(_dosageController.text.trim()) ?? 0.0;
    final availableStock = _selectedStockBatch!.amount;

    if (dosageAmount <= 0) {
      CustomErrorDialog.show(context: context, message: 'Dosage must be greater than zero.');
      return;
    }
    if (dosageAmount > availableStock) {
      CustomErrorDialog.show(context: context, message: 'Insufficient batch stock.');
      return;
    }

    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final newRecord = MedicineIntake(
      pigId: widget.pigId,
      userId: userId,
      category: _selectedMedicine!.category,
      medName: _selectedMedicine!.name,
      dosage: _dosageController.text.trim(),
      unitOfMeasurement: _dosageUnit,
      status: _selectedStatus,
      nextSchedule: _selectedNextSchedule, // 🔹 DateTime?, not a string
      purpose: _purposeController.text.isEmpty ? null : _purposeController.text,
      dateTaken: DateTime.now(),
    );

    Navigator.pop(context, {
      'intake': newRecord,
      'selectedStock': _selectedStockBatch,
      'medicineId': _selectedMedicine!.medId,
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final batchOptions = _fetchedBatches.map(_formatBatch).toList();
    final selectedBatchString = _selectedStockBatch != null ? _formatBatch(_selectedStockBatch!) : '';

    return BlocBuilder<MedicineCubit, MedicineState>(
    buildWhen: (prev, curr) => curr is MedicineLoaded,
    builder: (context, state) {
    final allMedicines = state is MedicineLoaded
    ? state.medicines
        : context.read<MedicineCubit>().currentMedicines;

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
                        medicines: _filteredMedicines(allMedicines),
                        onCleared: () => setState(() {
                          _selectedMedicine = null;
                          _fetchedBatches = [];
                          _selectedStockBatch = null;
                          _previousRecordText = '—';
                        }),
                        onSelected: (selection) async {
                          setState(() {
                            _selectedMedicine = selection;
                            _isLoadingSubStocks = true;
                            _selectedStockBatch = null;
                          });

                          // 🔹 Optimization: Fetch data sequentially
                          await _fetchPreviousRecord(selection.name);
                          final stocks = await context.read<MedicineCubit>().getStocksForMedicine(selection.medId!);

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
                          Expanded(flex: 3, child: CustomTextField(label: 'Dosage:', controller: _dosageController, border: 8, keyboardType: TextInputType.number, contentPadding: _fieldPadding)),
                          const SizedBox(width: 5),
                          Padding(padding: const EdgeInsets.only(bottom: 14), child: Text('| $_dosageUnit', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                          const SizedBox(width: 16),
                          Expanded(flex: 5, child: CustomDropdown(label: 'Status:', value: _selectedStatus, border: 8, contentPadding: _fieldPadding, items: _statusOptions, onChanged: (val) => setState(() => _selectedStatus = val!))),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: _selectDate,
                              child: IgnorePointer(
                                child: CustomTextField(label: 'Next Schedule:', controller: _scheduleController, border: 8, contentPadding: _fieldPadding, suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Previous Record:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: theme.brightness == Brightness.dark ? Colors.white54 : Colors.grey[600])),
                                const SizedBox(height: 4),
                                Container(
                                  width: double.infinity,
                                  padding: _fieldPadding,
                                  decoration: BoxDecoration(
                                    color: theme.brightness == Brightness.dark ? const Color(0xFF2A2A2A) : Colors.grey[200],
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: theme.brightness == Brightness.dark ? Colors.white12 : Colors.grey[300]!),
                                  ),
                                  child: Text(_previousRecordText, style: TextStyle(fontSize: 14, color: theme.brightness == Brightness.dark ? Colors.white54 : Colors.grey[500])),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      CustomTextField(label: 'Purpose: (Optional)', controller: _purposeController, border: 8, maxLines: 2, contentPadding: _fieldPadding),
                      const SizedBox(height: 20),
                      SizedBox(width: double.infinity, height: 48, child: ElevatedButton(onPressed: _onSave, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))), child: const Text('Save Record', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  },
  );
}
}