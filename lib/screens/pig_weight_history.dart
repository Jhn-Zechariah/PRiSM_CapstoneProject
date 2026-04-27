import 'package:flutter/material.dart';
import 'package:prism_app/features/auth/presentation/components/app_top_bar.dart';

// --- DATA MODELS --- //

class WeightRecord {
  final String pigId;
  final String pigName;
  final String date;
  final double weight;
  final Color accentColor;

  WeightRecord({
    required this.pigId,
    required this.pigName,
    required this.date,
    required this.weight,
    required this.accentColor,
  });
}

class PigOption {
  final String id;
  final String name;
  final Color accentColor;

  PigOption({required this.id, required this.name, required this.accentColor});
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
  String? selectedPigId;

  List<WeightRecord> get filteredRecords => selectedPigId == null
      ? widget.weightRecords
      : widget.weightRecords.where((r) => r.pigId == selectedPigId).toList();

  PigOption? get selectedPig => selectedPigId == null
      ? null
      : widget.pigs.firstWhere((p) => p.id == selectedPigId);

  Widget _buildChip({
    required String label,
    required bool isSelected,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF3B82F6) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? const Color(0xFF3B82F6) : Colors.grey.shade400,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected ? Colors.white : Colors.grey,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 2), trailing],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isPigSelected = selectedPigId != null;

    return Scaffold(
      backgroundColor: isDarkMode
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: AppTopBar(title: 'Weight History', showBackButton: true),
            ),
            const SizedBox(height: 8),

            // Filter Row
            Padding(
              padding: const EdgeInsets.only(right: 16, top: 4, bottom: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // ALL chip
                  _buildChip(
                    label: 'All',
                    isSelected: !isPigSelected,
                    onTap: () => setState(() => selectedPigId = null),
                  ),

                  // PIG chip with popup
                  widget.pigs.isEmpty
                      ? const SizedBox.shrink()
                      : PopupMenuButton<String>(
                          onSelected: (pigId) =>
                              setState(() => selectedPigId = pigId),
                          offset: const Offset(0, 30),
                          itemBuilder: (_) => widget.pigs
                              .map(
                                (pig) => PopupMenuItem<String>(
                                  value: pig.id,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 10,
                                        height: 10,
                                        margin: const EdgeInsets.only(right: 8),
                                        decoration: BoxDecoration(
                                          color: pig.accentColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Text(pig.name),
                                    ],
                                  ),
                                ),
                              )
                              .toList(),
                          child: _buildChip(
                            label: selectedPig?.name ?? 'Pig',
                            isSelected: isPigSelected,
                            trailing: Icon(
                              Icons.arrow_drop_down,
                              size: 16,
                              color: isPigSelected ? Colors.white : Colors.grey,
                            ),
                          ),
                        ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: widget.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filteredRecords.isEmpty
                  ? const Center(child: Text('No records found.'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      itemCount: filteredRecords.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
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
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 10, color: record.accentColor),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.pigName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Date: ',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: labelColor,
                                    ),
                                  ),
                                  TextSpan(
                                    text: record.date,
                                    style: TextStyle(
                                      fontSize: 12,
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
                                      fontSize: 12,
                                      color: labelColor,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '${record.weight} kg',
                                    style: TextStyle(
                                      fontSize: 12,
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
      ),
    );
  }
}
