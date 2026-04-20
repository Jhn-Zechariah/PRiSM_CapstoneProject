import 'package:flutter/material.dart';
import 'package:prism_app/screens/add_pig.dart';
import 'app_top_bar.dart';
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppTopBar(isDark: isDarkMode),
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
    );
  }

  //build header row; title and icon
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
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    AddPig(onThemeToggle: widget.onThemeToggle),
              ),
            );
          },
        ),
      ],
    );
  }

  //build list of pigs
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

  //pig card widget
  Widget _buildPigCard({
    required String name,
    required Color color,
    required bool isDark,
  }) {
    return IntrinsicHeight(
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          // This is the key: it forces the children (the color bar)
          // to stretch to the height of the tallest child (the content Column).
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // --- LEFT COLOR BAR ---
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

            // --- CONTENT SECTION ---
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // TITLE & MENU ICON
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
                        Icon(
                          Icons.more_vert,
                          size: 18,
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ],
                    ),

                    const SizedBox(height: 6),

                    // PIG DETAILS
                    _buildDetailText("Breed:", isDark),
                    _buildDetailText("Sex:", isDark),
                    _buildDetailText("Age:", isDark),
                    _buildDetailText("Current weight:", isDark),

                    const SizedBox(height: 8),

                    // NOTE BOX (This determines the overall card height)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "NOTE: ",
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
      ),
    );
  }

  // Helper widget to keep the main card code clean
  Widget _buildDetailText(String label, bool isDark) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        color: isDark ? Colors.white60 : Colors.grey,
      ),
    );
  }
}
