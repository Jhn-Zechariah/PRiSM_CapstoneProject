import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';

// --- Domain & State Layer Imports ---
import '../../../pig_management/domain/model/app_pig.dart';
import '../../domain/model/app_feeding_history.dart';
import '../cubits/feeding_history_cubit.dart';
import '../cubits/feeding_history_states.dart';

class FeedingHistoryPage extends StatefulWidget {
  final List<AppPig> availablePigs;

  const FeedingHistoryPage({super.key, required this.availablePigs});

  @override
  State<FeedingHistoryPage> createState() => _FeedingHistoryPageState();
}

class _FeedingHistoryPageState extends State<FeedingHistoryPage> {
  String? _selectedPigId =
      'All'; //  Set 'All' as the initial default string option
  String _currentFilter = 'Active';

  final List<Color> _accentColors = const [
    Color(0xFFE57373), // Red
    Color(0xFF81C784), // Green
    Color(0xFF64B5F6), // Blue
    Color(0xFFFFB74D), // Orange
    Color(0xFFBA68C8), // Purple
  ];

  List<AppPig> get _filteredPigs {
    return widget.availablePigs.where((pig) {
      final statusLower = pig.status.toLowerCase();
      final isInactive = statusLower == 'sold' || statusLower == 'deceased';

      if (_currentFilter == 'Active') {
        return !isInactive;
      } else {
        return isInactive;
      }
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadInitialPig();
  }

  void _loadInitialPig() {
    // 👈 Always reset selection back to 'All' when changing active/inactive tables
    setState(() {
      _selectedPigId = 'All';
    });
  }

  Color _getColorForPig(String pigId) {
    final index = widget.availablePigs.indexWhere((p) => p.pigId == pigId);
    if (index == -1) return Colors.grey;
    return _accentColors[index % _accentColors.length];
  }

  Widget _buildFiltersRow(bool isDark) {
    final displayPigs = _filteredPigs;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // LEFT SIDE: Active/Inactive Filter Dropdown
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

        // RIGHT SIDE: Specific Sub-Selection with "All" Option Included
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedPigId,
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
              // 👇 Explicitly inserting the global tracking item entry
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
                        '${pig.breed} | ${pig.displayId}',
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
              if (value != null && value != _selectedPigId) {
                setState(() => _selectedPigId = value);
              }
            },
          ),
        ),
      ],
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
              const AppTopBar(title: 'Feeding History', showBackButton: true),
              const SizedBox(height: 12),

              _buildFiltersRow(isDarkMode),
              const SizedBox(height: 8),

              Expanded(
                child: _filteredPigs.isEmpty
                    ? Center(
                        child: Text(
                          _currentFilter == 'Active'
                              ? 'No active pigs available.'
                              : 'No inactive pigs available.',
                          style: TextStyle(
                            color: isDarkMode ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      )
                    : BlocBuilder<FeedingHistoryCubit, FeedingHistoryState>(
                        builder: (context, state) {
                          if (state is FeedingHistoryLoading ||
                              state is FeedingHistoryInitial) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          } else if (state is FeedingHistoryError) {
                            return Center(
                              child: Text(
                                state.message,
                                style: const TextStyle(color: Colors.red),
                              ),
                            );
                          } else if (state is FeedingHistoryLoaded) {
                            // 1. Map pigs to access details efficiently
                            final pigMap = {
                              for (var p in widget.availablePigs) p.pigId: p,
                            };

                            // 2. Perform inline routing array modifications
                            final targetRecords = state.historyRecords.where((
                              record,
                            ) {
                              final associatedPig = pigMap[record.pigId];
                              if (associatedPig == null) return false;

                              // Verify record belongs to a pig matching the left-side filter context
                              final statusLower = associatedPig.status
                                  .toLowerCase();
                              final isPigInactive =
                                  statusLower == 'sold' ||
                                  statusLower == 'deceased';
                              final matchesStatus = _currentFilter == 'Active'
                                  ? !isPigInactive
                                  : isPigInactive;

                              if (!matchesStatus) return false;

                              // 👇 If 'All' is selected, display all records matching the status filter
                              if (_selectedPigId == 'All') return true;
                              return record.pigId == _selectedPigId;
                            }).toList();

                            if (targetRecords.isEmpty) {
                              return const Center(
                                child: Text('No feeding records found.'),
                              );
                            }

                            return ListView.builder(
                              itemCount: targetRecords.length,
                              itemBuilder: (context, index) {
                                final record = targetRecords[index];
                                final targetPig = pigMap[record.pigId];
                                final cardAccentColor = _getColorForPig(
                                  record.pigId,
                                );

                                return _buildFeedingRecordCard(
                                  record: record,
                                  pig: targetPig,
                                  accentColor: cardAccentColor,
                                  isDarkMode: isDarkMode,
                                );
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

  // ── Unified Card Structural Representation ─────────────────────
  Widget _buildFeedingRecordCard({
    required AppFeedingHistory record,
    required AppPig? pig,
    required Color accentColor,
    required bool isDarkMode,
  }) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final labelColor = isDarkMode ? Colors.white60 : Colors.black54;

    // 👇 Dynamically construct header values from parsed cross-reference
    final cardTitle = pig != null
        ? '${pig.breed} | ${pig.displayId}'
        : 'Unknown Pig';

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
            Container(
              width: 10,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cardTitle, // 👈 Dynamically populated string identifier
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
                          child: _buildRichLabel(
                            'Date:',
                            record.formattedDate,
                            labelColor,
                            textColor,
                          ),
                        ),
                        Expanded(
                          child: _buildRichLabel(
                            'Time:',
                            record.formattedTime,
                            labelColor,
                            textColor,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Removed the extra "kg" suffix from Feed type
                        Expanded(
                          child: _buildRichLabel(
                            'Feed type:',
                            record.feedType,
                            labelColor,
                            textColor,
                          ),
                        ),
                        Expanded(
                          child: _buildRichLabel(
                            'Amount:',
                            '${record.amount} kg',
                            labelColor,
                            textColor,
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

  Widget _buildRichLabel(
    String label,
    String value,
    Color labelColor,
    Color textColor,
  ) {
    return RichText(
      overflow: TextOverflow.ellipsis,
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(fontSize: 13, color: labelColor),
          ),
          TextSpan(
            text: value.isNotEmpty ? value : 'N/A',
            style: TextStyle(
              fontSize: 13,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
