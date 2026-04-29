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
          const SizedBox(height: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderRow(isDarkMode),
                const SizedBox(height: 4),
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
        // Matches _buildTitle() in Temperaturemonitoring exactly
        Row(
          children: [
            Icon(
              Symbols.yoshoku,
              size: 32, // ← matched to thermostat size: 32
              color: isDark ? Colors.white : Colors.black,
            ),
            const SizedBox(width: 12), // ← matched to SizedBox(width: 12)
            Text(
              'Feeding Records',
              style: TextStyle(
                fontSize: 24, // ← matched to fontSize: 24
                fontWeight: FontWeight.w900, // ← matched to FontWeight.w900
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.add),
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
      child: GestureDetector(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FeedingHistoryPage()),
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
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
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
                padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
            GestureDetector(
              onTap: () {
                setState(() {
                  _expandedIndex = isExpanded ? -1 : index;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
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
