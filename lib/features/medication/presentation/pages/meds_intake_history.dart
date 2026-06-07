import 'package:flutter/material.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';

class PigMedOption {
  final String id;
  final String status; // 🔹 Added status to determine Active/Inactive
  final Color accentColor;

  PigMedOption({
    required this.id,
    required this.status, // 🔹 Required here now
    required this.accentColor,
  });
}

class MedsIntakeHistoryScreen extends StatefulWidget {
  final List<PigMedOption> pigs;

  const MedsIntakeHistoryScreen({super.key, required this.pigs});

  @override
  State<MedsIntakeHistoryScreen> createState() =>
      _MedsIntakeHistoryScreenState();
}

class _MedsIntakeHistoryScreenState extends State<MedsIntakeHistoryScreen> {
  String _selectedFilter = 'All'; // Specific Pig ID or 'All'
  String _currentFilter = 'Active'; // Active or Inactive status

  // 🔹 1. Filter by Status (Active/Inactive)
  List<PigMedOption> get _filteredPigsByStatus {
    return widget.pigs.where((pig) {
      final statusLower = pig.status.toLowerCase();
      final isInactive = statusLower == 'sold' || statusLower == 'deceased';

      if (_currentFilter == 'Active') {
        return !isInactive;
      } else {
        return isInactive;
      }
    }).toList();
  }

  void _loadInitialPig() {
    // Reset the specific pig dropdown when changing Active/Inactive
    setState(() {
      _selectedFilter = 'All';
    });
  }

  Widget _buildFiltersRow(bool isDark) {
    final displayPigs = _filteredPigsByStatus;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 🔹 LEFT SIDE: Active/Inactive Filter Dropdown
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _currentFilter,
            icon: Icon(
              Icons.filter_list,
              size: 18,
              color: isDark ? Colors.white : Colors.black87,
            ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
            dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            items: const [
              DropdownMenuItem(value: 'Active', child: Text('Active Pigs')),
              DropdownMenuItem(value: 'Inactive', child: Text('Inactive Pigs')),
            ],
            onChanged: (value) {
              if (value != null && value != _currentFilter) {
                setState(() {
                  _currentFilter = value;
                  _loadInitialPig();
                });
              }
            },
          ),
        ),

        // 🔹 RIGHT SIDE: Specific Sub-Selection with "All" Option Included
        DropdownButtonHideUnderline(
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
            items: [
              const DropdownMenuItem<String>(
                value: 'All',
                child: Text(
                  'All Pigs',
                  style: TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ...displayPigs.map((pig) {
                return DropdownMenuItem(
                  value: pig.id,
                  child: Row(
                    children: [
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
                        pig.id,
                        style: const TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            onChanged: (value) {
              if (value != null && value != _selectedFilter) {
                setState(() => _selectedFilter = value);
              }
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 🔹 2. Final filter applying BOTH dropdowns
    final targetRecords = _filteredPigsByStatus.where((p) {
      if (_selectedFilter == 'All') return true;
      return p.id == _selectedFilter;
    }).toList();

    return Scaffold(
      backgroundColor:
      isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppTopBar(title: 'Medicine History', showBackButton: true),
              const SizedBox(height: 12),

              // Filter Row
              _buildFiltersRow(isDark),
              const SizedBox(height: 8),

              // History cards
              Expanded(
                child: targetRecords.isEmpty
                    ? Center(
                  child: Text(
                    _currentFilter == 'Active'
                        ? 'No active records found.'
                        : 'No inactive records found.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                )
                    : ListView.builder(
                  itemCount: targetRecords.length,
                  itemBuilder: (context, index) {
                    final pig = targetRecords[index];
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
                                            'Medicine:',
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
                                            'Dosage:',
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
                                    const SizedBox(height: 6),
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