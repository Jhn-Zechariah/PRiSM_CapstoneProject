import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import '../features/auth/presentation/components/app_top_bar.dart';

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

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : Colors.grey[100],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTopBar(showBackButton: true),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 5),

                        // Pig icon — replace with your asset if available
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

                        // Form card
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
                                    child: _buildLabeledField(
                                      label: 'Birth Month:',
                                      isDarkMode: isDarkMode,
                                      child: _buildTextField(
                                        controller: _birthMonthController,
                                        isDarkMode: isDarkMode,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildLabeledField(
                                      label: 'Sex:',
                                      isDarkMode: isDarkMode,
                                      child: _buildDropdownField(isDarkMode),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Row 2: Breed + Weight
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildLabeledField(
                                      label: 'Breed:',
                                      isDarkMode: isDarkMode,
                                      child: _buildTextField(
                                        controller: _breedController,
                                        isDarkMode: isDarkMode,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: _buildLabeledField(
                                      label: 'Weight:',
                                      isDarkMode: isDarkMode,
                                      child: _buildTextField(
                                        controller: _weightController,
                                        isDarkMode: isDarkMode,
                                        keyboardType: TextInputType.number,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),

                              // Stage
                              _buildLabeledField(
                                label: 'Stage:',
                                isDarkMode: isDarkMode,
                                child: _buildTextField(
                                  controller: _stageController,
                                  isDarkMode: isDarkMode,
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Status
                              _buildLabeledField(
                                label: 'Status:',
                                isDarkMode: isDarkMode,
                                child: _buildTextField(
                                  controller: _statusController,
                                  isDarkMode: isDarkMode,
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Save button
                              SizedBox(
                                width: double.infinity,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: _onSave,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFF5A623),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'Save',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
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

  Widget _buildLabeledField({
    required String label,
    required Widget child,
    required bool isDarkMode,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: isDarkMode ? Colors.white70 : Colors.black87,
          ),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required bool isDarkMode,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      style: TextStyle(
        fontSize: 14,
        color: isDarkMode ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.white24 : Colors.black26,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.white24 : Colors.black26,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFF5A623)),
        ),
        filled: true,
        fillColor: isDarkMode ? const Color(0xFF2A2A2A) : Colors.white,
      ),
    );
  }

  Widget _buildDropdownField(bool isDarkMode) {
    return DropdownButtonFormField<String>(
      initialValue: _selectedSex,
      isDense: true,
      dropdownColor: isDarkMode ? const Color(0xFF2A2A2A) : Colors.white,
      style: TextStyle(
        fontSize: 14,
        color: isDarkMode ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.white24 : Colors.black26,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.white24 : Colors.black26,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFF5A623)),
        ),
        filled: true,
        fillColor: isDarkMode ? const Color(0xFF2A2A2A) : Colors.white,
      ),
      icon: Icon(
        Icons.arrow_drop_down,
        size: 20,
        color: isDarkMode ? Colors.white54 : Colors.black54,
      ),
      items: _sexOptions.map((sex) {
        return DropdownMenuItem(value: sex, child: Text(sex));
      }).toList(),
      onChanged: (value) => setState(() => _selectedSex = value),
    );
  }
}