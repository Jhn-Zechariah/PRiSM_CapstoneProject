import 'package:flutter/material.dart';

class FeedingHistoryPage extends StatefulWidget {
  const FeedingHistoryPage({super.key});

  @override
  State<FeedingHistoryPage> createState() => _FeedingHistoryPageState();
}

class _FeedingHistoryPageState extends State<FeedingHistoryPage> {
  // Currently selected filter option; defaults to 'All'
  String _selectedFilter = 'All';

  // Sample list of pigs with their display color and feeding record fields
  final List<Map<String, dynamic>> _pigs = [
    {
      "name": "Pig 1",
      "color": const Color.fromRGBO(214, 40, 40, 1), // Red
      "date": "",
      "time": "",
      "amountOfFeed": "",
      "feedType": "",
    },
    {
      "name": "Pig 2",
      "color": const Color.fromRGBO(0, 48, 73, 1), // Dark blue
      "date": "",
      "time": "",
      "amountOfFeed": "",
      "feedType": "",
    },
    {
      "name": "Pig 3",
      "color": const Color.fromRGBO(247, 127, 0, 1), // Orange
      "date": "",
      "time": "",
      "amountOfFeed": "",
      "feedType": "",
    },
  ];

  // Returns all pigs when filter is 'All', otherwise returns only the matched pig
  List<Map<String, dynamic>> get _filteredPigs {
    if (_selectedFilter == 'All') return _pigs;
    return _pigs.where((p) => p['name'] == _selectedFilter).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Detect current theme brightness for conditional styling
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── TopBar: back arrow + centered title + logo ────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back navigation button
                  IconButton(
                    icon: Icon(
                      Icons.arrow_back,
                      color: isDark ? Colors.white : Colors.black,
                      size: 28,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  // Page title centered between the back button and logo
                  Expanded(
                    child: Center(
                      child: Text(
                        'Feeding History',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : Colors.black,
                        ),
                      ),
                    ),
                  ),
                  // App logo — switches asset based on theme
                  Image.asset(
                    isDark ? 'assets/logo_dark.png' : 'assets/logo_light.png',
                    height: 40,
                    // Fallback icon if the asset is missing
                    errorBuilder: (context, error, stackTrace) => Icon(
                      Icons.business,
                      size: 40,
                      color: isDark ? Colors.white24 : Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Dropdown filter aligned to the right ──────────────────
              Align(
                alignment: Alignment.centerRight,
                child: _buildDropdownFilter(isDark),
              ),
              const SizedBox(height: 8),

              // ── Scrollable list of feeding history cards ──────────────
              Expanded(child: _buildFeedingHistoryList(isDark)),
            ],
          ),
        ),
      ),
    );
  }

  /// Builds the dropdown filter widget with 'All' plus one option per pig
  Widget _buildDropdownFilter(bool isDark) {
    // Prepend 'All' to the list of pig names for filter options
    final options = ['All', ..._pigs.map((p) => p['name'] as String)];

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
        // Dropdown background adapts to the current theme
        dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        isDense: true,
        items: options.map((option) {
          return DropdownMenuItem(
            value: option,
            child: Text(
              option,
              style: const TextStyle(
                color: Color(0xFF2563EB),
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          );
        }).toList(),
        // Update the selected filter and trigger a rebuild
        onChanged: (value) {
          if (value != null) setState(() => _selectedFilter = value);
        },
      ),
    );
  }

  /// Builds a scrollable ListView of filtered pig feeding history cards
  Widget _buildFeedingHistoryList(bool isDark) {
    return ListView.builder(
      itemCount: _filteredPigs.length,
      itemBuilder: (context, index) {
        final pig = _filteredPigs[index];
        return _buildHistoryCard(pig, isDark);
      },
    );
  }

  /// Builds a single history card for a given pig entry
  Widget _buildHistoryCard(Map<String, dynamic> pig, bool isDark) {
    final color = pig['color'] as Color;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Colored left accent strip unique to each pig
            Container(
              width: 10,
              decoration: BoxDecoration(
                color: color,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),

            // Main card content area
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pig name header
                    Text(
                      pig['name'] as String,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Row 1: Date and Time labels
                    Row(
                      children: [
                        Expanded(child: _buildLabel('Date:', isDark)),
                        Expanded(child: _buildLabel('Time:', isDark)),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Row 2: Amount of feed and Feed type labels
                    Row(
                      children: [
                        Expanded(
                            child: _buildLabel('Amount of feed:', isDark)),
                        Expanded(child: _buildLabel('Feed type:', isDark)),
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

  /// Builds a simple muted label text widget used inside history cards
  Widget _buildLabel(String label, bool isDark) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        color: isDark ? Colors.white60 : Colors.black54,
      ),
    );
  }
}