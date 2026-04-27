import 'package:flutter/material.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'selectpigfeedpopup.dart';   // Multi-pig feed popup (+ button in header)
import 'selectpigfeedpopup2.dart';  // Single pig feed popup (+ button in expanded card)
import 'feedinghistory.dart';        // Feeding history page
import 'extendedfeedingrecord.dart'; // Expanded preview widget for individual pig cards

class FeedingRecordsPage extends StatefulWidget {
  const FeedingRecordsPage({super.key});

  @override
  State<FeedingRecordsPage> createState() => _FeedingRecordsPageState();
}

class _FeedingRecordsPageState extends State<FeedingRecordsPage> {
  // Tracks which pig card is currently expanded; -1 means none are expanded
  int _expandedIndex = -1;

  // List of pigs with their display name and accent color
  final List<Map<String, dynamic>> _pigs = [
    {"name": "Pig 1", "color": const Color.fromRGBO(214, 40, 40, 1)},  // Red
    {"name": "Pig 2", "color": const Color.fromRGBO(0, 48, 73, 1)},    // Dark blue
    {"name": "Pig 3", "color": const Color.fromRGBO(247, 127, 0, 1)},  // Orange
  ];

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Shared top bar with logo and navigation controls
          AppTopBar(),
          const SizedBox(height: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Page title with icon and the global + button
                _buildHeaderRow(isDarkMode),
                const SizedBox(height: 4),

                // "View feeding history" link aligned to the right
                _buildViewHistoryLink(),
                const SizedBox(height: 12),

                // Scrollable list of pig feeding record cards
                Expanded(child: _buildFeedingList(isDarkMode)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Builds the page header row containing the title icon, "Feeding Records"
  /// text, and the global add (+) button that opens [SelectPigFeedPopup]
  Widget _buildHeaderRow(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Left side: food icon + page title
        Row(
          children: [
            Icon(
              Symbols.yoshoku,
              size: 28,
              color: isDark ? Colors.white : Colors.black,
            ),
            const SizedBox(width: 8),
            Text(
              'Feeding Records',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),

        // Right side: global add button — opens multi-pig feed popup
        IconButton(
          icon: const Icon(Icons.add),
          color: isDark ? Colors.white : Colors.black,
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => SelectPigFeedPopup(
                pigs: _pigs,
                // Uses Pig 1's color as the default dialog accent strip
                pigColor: const Color.fromRGBO(214, 40, 40, 1),
              ),
            );
          },
        ),
      ],
    );
  }

  /// Builds the "View feeding history" tappable link that navigates
  /// to [FeedingHistoryPage]
  Widget _buildViewHistoryLink() {
    return Align(
      alignment: Alignment.centerRight,
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FeedingHistoryPage(),
            ),
          );
        },
        child: const Text(
          'View feeding history',
          style: TextStyle(
            color: Color(0xFF2563EB),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  /// Builds the scrollable ListView of pig feeding record cards
  Widget _buildFeedingList(bool isDark) {
    return ListView.builder(
      itemCount: _pigs.length,
      itemBuilder: (context, index) {
        final pig = _pigs[index];

        // Determine if this card is the currently expanded one
        final isExpanded = _expandedIndex == index;

        return _buildFeedingCard(
          index: index,
          name: pig["name"],
          color: pig["color"],
          isDark: isDark,
          isExpanded: isExpanded,
        );
      },
    );
  }

  /// Builds a single collapsible feeding record card for a pig.
  /// Tapping the chevron toggles expansion; when expanded, shows
  /// [FeedingRecordExpandedPreview] and a per-pig add (+) button.
  Widget _buildFeedingCard({
    required int index,
    required String name,
    required Color color,
    required bool isDark,
    required bool isExpanded,
  }) {
    return Container(
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

            // ── Left colored accent strip unique to each pig ──────────────
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

            // ── Main card content ─────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Card header: pig name + conditional add button ─────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),

                        // Add button only visible when the card is expanded;
                        // opens SelectPigFeedPopup2 for this specific pig
                        if (isExpanded)
                          GestureDetector(
                            onTap: () {
                              showDialog(
                                context: context,
                                builder: (_) => SelectPigFeedPopup2(
                                  pigName: name,
                                  pigColor: color,
                                ),
                              );
                            },
                            child: Icon(
                              Icons.add,
                              size: 22,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                      ],
                    ),

                    // ── Expanded preview — only rendered when card is open ─
                    // Connects to FeedingRecordExpandedPreview in extendedfeedingrecord.dart
                    if (isExpanded) ...[
                      const SizedBox(height: 12),
                      FeedingRecordExpandedPreview(
                        pigName: name,
                        pigColor: color,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Chevron toggle button ─────────────────────────────────────
            // Tap toggles expansion: sets _expandedIndex to this index,
            // or collapses it back to -1 if already expanded
            GestureDetector(
              onTap: () {
                setState(() {
                  _expandedIndex = isExpanded ? -1 : index;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                // Animates the chevron 180° when the card expands/collapses
                child: AnimatedRotation(
                  turns: isExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: isDark ? Colors.white60 : Colors.black54,
                    size: 24,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}