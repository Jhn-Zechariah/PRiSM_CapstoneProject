import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_svg/svg.dart';
import '../features/auth/data/firestore_pig_repo.dart';
import '../features/auth/domain/models/app_pig.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import '../features/auth/presentation/components/custom_button.dart';
import '../features/auth/presentation/components/snackbar.dart';
import '../features/auth/presentation/components/textfield.dart';
import '../features/auth/presentation/components/dropdown.dart';
import '../features/auth/presentation/cubits/pig_cubit.dart';

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

  //dropdown options
  String? _selectedSex;
  final List<String> _sexOptions = ['Male', 'Female'];
  String? _selectedStage;
  final List<String> _stageOptions = ['Piglet', 'Weanling', 'Grower', "Barrow"];
  String? _selectedStatus;
  final List<String> _statusOptions = ['Normal/Healthy', 'Abnormal/Sick', 'Sold' ,'Deceased'];

  @override
  void initState() {
    super.initState();

    // If we passed an existing pig, populate the fields!
    if (widget.existingPig != null) {
      final pig = widget.existingPig!;
      _breedController.text = pig.breed;
      _weightController.text = pig.currentWeightKg.toString();
      _birthDateController.text = pig.birthDate.toString().split(' ')[0];
      if (_sexOptions.contains(pig.sex)) {
        _selectedSex = pig.sex;
      }
      if (_stageOptions.contains(pig.stage)) {
        _selectedStage = pig.stage;
      }
      if(_statusOptions.contains(pig.status)){
        _selectedStatus = pig.status;
      }
      // Set your date, sex, and stage variables here as well
    }
  }

  @override
  void dispose() {
    _birthDateController.dispose();
    _breedController.dispose();
    _weightController.dispose();
    super.dispose();
  }

  final pigRepo = FirebasePigRepo();

  void _onSave() async {
    // 1. ALWAYS validate the form first, for both Add and Update modes!
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_isLoading) return;

    setState(() => _isLoading = true);

    final pigCubit = context.read<PigCubit>();

    if (widget.existingPig != null) {
      // UPDATE MODE
      final updatedPig = AppPig(
        pigId: widget.existingPig!.pigId,
        userId: widget.existingPig!.userId, // KEEP the original user ID!
        displayId: widget.existingPig!.displayId, // KEEP the original display ID!
        breed: _breedController.text,
        //Grab the updated date from the controller
        birthDate: DateTime.tryParse(_birthDateController.text) ?? widget.existingPig!.birthDate,
        sex: _selectedSex!,
        stage: _selectedStage!,
        status: _selectedStatus!,
        notes: widget.existingPig!.notes, // KEEP the existing notes!
        currentWeightKg: double.tryParse(_weightController.text) ?? widget.existingPig!.currentWeightKg,
      );

      pigCubit.updatePigDetails(updatedPig);

      if (!mounted) return;
      CustomSnackbar.show(
        context: context,
        message: "Pig updated successfully!",
      );
      Navigator.pop(context); // Close the screen after updating!

    } else {
      // ADD MODE
      final newPig = AppPig(
        pigId: '',
        userId: '', // The Repo will populate this automatically
        displayId: '', // The Repo will populate this automatically
        breed: _breedController.text,
        birthDate: DateTime.tryParse(_birthDateController.text) ?? DateTime.now(),
        sex: _selectedSex!,
        currentWeightKg: double.parse(_weightController.text),
        notes: 'Pig Registered',
        stage: _selectedStage!,
        status: _selectedStatus!,
      );

      try {
        await pigRepo.addPig(newPig);

        if (!mounted) return; // Safety check before showing SnackBar
        CustomSnackbar.show(
          context: context,
          message: "Pig Profile Saved!",
        );
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        CustomSnackbar.show(
          context: context,
          isError: true,
          message: "Error saving: $e",
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final fieldPadding = const EdgeInsets.symmetric(horizontal: 10, vertical: 10);
    final fillColor = isDarkMode ? const Color(0xFF2A2A2A) : Colors.white;

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
                          isDarkMode ? 'assets/pig_dark.svg' : 'assets/pig_light.svg',
                          height: 120,
                          width: 120,
                        ),

                        Text(
                          'Pig Information',
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
                            color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [
                              BoxShadow(
                                color: Colors.black12,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Row 1: Birth Month + Sex
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start, // Helps align if error text shows
                                children: [
                                  Expanded(
                                    child: CustomTextField(
                                      label: 'Birth Date:',
                                      readonly: true,
                                      prefixIcon: Icons.calendar_month,
                                      controller: _birthDateController,
                                      border: 6,
                                      contentPadding: fieldPadding,
                                      filled: true,
                                      fillColor: fillColor,
                                      onTap: () => _selectDate(context),
                                      validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: CustomDropdown(
                                      label: 'Sex:',
                                      value: _selectedSex,
                                      items: _sexOptions,
                                      border: 6,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      filled: true,
                                      fillColor: fillColor,
                                      onChanged: (value) => setState(() => _selectedSex = value),
                                      validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Row 2: Breed + Weight
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: CustomTextField(
                                      label: 'Breed:',
                                      controller: _breedController,
                                      border: 6,
                                      contentPadding: fieldPadding,
                                      filled: true,
                                      fillColor: fillColor,
                                      // 👇 Validator added
                                      validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: CustomTextField(
                                      label: 'Weight:',
                                      controller: _weightController,
                                      border: 6,
                                      keyboardType: TextInputType.number,
                                      contentPadding: fieldPadding,
                                      filled: true,
                                      fillColor: fillColor,
                                      validator: (value) {
                                        if (value == null || value.isEmpty) return 'Required';
                                        if (double.tryParse(value) == null) return 'Invalid number';
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Stage
                              CustomDropdown(
                                label: 'Stage:',
                                value: _selectedStage,
                                items: _stageOptions,
                                border: 6,
                                contentPadding: fieldPadding,
                                filled: true,
                                fillColor: fillColor,
                                onChanged: (value) => setState(() => _selectedStage = value),
                                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                              ),
                              const SizedBox(height: 12),

                              // Status
                              CustomDropdown(
                                label: 'Status:',
                                value: _selectedStatus,
                                items: _statusOptions,
                                border: 6,
                                contentPadding: fieldPadding,
                                filled: true,
                                fillColor: fillColor,
                                onChanged: (value) => setState(() => _selectedStatus = value),
                                // 👇 Validator added
                                validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                              ),
                              const SizedBox(height: 20),

                              // Save button
                              CustomButton(
                                text: 'Save',
                                border: 10,
                                onPressed: _onSave,
                                color: isDarkMode ? Colors.black87 : Colors.black87,
                              ),
                              const SizedBox(height: 12),
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
    DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2090),
    );

    if (picked != null) {
      setState(() {
        _birthDateController.text = picked.toString().split(' ')[0];
      });
    }
  }
}