import 'package:flutter/material.dart';
import 'package:prism_app/features/auth/presentation/components/app_top_bar.dart';

// --- DATA MODELS --- //

class WeightRecord {
  final String pigId;
  final String date;
  final double weight;
  final Color accentColor;

  WeightRecord({
    required this.pigId,
    required this.date,
    required this.weight,
    required this.accentColor,
  });
}

class PigOption {
  final String id;
  final Color accentColor;

  PigOption({required this.id, required this.accentColor});
}

// --- SCREEN --- //

class WeightHistoryScreen extends StatefulWidget {
  final List<PigOption> pigs;
  final List<WeightRecord> weightRecords;
  final bool isLoading;

  const WeightHistoryScreen({
    super.key,
    required this.pigs,
    required this.weightRecords,
    this.isLoading = false,
  });

  @override
  State<WeightHistoryScreen> createState() => _WeightHistoryScreenState();
}

class _WeightHistoryScreenState extends State<WeightHistoryScreen> {
  String _selectedFilter = 'All';

  List<WeightRecord> get filteredRecords {
    if (_selectedFilter == 'All') return widget.weightRecords;
    return widget.weightRecords
        .where((r) => r.pigId == _selectedFilter)
        .toList();
  }

  Widget _buildDropdownFilter(bool isDark) {
    // 'All' + one entry per pig
    final options = ['All', ...widget.pigs.map((p) => p.id)];

    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedFilter,
        icon: const Icon(
          Icons.keyboard_arrow_down,
          size: 18,
          color: Color(0xFF2563EB),
        ),
        style: const TextStyle(
          color: Color(0xFF2563EB),
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        isDense: true,
        items: options.map((option) {
          // For 'All' just show 'All', for pig ids show the pig name
          final label = option == 'All'
              ? 'All'
              : widget.pigs.firstWhere((p) => p.id == option).id;

          return DropdownMenuItem(
            value: option,
            child: Row(
              children: [
                // Show color dot for pig options
                if (option != 'All') ...[
                  Container(
                    width: 8,
                    height: 8,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: widget.pigs
                          .firstWhere((p) => p.id == option)
                          .accentColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) setState(() => _selectedFilter = value);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTopBar(title: 'Weight History', showBackButton: true),
              const SizedBox(height: 12),

              // Dropdown filter aligned to the right
              Align(
                alignment: Alignment.centerRight,
                child: _buildDropdownFilter(isDarkMode),
              ),
              const SizedBox(height: 8),

              // Content
              Expanded(
                child: widget.isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filteredRecords.isEmpty
                    ? const Center(child: Text('No records found.'))
                    : ListView.builder(
                        itemCount: filteredRecords.length,
                        itemBuilder: (context, index) {
                          final record = filteredRecords[index];
                          return WeightRecordCard(
                            record: record,
                            isDarkMode: isDarkMode,
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- WEIGHT RECORD CARD --- //

class WeightRecordCard extends StatelessWidget {
  final WeightRecord record;
  final bool isDarkMode;

  const WeightRecordCard({
    super.key,
    required this.record,
    required this.isDarkMode,
  });

  @override
  Widget build(BuildContext context) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final labelColor = isDarkMode ? Colors.white60 : Colors.black54;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDarkMode ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left accent stripe
            Container(
              width: 10,
              decoration: BoxDecoration(
                color: record.accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),

            // Card content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.pigId,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: textColor,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Date: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: labelColor,
                                  ),
                                ),
                                TextSpan(
                                  text: record.date,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: textColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          child: RichText(
                            text: TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Weight: ',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: labelColor,
                                  ),
                                ),
                                TextSpan(
                                  text: '${record.weight} kg',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: textColor,
                                    fontWeight: FontWeight.w500,
                                  ),
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
