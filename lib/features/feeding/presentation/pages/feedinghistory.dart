import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';

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
  String _selectedPigId = 'All';
  String _currentFilter = 'Active';

  final ScrollController _scrollController = ScrollController();
  String? _currentUserId;

  // Memoised so _filteredPigs isn't recomputed on every rebuild.
  List<AppPig>? _cachedFilteredPigs;
  String? _lastFilter;

  static const _accentColors = [
    Color(0xFFE57373),
    Color(0xFF81C784),
    Color(0xFF64B5F6),
    Color(0xFFFFB74D),
    Color(0xFFBA68C8),
  ];

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _currentUserId = FirebaseAuth.instance.currentUser?.uid;
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Returns the pigs matching [_currentFilter], memoised until the filter
  /// value changes so we don't re-scan the pig list on every frame.
  List<AppPig> get _filteredPigs {
    if (_cachedFilteredPigs == null || _lastFilter != _currentFilter) {
      _lastFilter = _currentFilter;
      _cachedFilteredPigs = widget.availablePigs.where((pig) {
        final statusLower = pig.status.toLowerCase();
        final isInactive =
            statusLower == 'sold' || statusLower == 'deceased';
        return _currentFilter == 'Active' ? !isInactive : isInactive;
      }).toList();
    }
    return _cachedFilteredPigs!;
  }

  Color _colorForPig(String pigId) {
    final index = widget.availablePigs.indexWhere((p) => p.pigId == pigId);
    if (index == -1) return Colors.grey;
    return _accentColors[index % _accentColors.length];
  }

  // ── Scroll listener ────────────────────────────────────────────────────────

  void _onScroll() {
    if (!mounted) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      final userId = _currentUserId;
      if (userId == null) return;
      context.read<FeedingHistoryCubit>().loadMoreHistory(userId);
    }
  }

  // ── Filter bar ─────────────────────────────────────────────────────────────

  Widget _buildFiltersRow(bool isDark) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final dropBg = isDark ? const Color(0xFF2C2C2C) : Colors.white;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Active / Inactive filter
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _currentFilter,
            icon: Icon(Icons.filter_list, size: 18, color: textColor),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textColor,
            ),
            dropdownColor: dropBg,
            items: const [
              DropdownMenuItem(value: 'Active', child: Text('Current Pigs')),
              DropdownMenuItem(
                  value: 'Inactive', child: Text('Removed Pigs')),
            ],
            onChanged: (value) {
              if (value != null && value != _currentFilter) {
                setState(() {
                  _currentFilter = value;
                  _cachedFilteredPigs = null; // bust memo
                  _selectedPigId = 'All';
                });
              }
            },
          ),
        ),

        // Pig picker
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
            dropdownColor: dropBg,
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
              ..._filteredPigs.map((pig) {
                final color = _colorForPig(pig.pigId);
                return DropdownMenuItem<String>(
                  value: pig.pigId,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: color,
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppTopBar(title: 'Feeding History', showBackButton: true),
              const SizedBox(height: 12),
              _buildFiltersRow(isDark),
              const SizedBox(height: 8),
              Expanded(
                child: _filteredPigs.isEmpty
                    ? Center(
                  child: Text(
                    _currentFilter == 'Active'
                        ? 'No active pigs available.'
                        : 'No inactive pigs available.',
                    style: TextStyle(
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
                )
                    : BlocBuilder<FeedingHistoryCubit, FeedingHistoryState>(
                  // Only rebuild on transitions that change visible content.
                  buildWhen: (prev, curr) =>
                  curr is FeedingHistoryLoading ||
                      curr is FeedingHistoryInitial ||
                      curr is FeedingHistoryLoaded ||
                      curr is FeedingHistoryLoadingMore ||
                      curr is FeedingHistoryError,
                  builder: (context, state) {
                    if (state is FeedingHistoryLoading ||
                        state is FeedingHistoryInitial) {
                      return const Center(
                          child: CircularProgressIndicator());
                    }

                    if (state is FeedingHistoryError) {
                      return Center(
                        child: Text(
                          state.message,
                          style: const TextStyle(color: Colors.red),
                        ),
                      );
                    }

                    List<AppFeedingHistory> records = [];
                    bool hasMore = false;
                    bool isLoadingMore = false;

                    if (state is FeedingHistoryLoaded) {
                      records = state.historyRecords;
                      hasMore = state.hasMore;
                    } else if (state is FeedingHistoryLoadingMore) {
                      records = state.currentRecords;
                      isLoadingMore = true;
                    }

                    if (records.isEmpty) {
                      return const Center(
                          child: Text('No feeding records found.'));
                    }

                    final pigMap = {
                      for (final p in widget.availablePigs)
                        p.pigId: p,
                    };

                    // Filter records by active/inactive status and
                    // selected pig, then sort latest-first by timestamp.
                    final targetRecords = records
                        .where((record) {
                      final pig = pigMap[record.pigId];
                      if (pig == null) return false;

                      final statusLower =
                      pig.status.toLowerCase();
                      final isInactive = statusLower == 'sold' ||
                          statusLower == 'deceased';
                      final matchesStatus =
                      _currentFilter == 'Active'
                          ? !isInactive
                          : isInactive;

                      if (!matchesStatus) return false;
                      if (_selectedPigId == 'All') return true;
                      return record.pigId == _selectedPigId;
                    })
                        .toList()
                    // Guarantee latest-first even after client-side
                    // filter narrows a merged multi-pig result set.
                      ..sort((a, b) =>
                          b.timestamp.compareTo(a.timestamp));

                    if (targetRecords.isEmpty) {
                      return const Center(
                          child: Text('No feeding records found.'));
                    }

                    // Only show the trailing spinner when there are
                    // records AND more pages exist (or a load is
                    // active). Without the non-empty guard, the spinner
                    // persists when the current filter has no matching
                    // records but Firestore has records on other pigs.
                    final showTrailingSpinner =
                        (isLoadingMore || hasMore) &&
                            targetRecords.isNotEmpty;
                    final itemCount = showTrailingSpinner
                        ? targetRecords.length + 1
                        : targetRecords.length;

                    return ListView.builder(
                      controller: _scrollController,
                      itemCount: itemCount,
                      itemBuilder: (context, index) {
                        if (index == targetRecords.length) {
                          return const Padding(
                            padding:
                            EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                                child: CircularProgressIndicator()),
                          );
                        }

                        final record = targetRecords[index];
                        return _buildFeedingRecordCard(
                          record: record,
                          pig: pigMap[record.pigId],
                          accentColor: _colorForPig(record.pigId),
                          isDarkMode: isDark,
                        );
                      },
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

  // ── Cards ──────────────────────────────────────────────────────────────────

  Widget _buildFeedingRecordCard({
    required AppFeedingHistory record,
    required AppPig? pig,
    required Color accentColor,
    required bool isDarkMode,
  }) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final labelColor = isDarkMode ? Colors.white60 : Colors.black54;
    final cardTitle =
    pig != null ? '${pig.breed} | ${pig.displayId}' : 'Unknown Pig';

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
            // Colour accent strip
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
                      cardTitle,
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
                          child: _buildRichLabel('Date:', record.formattedDate,
                              labelColor, textColor),
                        ),
                        Expanded(
                          child: _buildRichLabel('Time:', record.formattedTime,
                              labelColor, textColor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(
                          child: _buildRichLabel('Feed type:', record.feedType,
                              labelColor, textColor),
                        ),
                        Expanded(
                          child: _buildRichLabel('Amount:',
                              '${record.amount} kg', labelColor, textColor),
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