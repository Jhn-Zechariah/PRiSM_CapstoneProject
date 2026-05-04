import 'package:flutter/material.dart';

class MedicineIntakeDialog extends StatefulWidget {
  final Color accentColor;

  const MedicineIntakeDialog({super.key, required this.accentColor});

  @override
  State<MedicineIntakeDialog> createState() => _MedicineIntakeDialogState();
}

class _MedicineIntakeDialogState extends State<MedicineIntakeDialog> {
  final _medsController = TextEditingController();
  final _dosageController = TextEditingController();
  final _scheduleController = TextEditingController();
  final _purposeController = TextEditingController();
  String? _selectedStatus;

  final List<String> _statusOptions = ['Ongoing', 'Completed', 'Discontinued'];

  @override
  void dispose() {
    _medsController.dispose();
    _dosageController.dispose();
    _scheduleController.dispose();
    _purposeController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
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
        _scheduleController.text = "${picked.toLocal()}".split(' ')[0];
      });
    }
  }

  void _onSave() {
    Navigator.pop(context, {
      'type': 'medicine',
      'name': _medsController.text,
      'dosage': _dosageController.text,
      'status': _selectedStatus,
      'nextSchedule': _scheduleController.text,
      'purpose': _purposeController.text,
    });
  }

  TextStyle _labelStyle(BuildContext context) => TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    color: Theme.of(context).textTheme.bodySmall?.color,
  );

  Widget _buildField({
    required TextEditingController controller,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
    String? hint,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return TextField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      maxLines: maxLines,
      keyboardType: keyboardType,
      style: TextStyle(fontSize: 14, color: theme.textTheme.bodyMedium?.color),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: isDark ? Colors.white38 : Colors.black38,
          fontSize: 14,
        ),
        suffixIcon: suffixIcon,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDark ? Colors.white24 : Colors.black26,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: widget.accentColor, width: 1.5),
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2A2A2A) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDark ? Colors.white24 : Colors.black26),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedStatus,
          isDense: true,
          isExpanded: true,
          dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
          icon: Icon(
            Icons.unfold_more,
            size: 18,
            color: theme.textTheme.bodySmall?.color,
          ),
          style: TextStyle(
            fontSize: 14,
            color: theme.textTheme.bodyMedium?.color,
          ),
          items: _statusOptions
              .map((s) => DropdownMenuItem(value: s, child: Text(s)))
              .toList(),
          onChanged: (val) => setState(() => _selectedStatus = val),
        ),
      ),
    );
  }

  Widget _buildPreviousRecord(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isDark ? Colors.white12 : Colors.grey.shade300,
        ),
      ),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Text(
        '—',
        style: TextStyle(fontSize: 14, color: theme.textTheme.bodySmall?.color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 10, color: widget.accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Pig intake',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: theme.textTheme.bodyLarge?.color,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Icon(
                              Icons.close,
                              size: 20,
                              color: theme.textTheme.bodyMedium?.color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),

                      // Meds/vit
                      Text('Meds/vit:', style: _labelStyle(context)),
                      const SizedBox(height: 4),
                      _buildField(
                        controller: _medsController,
                        hint: 'Medicine/vitamins',
                      ),
                      const SizedBox(height: 12),

                      // Dosage + Status
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Dosage:', style: _labelStyle(context)),
                                const SizedBox(height: 4),
                                _buildField(
                                  controller: _dosageController,
                                  keyboardType: TextInputType.number,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Status:', style: _labelStyle(context)),
                                const SizedBox(height: 4),
                                _buildDropdown(),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Next Schedule + Previous Record
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Next Schedule:',
                                  style: _labelStyle(context),
                                ),
                                const SizedBox(height: 4),
                                _buildField(
                                  controller: _scheduleController,
                                  readOnly: true,
                                  onTap: _selectDate,
                                  suffixIcon: IconButton(
                                    icon: const Icon(
                                      Icons.calendar_today_outlined,
                                      size: 18,
                                    ),
                                    onPressed: _selectDate,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Previous Record:',
                                  style: _labelStyle(context),
                                ),
                                const SizedBox(height: 4),
                                _buildPreviousRecord(context),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Purpose
                      Text('Purpose:', style: _labelStyle(context)),
                      const SizedBox(height: 4),
                      _buildField(
                        controller: _purposeController,
                        keyboardType: TextInputType.multiline,
                      ),
                      const SizedBox(height: 20),

                      // Save button
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _onSave,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber,
                            foregroundColor: Colors.black,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
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
              ),
            ],
          ),
        ),
      ),
    );
  }
}
