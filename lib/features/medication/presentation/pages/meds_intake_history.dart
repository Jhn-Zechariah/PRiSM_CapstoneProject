import 'package:flutter/material.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';

class PigMedOption {
  final String id;

  final Color accentColor;

  PigMedOption({required this.id, required this.accentColor});
}

class MedsIntakeHistoryScreen extends StatefulWidget {
  final List<PigMedOption> pigs;

  const MedsIntakeHistoryScreen({super.key, required this.pigs});

  @override
  State<MedsIntakeHistoryScreen> createState() =>
      _MedsIntakeHistoryScreenState();
}

class _MedsIntakeHistoryScreenState extends State<MedsIntakeHistoryScreen> {
  String _selectedFilter = 'All';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = ['All', ...widget.pigs.map((p) => p.id)];
    final filteredPigs = _selectedFilter == 'All'
        ? widget.pigs
        : widget.pigs.where((p) => p.id == _selectedFilter).toList();

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppTopBar(title: 'Medicine History', showBackButton: true),
              const SizedBox(height: 12),

              // Dropdown filter
              Align(
                alignment: Alignment.centerRight,
                child: DropdownButtonHideUnderline(
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
                    dropdownColor: isDark
                        ? const Color(0xFF2C2C2C)
                        : Colors.white,
                    isDense: true,
                    items: options.map((option) {
                      final label = option == 'All'
                          ? 'All'
                          : widget.pigs.firstWhere((p) => p.id == option).id;
                      final pig = option == 'All'
                          ? null
                          : widget.pigs.firstWhere((p) => p.id == option);
                      return DropdownMenuItem(
                        value: option,
                        child: Row(
                          children: [
                            if (pig != null)
                              Container(
                                width: 8,
                                height: 8,
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: pig.accentColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
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
                      if (value != null) {
                        setState(() => _selectedFilter = value);
                      }
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // History cards
              Expanded(
                child: filteredPigs.isEmpty
                    ? const Center(child: Text('No records found.'))
                    : ListView.builder(
                        itemCount: filteredPigs.length,
                        itemBuilder: (context, index) {
                          final pig = filteredPigs[index];
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? const Color(0xFF2C2C2C)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white10
                                    : Colors.grey.shade300,
                              ),
                            ),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    width: 10,
                                    decoration: BoxDecoration(
                                      color: pig.accentColor,
                                      borderRadius: const BorderRadius.only(
                                        topLeft: Radius.circular(12),
                                        bottomLeft: Radius.circular(12),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        14,
                                        14,
                                        14,
                                        14,
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            pig.id,
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                              color: isDark
                                                  ? Colors.white
                                                  : Colors.black,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Date:',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: isDark
                                                        ? Colors.white60
                                                        : Colors.black54,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  'Medicine:',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: isDark
                                                        ? Colors.white60
                                                        : Colors.black54,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 6),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  'Dosage:',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: isDark
                                                        ? Colors.white60
                                                        : Colors.black54,
                                                  ),
                                                ),
                                              ),
                                              Expanded(
                                                child: Text(
                                                  'Notes:',
                                                  style: TextStyle(
                                                    fontSize: 13,
                                                    color: isDark
                                                        ? Colors.white60
                                                        : Colors.black54,
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
