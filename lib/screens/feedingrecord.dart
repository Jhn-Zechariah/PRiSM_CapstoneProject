import 'package:flutter/material.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'selectpigfeedpopup.dart';
import 'selectpigfeedpopup2.dart';
import 'feedinghistory.dart';
import 'extendedfeedingrecord.dart';

class FeedingRecordsPage extends StatefulWidget {
  const FeedingRecordsPage({super.key});

  @override
  State<FeedingRecordsPage> createState() => _FeedingRecordsPageState();
}

class _FeedingRecordsPageState extends State<FeedingRecordsPage> {
  int _expandedIndex = -1;

  final List<Map<String, dynamic>> _pigs = [
    {"name": "Pig 1", "color": const Color.fromRGBO(214, 40, 40, 1)},
    {"name": "Pig 2", "color": const Color.fromRGBO(0, 48, 73, 1)},
    {"name": "Pig 3", "color": const Color.fromRGBO(247, 127, 0, 1)},
  ];

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTopBar(),
          const SizedBox(height: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderRow(isDarkMode),
                _buildViewHistoryLink(),
                const SizedBox(height: 12),
                Expanded(child: _buildFeedingList(isDarkMode)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Icon(
              Symbols.yoshoku,
              size: 32,
              color: isDark ? Colors.white : Colors.black,
            ),
            const SizedBox(width: 12),
            Text(
              'Feeding Records',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.add, size: 28),
          color: isDark ? Colors.white : Colors.black,
          onPressed: () {
            showDialog(
              context: context,
              builder: (_) => SelectPigFeedPopup(
                pigs: _pigs,
                pigColor: const Color.fromRGBO(214, 40, 40, 1),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildViewHistoryLink() {
    return Align(
      alignment: Alignment.centerRight,
      child: TextButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FeedingHistoryPage()),
          );
        },
        style: TextButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: const Size(0, 30),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: const Text(
          'View feeding history',
          style: TextStyle(
            color: Color(0xFF3B82F6), // Matches the blue in your reference
            fontSize: 14,
            fontWeight: FontWeight.w600, // Matches the semi-bold look
          ),
        ),
      ),
    );
  }

  Widget _buildFeedingList(bool isDark) {
    return ListView.builder(
      itemCount: _pigs.length,
      itemBuilder: (context, index) {
        final pig = _pigs[index];
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
        // Changed border to slightly darker to match your UI image better
        border: Border.all(color: isDark ? Colors.white10 : Colors.black54),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
            Expanded(
              child: Padding(
                // Even padding ensures icons on the right edge align nicely
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // TOP ROW: Title + (+ or down arrow)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          name,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 18,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
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
                              size: 26,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          )
                        else
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _expandedIndex = index;
                              });
                            },
                            child: Icon(
                              Icons.keyboard_arrow_down,
                              size: 28,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                      ],
                    ),

                    // EXPANDED CONTENT: Preview + (up arrow at the bottom right)
                    if (isExpanded) ...[
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: FeedingRecordExpandedPreview(
                              pigName: name,
                              pigColor: color,
                            ),
                          ),
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _expandedIndex = -1;
                              });
                            },
                            child: Icon(
                              Icons.keyboard_arrow_up,
                              size: 28,
                              color: isDark ? Colors.white : Colors.black,
                            ),
                          ),
                        ],
                      ),
                    ],
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
