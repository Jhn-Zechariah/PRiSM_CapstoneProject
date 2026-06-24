import 'package:flutter/material.dart';
import '../../../../core/widgets/textfield.dart';
import '../../domain/model/app_medicine.dart';

class MedicineSearchComboBox extends StatefulWidget {
  final String label;
  final List<Medicine> medicines;
  final ValueChanged<Medicine> onSelected;
  final VoidCallback onCleared;

  const MedicineSearchComboBox({
    super.key,
    required this.label,
    required this.medicines,
    required this.onSelected,
    required this.onCleared,
  });

  @override
  State<MedicineSearchComboBox> createState() => _MedicineSearchComboBoxState();
}

class _MedicineSearchComboBoxState extends State<MedicineSearchComboBox> {
  final GlobalKey _autocompleteKey = GlobalKey();
  final TextEditingController _internalController = TextEditingController();

  // 🔹 Tracks which controller we've already attached a listener to.
  TextEditingController? _attachedController;

  @override
  void dispose() {
    _internalController.dispose();
    super.dispose();
  }

  void _onControllerChanged(TextEditingController controller) {
    if (!mounted) return;
    _internalController.text = controller.text;
    if (controller.text.isEmpty) widget.onCleared();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      key: _autocompleteKey,
      child: Autocomplete<Medicine>(
        optionsBuilder: (textEditingValue) {
          if (textEditingValue.text.isEmpty) return const Iterable<Medicine>.empty();
          return widget.medicines.where((item) =>
              item.name.toLowerCase().contains(textEditingValue.text.toLowerCase()));
        },
        displayStringForOption: (item) => item.name,
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          // 🔹 Only attach once per controller instance — fixes the leak.
          if (_attachedController != controller) {
            _attachedController = controller;
            controller.addListener(() => _onControllerChanged(controller));
          }

          return CustomTextField(
            label: widget.label,
            controller: controller,
            focusNode: focusNode,
            border: 8,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
            hint: 'Type or choose...',
          );
        },
        onSelected: widget.onSelected,
        optionsViewBuilder: (context, onSelected, options) {
          final renderBox = _autocompleteKey.currentContext?.findRenderObject() as RenderBox?;
          final width = renderBox?.size.width ?? 300.0;

          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4.0,
              color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: width,
                constraints: const BoxConstraints(maxHeight: 200),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (context, index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      title: Text(option.name, style: TextStyle(color: theme.textTheme.bodyMedium?.color)),
                      subtitle: Text('Total Stock: ${option.totalStock}', style: const TextStyle(fontSize: 11)),
                      onTap: () => onSelected(option),
                    );
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}