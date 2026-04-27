import 'package:flutter/material.dart';

import '../features/auth/presentation/components/custom_button.dart';

class UpdatePigWeightDialog extends StatefulWidget {
  final String pigLabel;
  final double currentWeight;
  final Color accentColor;

  const UpdatePigWeightDialog({
    super.key,
    required this.pigLabel,
    required this.currentWeight,
    required this.accentColor,
  });

  @override
  State<UpdatePigWeightDialog> createState() => _UpdatePigWeightDialogState();
}

class _UpdatePigWeightDialogState extends State<UpdatePigWeightDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(double.parse(_controller.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent stripe
              Container(width: 10, color: widget.accentColor),

              // Dialog content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Title row with X button
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Update weight',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            GestureDetector(
                              onTap: () => Navigator.of(context).pop(),
                              child: const Icon(Icons.close, size: 20),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Pig label
                        Text(
                          widget.pigLabel,
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 10),

                        // Current weight
                        Text(
                          'Current weight: ${widget.currentWeight == 0.0 ? '' : '${widget.currentWeight} kg'}',
                          style: const TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 10),

                        // Updated weight label
                        const Text(
                          'Updated weight:',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 6),

                        // Text input
                        TextFormField(
                          controller: _controller,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Colors.black26,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: widget.accentColor,
                                width: 2,
                              ),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.red),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.red),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Enter a weight';
                            }
                            if (double.tryParse(value) == null) {
                              return 'Enter a valid number';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),

                        // Update button (full width, amber)
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child:  CustomButton(
                            text: 'Update',
                            backgroundColor: Colors.amber,
                            color: Colors.black87,
                            border: 10,
                            onPressed: _submit,
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
