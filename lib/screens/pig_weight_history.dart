import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../features/auth/domain/models/app_weight_history.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import '../features/auth/domain/models/app_pig.dart';
import '../features/auth/presentation/cubits/weight_history_cubit.dart';
import '../features/auth/presentation/cubits/weight_history_states.dart';


class WeightHistoryScreen extends StatefulWidget {
  final List<AppPig> availablePigs; // Pass your loaded pigs here

  const WeightHistoryScreen({super.key, required this.availablePigs});

  @override
  State<WeightHistoryScreen> createState() => _WeightHistoryScreenState();
}

class _WeightHistoryScreenState extends State<WeightHistoryScreen> {
  String? _selectedPigId;

  // Define the looping accent colors
  final List<Color> _accentColors = const [
    Color(0xFFE57373), // Red
    Color(0xFF81C784), // Green
    Color(0xFF64B5F6), // Blue
    Color(0xFFFFB74D), // Orange
    Color(0xFFBA68C8), // Purple
  ];

  @override
  void initState() {
    super.initState();
    if (widget.availablePigs.isNotEmpty) {
      _selectedPigId = widget.availablePigs.first.pigId;
      // Trigger the cubit to load the first pig's history
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<WeightHistoryCubit>().loadHistoryForPig(_selectedPigId!);
      });
    }
  }

  // Helper to get color based on the pig's index in the list
  Color _getColorForPig(String pigId) {
    final index = widget.availablePigs.indexWhere((p) => p.pigId == pigId);
    if (index == -1) return Colors.grey;
    return _accentColors[index % _accentColors.length];
  }

  // Helper to format Date
  String _formatDate(DateTime date) {
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  Widget _buildDropdownFilter(bool isDark) {
    if (widget.availablePigs.isEmpty) return const SizedBox.shrink();

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedPigId,
        icon: const Icon(Icons.keyboard_arrow_down, size: 18, color: Color(0xFF2563EB)),
        style: const TextStyle(color: Color(0xFF2563EB), fontSize: 13, fontWeight: FontWeight.w600),
        dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        isDense: true,
        items: widget.availablePigs.map((pig) {
          return DropdownMenuItem(
            value: pig.pigId,
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    color: _getColorForPig(pig.pigId),
                    shape: BoxShape.circle,
                  ),
                ),
                Text(
                  '${pig.breed} | ${pig.displayId}', // Or however you want to display the name
                  style: const TextStyle(color: Color(0xFF2563EB), fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null && value != _selectedPigId) {
            setState(() => _selectedPigId = value);
            // Fetch new history when dropdown changes!
            context.read<WeightHistoryCubit>().loadHistoryForPig(value);
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final selectedColor = _selectedPigId != null ? _getColorForPig(_selectedPigId!) : Colors.grey;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppTopBar(title: 'Weight History', showBackButton: true),
              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerRight,
                child: _buildDropdownFilter(isDarkMode),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: BlocBuilder<WeightHistoryCubit, WeightHistoryState>(
                  builder: (context, state) {
                    if (state is WeightHistoryLoading || state is WeightHistoryInitial) {
                      return const Center(child: CircularProgressIndicator());
                    } else if (state is WeightHistoryError) {
                      return Center(child: Text(state.message, style: const TextStyle(color: Colors.red)));
                    } else if (state is WeightHistoryLoaded) {
                      final records = state.records;

                      if (records.isEmpty) {
                        return const Center(child: Text('No weight records found.'));
                      }

                      return ListView.builder(
                        itemCount: records.length,
                        itemBuilder: (context, index) {
                          final record = records[index];
                          return _buildWeightRecordCard(record, selectedColor, isDarkMode);
                        },
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWeightRecordCard(AppWeightRecord record, Color accentColor, bool isDarkMode) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final labelColor = isDarkMode ? Colors.white60 : Colors.black54;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDarkMode ? Colors.white10 : Colors.grey.shade300),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 10,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), bottomLeft: Radius.circular(12)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.notes.isNotEmpty ? record.notes : 'Weight Update',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: textColor),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(text: 'Date: ', style: TextStyle(fontSize: 13, color: labelColor)),
                                TextSpan(
                                  text: _formatDate(record.dateRecorded),
                                  style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(text: 'Weight: ', style: TextStyle(fontSize: 13, color: labelColor)),
                                TextSpan(
                                  text: '${record.weightKg} kg',
                                  style: TextStyle(fontSize: 13, color: textColor, fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}