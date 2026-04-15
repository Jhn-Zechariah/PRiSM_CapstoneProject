import 'package:flutter/material.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';

class PigProfiles extends StatefulWidget {
  final VoidCallback onThemeToggle;

  const PigProfiles({super.key, required this.onThemeToggle});

  @override
  State<PigProfiles> createState() => _PigProfilesState();
}

class _PigProfilesState extends State<PigProfiles> {
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
                const SizedBox(height: 12),
                Expanded(child: _buildPigList(isDarkMode)),
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
              Symbols.savings,
              size: 28,
              color: isDark ? Colors.white : Colors.black,
            ),
            const SizedBox(width: 8),
            Text(
              'Pig Profiles',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.add),
          color: isDark ? Colors.white : Colors.black,
          onPressed: () {
            // add pig logic here
          },
        ),
      ],
    );
  }

  Widget _buildPigList(bool isDark) {
    final pigs = [
      {"name": "Pig 1", "color": const Color.fromRGBO(214, 40, 40, 1)},
      {"name": "Pig 2", "color": const Color.fromRGBO(0, 48, 73, 1)},
      {"name": "Pig 3", "color": const Color.fromRGBO(247, 127, 0, 1)},
    ];

    return ListView.builder(
      itemCount: pigs.length,
      itemBuilder: (context, index) {
        final pig = pigs[index];
        return _buildPigCard(
          name: pig["name"] as String,
          color: pig["color"] as Color,
          isDark: isDark,
        );
      },
    );
  }

  Widget _buildPigCard({
    required String name,
    required Color color,
    required bool isDark,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 140,
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
              padding: const EdgeInsets.all(12),
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
                      const Icon(Icons.more_vert, size: 18),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    "Breed:",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
                  Text(
                    "Sex:",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
                  Text(
                    "Age:",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
                  Text(
                    "Current weight:",
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white60 : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[800] : Colors.grey[200],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      "NOTE:",
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}