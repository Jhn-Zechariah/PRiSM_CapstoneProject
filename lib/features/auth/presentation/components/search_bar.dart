import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

class MedicineSearchBar extends StatelessWidget {
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onClear;

  const MedicineSearchBar({
    super.key,
    this.controller,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      onSubmitted: onSubmitted,

      decoration: InputDecoration(
        hintText: "Search medicine",
        prefixIcon: const Icon(Symbols.search),
        suffixIcon: (controller != null && controller!.text.isNotEmpty)
            ? IconButton(
                icon: const Icon(Symbols.close),
                onPressed:
                    onClear ??
                    () {
                      controller?.clear();
                    },
              )
            : null,
        filled: true,
        fillColor: isDarkMode ? Colors.grey[900] : Colors.grey[200],

        contentPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 12),
        isDense: true,

        constraints: const BoxConstraints(minHeight: 30, maxHeight: 35),

        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey, width: 1),
        ),

        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: Colors.blue, // color when clicked
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
