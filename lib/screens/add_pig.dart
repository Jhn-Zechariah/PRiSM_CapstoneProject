import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import '../features/auth/presentation/components/custom_button.dart';
import '../features/auth/presentation/components/custom_textfield.dart';
import '../features/auth/presentation/components/dropdown.dart';


class PigInformationScreen extends StatefulWidget {
  const PigInformationScreen({super.key});

  @override
  State<PigInformationScreen> createState() => _PigInformationScreenState();
}

class _PigInformationScreenState extends State<PigInformationScreen> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _birthMonthController = TextEditingController();
  final TextEditingController _breedController = TextEditingController();
  final TextEditingController _weightController = TextEditingController();
  final TextEditingController _stageController = TextEditingController();
  final TextEditingController _statusController = TextEditingController();

  String? _selectedSex;
  final List<String> _sexOptions = ['Male', 'Female'];

  String? _selectedStage;
  final List<String> _stageOptions = ['Piglet', 'Weanling', 'Grower', "Barrow"];

  String? _selectedStatus;
  final List<String> _statusOptions = ['Normal/Healthy', 'Abnormal/Sick', 'Deceased'];

  @override
  void dispose() {
    _birthMonthController.dispose();
    _breedController.dispose();
    _weightController.dispose();
    _stageController.dispose();
    _statusController.dispose();
    super.dispose();
  }

  void _onSave() {
    if (_formKey.currentState?.validate() ?? false) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pig information saved!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Extracted some reusable styling variables to make the form cleaner
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
                                children: [
                                  Expanded(
                                    child: CustomTextField(
                                      label: 'Birth Month:',
                                      controller: _birthMonthController,
                                      border: 6,
                                      contentPadding: fieldPadding,
                                      filled: true,
                                      fillColor: fillColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    //CustomDropdown in action!
                                    child: CustomDropdown(
                                      label: 'Sex:',
                                      value: _selectedSex,
                                      items: _sexOptions,
                                      border: 6,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      filled: true,
                                      fillColor: fillColor,
                                      onChanged: (value) => setState(() => _selectedSex = value),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Row 2: Breed + Weight
                              Row(
                                children: [
                                  Expanded(
                                    child: CustomTextField(
                                      label: 'Breed:',
                                      controller: _breedController,
                                      border: 6,
                                      contentPadding: fieldPadding,
                                      filled: true,
                                      fillColor: fillColor,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: CustomTextField(
                                      label: 'Weight:',
                                      controller: _weightController,
                                      border: 6,
                                      keyboardType: TextInputType.number, // Uses the new parameter!
                                      contentPadding: fieldPadding,
                                      filled: true,
                                      fillColor: fillColor,
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
                              ),
                              const SizedBox(height: 20),

                              // Save button
                              CustomButton(
                                text: 'Save',
                                backgroundColor: const Color(0xFFF5A623),
                                border: 10,
                                onPressed: _onSave,
                                color: isDarkMode? Colors.black87 : Colors.black87,
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
}