// import 'package:flutter/material.dart';
//
// class CustomSearchComboBox<T extends Object> extends StatefulWidget {
//   final String? label;
//   final String? hintText;
//   final double? border;
//   final EdgeInsetsGeometry? contentPadding;
//
//   final List<T> items;
//   final String Function(T) displayStringForOption;
//   final bool Function(T item, String query) filterFn;
//   final Widget Function(T item)? itemBuilder; // Optional custom UI for dropdown items
//
//   final ValueChanged<T> onSelected;
//   final VoidCallback? onCleared;
//   final bool enabled;
//
//   const CustomSearchComboBox({
//     super.key,
//     this.label,
//     this.hintText,
//     this.border,
//     this.contentPadding,
//     required this.items,
//     required this.displayStringForOption,
//     required this.filterFn,
//     this.itemBuilder,
//     required this.onSelected,
//     this.onCleared,
//     this.enabled = true,
//   });
//
//   @override
//   State<CustomSearchComboBox<T>> createState() => _CustomSearchComboBoxState<T>();
// }
//
// class _CustomSearchComboBoxState<T extends Object> extends State<CustomSearchComboBox<T>> {
//   final GlobalKey _autocompleteKey = GlobalKey();
//   final TextEditingController _internalController = TextEditingController();
//
//   @override
//   void dispose() {
//     _internalController.dispose();
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     final isDarkMode = Theme.of(context).brightness == Brightness.dark;
//     final bool isDisabled = !widget.enabled;
//
//     // Matching your CustomTextField color logic
//     final resolvedTextColor = isDisabled
//         ? (isDarkMode ? Colors.white54 : Colors.grey[500])
//         : (isDarkMode ? Colors.white : Colors.black87);
//
//     final resolvedFillColor = isDisabled
//         ? (isDarkMode ? const Color(0xFF2A2A2A) : Colors.grey[200])
//         : (isDarkMode ? const Color(0xFF1E1E1E) : Colors.white);
//
//     final resolvedBorderColor = isDisabled
//         ? (isDarkMode ? Colors.white12 : Colors.grey[300]!)
//         : (isDarkMode ? Colors.white24 : Colors.black26);
//
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       mainAxisSize: MainAxisSize.min,
//       children: [
//         if (widget.label != null) ...[
//           Padding(
//             padding: const EdgeInsets.only(bottom: 4),
//             child: Text(
//               widget.label!,
//               style: TextStyle(
//                 fontSize: 12,
//                 fontWeight: FontWeight.w500,
//                 color: isDisabled
//                     ? (isDarkMode ? Colors.white54 : Colors.grey[600])
//                     : (isDarkMode ? Colors.white70 : Colors.black87),
//               ),
//             ),
//           ),
//         ],
//         Container(
//           key: _autocompleteKey,
//           child: Autocomplete<T>(
//             optionsBuilder: (TextEditingValue textEditingValue) {
//               if (textEditingValue.text.isEmpty) return const Iterable<T>.empty();
//               return widget.items.where((item) => widget.filterFn(item, textEditingValue.text));
//             },
//             displayStringForOption: widget.displayStringForOption,
//             fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
//               // Sync local controller to detect clearing
//               if (_internalController.text != controller.text && _internalController.text.isEmpty) {
//                 controller.text = _internalController.text;
//               }
//               controller.addListener(() {
//                 _internalController.text = controller.text;
//                 if (controller.text.isEmpty && widget.onCleared != null) {
//                   widget.onCleared!();
//                 }
//               });
//
//               // The exact styling of your CustomTextField
//               return Material(
//                 elevation: isDisabled ? 2 : 5,
//                 color: Colors.transparent,
//                 borderRadius: BorderRadius.circular(widget.border ?? 30),
//                 child: TextFormField(
//                   controller: controller,
//                   focusNode: focusNode, // FocusNode is strictly required here for Autocomplete
//                   enabled: widget.enabled,
//                   style: TextStyle(fontSize: 14, color: resolvedTextColor),
//                   decoration: InputDecoration(
//                     hintText: widget.hintText,
//                     hintStyle: TextStyle(color: isDarkMode ? Colors.white60 : Colors.black54),
//                     isDense: widget.contentPadding != null,
//                     contentPadding: widget.contentPadding,
//                     filled: true,
//                     fillColor: resolvedFillColor,
//                     disabledBorder: OutlineInputBorder(
//                       borderRadius: BorderRadius.circular(widget.border ?? 30),
//                       borderSide: BorderSide(color: resolvedBorderColor),
//                     ),
//                     enabledBorder: OutlineInputBorder(
//                       borderRadius: BorderRadius.circular(widget.border ?? 30),
//                       borderSide: BorderSide(color: resolvedBorderColor),
//                     ),
//                     focusedBorder: OutlineInputBorder(
//                       borderRadius: BorderRadius.circular(widget.border ?? 30),
//                       borderSide: BorderSide(color: isDisabled ? resolvedBorderColor : Colors.blue),
//                     ),
//                     border: OutlineInputBorder(
//                       borderRadius: BorderRadius.circular(widget.border ?? 30),
//                     ),
//                   ),
//                 ),
//               );
//             },
//             onSelected: widget.onSelected,
//             optionsViewBuilder: (context, onSelected, options) {
//               final renderBox = _autocompleteKey.currentContext?.findRenderObject() as RenderBox?;
//               final width = renderBox?.size.width ?? 300.0;
//
//               return Align(
//                 alignment: Alignment.topLeft,
//                 child: Material(
//                   elevation: 5.0, // Matches your CustomTextField active elevation
//                   color: resolvedFillColor,
//                   borderRadius: BorderRadius.circular(widget.border ?? 30),
//                   clipBehavior: Clip.antiAlias, // Ensures items don't bleed over the rounded corners
//                   child: Container(
//                     width: width,
//                     constraints: const BoxConstraints(maxHeight: 200),
//                     child: ListView.builder(
//                       padding: EdgeInsets.zero,
//                       shrinkWrap: true,
//                       itemCount: options.length,
//                       itemBuilder: (context, index) {
//                         final option = options.elementAt(index);
//                         // Use custom builder if provided, otherwise default to simple text
//                         if (widget.itemBuilder != null) {
//                           return InkWell(
//                             onTap: () => onSelected(option),
//                             child: widget.itemBuilder!(option),
//                           );
//                         }
//                         return ListTile(
//                           title: Text(
//                             widget.displayStringForOption(option),
//                             style: TextStyle(color: resolvedTextColor),
//                           ),
//                           onTap: () => onSelected(option),
//                         );
//                       },
//                     ),
//                   ),
//                 ),
//               );
//             },
//           ),
//         ),
//       ],
//     );
//   }
// }