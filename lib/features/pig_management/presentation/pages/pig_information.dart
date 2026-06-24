import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import '../../../../core/widgets/dropdown.dart';
import '../../domain/model/app_pig.dart';
import '../../../../core/widgets/app_top_bar.dart';
import '../../../../core/widgets/button.dart';
import '../../../../core/widgets/confirmation_box.dart';
import '../../../../core/widgets/snackbar.dart';
import '../../../../core/widgets/textfield.dart';
import '../cubits/pig_cubit.dart';
import '../cubits/pig_states.dart';


class PigInformationScreen extends StatefulWidget {
  final AppPig? existingPig;
  const PigInformationScreen({super.key, this.existingPig});


  @override
  State<PigInformationScreen> createState() => _PigInformationScreenState();
}


class _PigInformationScreenState extends State<PigInformationScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;


  final TextEditingController _birthDateController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _stageController = TextEditingController();


  // dropdown options
  String? _selectedSex;
  final List<String> _sexOptions = ['Male', 'Female'];
  String? _selectedStage;
  String? _selectedStatus;


  // 👇 Removed 'final' so we can assign it dynamically
  List<String> _statusOptions = [];


  @override
  void initState() {
    super.initState();


    if (widget.existingPig != null) {
      // UPDATE MODE: All options available
      _statusOptions = ['Normal/Healthy', 'Abnormal/Sick', 'Sold', 'Deceased'];


      final pig = widget.existingPig!;
      _breedController.text = pig.breed;
      _weightController.text = pig.currentWeightKg.toString();
      _birthDateController.text = pig.birthDate.toString().split(' ')[0];
      if (_sexOptions.contains(pig.sex)) {
        _selectedSex = pig.sex;
      }
      if (_statusOptions.contains(pig.status)) {
        _selectedStatus = pig.status;
      }
    } else {
      // ADD MODE: Only Healthy and Sick options available
      _statusOptions = ['Normal/Healthy', 'Abnormal/Sick'];
    }

    // Stage is always derived automatically from the birth date.
    _updateStageFromBirthDate();
  }


  @override
  void dispose() {
    _birthDateController.dispose();
    _breedController.dispose();
    _weightController.dispose();
    _stageController.dispose();
    super.dispose();
  }


  /// Calculates the pig's life stage based on its age in days:
  /// - Piglet: 0-21 days
  /// - Nursery: 22-70 days
  /// - Grower: 71-120 days
  /// - Finisher: 121-170 days
  /// - Mature: 171+ days (fallback for anything beyond the finisher window)
  String _calculateStage(DateTime birthDate) {
    final ageInDays = DateTime.now().difference(birthDate).inDays;

    if (ageInDays < 0) {
      // Defensive fallback; birth date should never be in the future.
      return 'Piglet';
    } else if (ageInDays <= 21) {
      return 'Piglet';
    } else if (ageInDays <= 70) {
      return 'Nursery';
    } else if (ageInDays <= 120) {
      return 'Grower';
    } else if (ageInDays <= 170) {
      return 'Finisher';
    } else {
      return 'Mature';
    }
  }


  /// Re-derives the stage from whatever is currently in the birth date
  /// field and pushes it into both the backing value and its controller.
  void _updateStageFromBirthDate() {
    final parsedDate = DateTime.tryParse(_birthDateController.text);
    if (parsedDate == null) {
      _selectedStage = null;
      _stageController.text = '';
      return;
    }

    final stage = _calculateStage(parsedDate);
    _selectedStage = stage;
    _stageController.text = stage;
  }


  void _onSave() async {
    if (!_formKey.currentState!.validate()) return;


    // 2. Check for confirmation dialog condition if updating
    if (widget.existingPig != null) {
      final isMarkingInactive =
          _selectedStatus == 'Sold' || _selectedStatus == 'Deceased';
      final statusChanged = _selectedStatus != widget.existingPig!.status;


      // Only show dialog if they are changing the status TO Sold or Deceased
      if (isMarkingInactive && statusChanged) {
        final shouldProceed = await showDialog<bool>(
          context: context,
          builder: (context) => CustomConfirmDialog(
            title: 'Confirm Status Change',
            content:
            'Are you sure you want to mark ${widget.existingPig!.breed}/${widget.existingPig!.displayId} as $_selectedStatus?',
            confirmText: 'Yes, Proceed',
            cancelText: 'Cancel',
            confirmColor: Colors.amber.shade700,
          ),
        );


        // If they click outside the box or hit Cancel, abort the save.
        if (shouldProceed != true) {
          return;
        }
      }
    }


    if (_isLoading) return;
    setState(() => _isLoading = true);
    final pigCubit = context.read<PigCubit>();


    if (widget.existingPig != null) {
      String notes = "";


      if (_selectedStatus == 'Sold') {
        notes = "Sold at ${DateTime.now().toString().split(' ')[0]}";
      } else if (_selectedStatus == 'Deceased') {
        notes = "Deceased at ${DateTime.now().toString().split(' ')[0]}";
      }


      // UPDATE MODE
      final updatedPig = AppPig(
        pigId: widget.existingPig!.pigId,
        userId: widget.existingPig!.userId,
        displayId: widget.existingPig!.displayId,
        breed: _breedController.text,
        birthDate:
        DateTime.tryParse(_birthDateController.text) ??
            widget.existingPig!.birthDate,
        sex: _selectedSex!,
        birthWeightKg: widget.existingPig!.birthWeightKg,
        stage: _selectedStage!,
        status: _selectedStatus!,
        notes: notes,
        currentWeightKg:
        double.tryParse(_weightController.text) ??
            widget.existingPig!.currentWeightKg,
      );

      try {
        await pigCubit.updatePigDetails(
          updatedPig,
          oldWeightKg: widget.existingPig!.currentWeightKg,
        );

        if (!mounted) return;

        // ✅ Check if the cubit emitted an error before celebrating
        final currentState = pigCubit.state;
        if (currentState is PigError) {
          CustomSnackbar.show(
            context: context,
            isError: true,
            message: "Failed to update pig. Please try again.",
          );
          return;
        }

        CustomSnackbar.show(
          context: context,
          message: "Pig updated successfully!",
        );
        Navigator.pop(context);
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    } else {
      // ADD MODE
      final newPig = AppPig(
        pigId: '',
        userId: '',
        displayId: '',
        breed: _breedController.text,
        birthDate:
        DateTime.tryParse(_birthDateController.text) ?? DateTime.now(),
        sex: _selectedSex!,
        birthWeightKg: double.parse('1.4'), // Default birth weight (can be updated later)
        currentWeightKg: double.parse(_weightController.text),
        notes: 'Pig Registered ',
        stage: _selectedStage!,
        status: _selectedStatus!,
      );


      try {
        await pigCubit.addPig(newPig);


        if (!mounted) return;
        CustomSnackbar.show(context: context, message: "Pig Profile Saved!");
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        CustomSnackbar.show(
          context: context,
          isError: true,
          message: "Error saving: $e",
        );
      } finally {
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final fieldPadding = const EdgeInsets.symmetric(
      horizontal: 10,
      vertical: 14,
    );


    final isReadOnly =
        widget.existingPig != null &&
            (widget.existingPig!.status.toLowerCase() == 'sold' ||
                widget.existingPig!.status.toLowerCase() == 'deceased');


    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppTopBar(showBackButton: true),
              const SizedBox(height: 17),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          isDarkMode
                              ? 'assets/pig_dark.svg'
                              : 'assets/pig_light.svg',
                          height: 120,
                          width: 120,
                        ),


                        Text(
                          isReadOnly
                              ? 'View Pig Information'
                              : 'Pig Information',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 20),


                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.black54),
                            color: isDarkMode
                                ? const Color(0xFF1E1E1E)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black26,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: CustomTextField(
                                      label: 'Birth Date:',
                                      readonly: true,
                                      enabled: !isReadOnly,
                                      borderColor: Colors.black54,
                                      prefixIcon: Icons.calendar_month,
                                      controller: _birthDateController,
                                      border: 6,
                                      onTap: () {
                                        if (!isReadOnly) _selectDate(context);
                                      },
                                      validator: (value) =>
                                      value == null || value.isEmpty
                                          ? 'Required'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: CustomDropdown(
                                      label: 'Sex:',
                                      value: _selectedSex,
                                      items: _sexOptions,
                                      borderColor: Colors.black54,
                                      border: 6,
                                      contentPadding: fieldPadding,
                                      readonly: isReadOnly,
                                      enabled: !isReadOnly,
                                      onChanged: (newValue) {
                                        setState(
                                              () => _selectedSex = newValue!,
                                        );
                                      },
                                      validator: (value) =>
                                      value == null || value.isEmpty
                                          ? 'Required'
                                          : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),


                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: CustomTextField(
                                      label: 'Breed:',
                                      readonly: isReadOnly,
                                      enabled: !isReadOnly,
                                      controller: _breedController,
                                      borderColor: Colors.black54,
                                      border: 6,
                                      contentPadding: fieldPadding,
                                      validator: (value) =>
                                      value == null || value.isEmpty
                                          ? 'Required'
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: CustomTextField(
                                      label: 'Weight:',
                                      readonly: isReadOnly,
                                      enabled: !isReadOnly,
                                      controller: _weightController,
                                      borderColor: Colors.black54,
                                      border: 6,
                                      keyboardType: TextInputType.number,
                                      contentPadding: fieldPadding,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Required';
                                        }
                                        if (double.tryParse(value) == null) {
                                          return 'Invalid number';
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),


                              // Stage is now a disabled/read-only text field whose
                              // value is computed automatically from the birth date
                              // (Piglet: 0-21d, Nursery: 22-70d, Grower: 71-120d,
                              // Finisher: 121-170d).
                              CustomTextField(
                                label: 'Stage:',
                                readonly: true,
                                enabled: false,
                                controller: _stageController,
                                borderColor: Colors.black54,
                                border: 6,
                                contentPadding: fieldPadding,
                              ),
                              const SizedBox(height: 12),


                              CustomDropdown(
                                label: 'Status:',
                                value: _selectedStatus,
                                items:
                                _statusOptions, // 👇 Uses the dynamic list now
                                borderColor: Colors.black54,
                                border: 6,
                                contentPadding: fieldPadding,
                                readonly: isReadOnly,
                                enabled: !isReadOnly,
                                onChanged: (newValue) {
                                  setState(() => _selectedStatus = newValue!);
                                },
                                validator: (value) =>
                                value == null || value.isEmpty
                                    ? 'Required'
                                    : null,
                              ),
                              const SizedBox(height: 20),


                              if (!isReadOnly) ...[
                                CustomButton(
                                  text: _isLoading ? 'Saving...' : 'Save',
                                  backgroundColor: Colors.blue,
                                  border: 10,
                                  onPressed: _onSave,
                                  color: isDarkMode
                                      ? Colors.black87
                                      : Colors.black87,
                                ),
                                const SizedBox(height: 12),
                              ],
                            ],
                          ),
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


  Future<void> _selectDate(BuildContext context) async {
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: todayOnly,
      firstDate: DateTime(2020),
      // Cap selection at today so a future birth date can't be chosen.
      lastDate: todayOnly,
    );


    if (picked != null) {
      setState(() {
        _birthDateController.text = picked.toString().split(' ')[0];
        _updateStageFromBirthDate();
      });
    }
  }
}