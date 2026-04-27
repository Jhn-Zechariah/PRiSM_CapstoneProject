import 'package:flutter/material.dart';
import '../features/auth/presentation/components/app_top_bar.dart';
import 'add_pig.dart';
import 'package:prism_app/screens/update_pig_weight_dialog.dart';
import 'pig_weight_history.dart';

// // Inside your ListView.builder for the profile cards:
// final colors = [Colors.red, const Color(0xFF003366), Colors.orange];
// final assignedColor = colors[index % colors.length]; // Loops through the colors perfectly!

// --- ENUMS & DATA MODELS --- //

// Enum for the 3-dot menu actions
enum PigMenuAction { info, updateWeight }

// Data model to easily generate the list
class PigProfileData {
  final String name;
  final String breed;
  final String age;
  final String sex;
  final String weight;
  final String note;
  final Color accentColor;

  PigProfileData({
    required this.name,
    required this.breed,
    required this.age,
    required this.sex,
    required this.weight,
    required this.note,
    required this.accentColor,
  });
}

// --- MAIN SCREEN --- //

class PigProfilesScreen extends StatefulWidget {
  const PigProfilesScreen({super.key});

  @override
  State<PigProfilesScreen> createState() => _PigProfilesScreenState();
}

class _PigProfilesScreenState extends State<PigProfilesScreen> {
  // Dummy data based on your screenshot
  final List<PigProfileData> profiles = [
    PigProfileData(
      name: 'Pig 1',
      breed: '',
      age: '',
      sex: '',
      weight: '',
      note: '',
      accentColor: Colors.red,
    ),
    PigProfileData(
      name: 'Pig 2',
      breed: '',
      age: '',
      sex: '',
      weight: '',
      note: '',
      accentColor: const Color(0xFF003366), // Dark Blue
    ),
    PigProfileData(
      name: 'Pig 3',
      breed: '',
      age: '',
      sex: '',
      weight: '',
      note: '',
      accentColor: Colors.orange,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Your Custom App Bar
          const AppTopBar(),
          const SizedBox(height: 16),

          // Header Row
          Row(
            children: [
              //  Replace Icon with SvgPicture.asset if using your custom pig icon
              const Icon(Icons.savings_outlined, size: 32),
              const SizedBox(width: 12),
              const Text(
                'Pig Profiles',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 28),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PigInformationScreen(),
                    ),
                  );
                },
              ),
            ],
          ),

          // View Weight History Link
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => WeightHistoryScreen(
                      pigs: profiles
                          .map(
                            (p) => PigOption(
                              id: p
                                  .name, // your pig's database ID; dummying with name for now
                              name: p.name,
                              accentColor: p.accentColor,
                            ),
                          )
                          .toList(),
                      weightRecords:
                          const [], //empty for now, will be fetched in the WeightHistoryScreen
                      isLoading: false,
                    ),
                  ),
                );
              },
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text(
                'View weight history',
                style: TextStyle(
                  color: Color(0xFF3B82F6),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // List of Profile Cards
          Expanded(
            child: ListView.separated(
              itemCount: profiles.length,
              separatorBuilder: (context, index) => const SizedBox(height: 16),
              itemBuilder: (context, index) {
                return PigProfileCard(
                  data: profiles[index],
                  isDarkMode: isDarkMode,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// --- REUSABLE CARD COMPONENT --- //

class PigProfileCard extends StatelessWidget {
  final PigProfileData data;
  final bool isDarkMode;

  const PigProfileCard({
    super.key,
    required this.data,
    required this.isDarkMode,
  });

  void _handleMenuAction(BuildContext context, PigMenuAction action) {
    switch (action) {
      case PigMenuAction.info:
        // Navigate to your PigInformationScreen
        // Navigator.push(context, MaterialPageRoute(builder: (_) => const PigInformationScreen()));
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Navigating to Info...')));
        break;

      //pop up a dialog to update weight
      case PigMenuAction.updateWeight:
        // Open weight update modal or screen
        showDialog<double>(
          context: context,
          builder: (_) => UpdatePigWeightDialog(
            pigLabel: data.name,
            currentWeight: double.tryParse(data.weight) ?? 0.0,
            accentColor: data.accentColor, // passes the pig's color
          ),
        ).then((newWeight) {
          if (newWeight != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('${data.name} weight updated to $newWeight kg'),
                backgroundColor: data.accentColor,
              ),
            );
          }
        });
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final labelColor = isDarkMode ? Colors.white70 : Colors.black54;

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 6, offset: Offset(0, 3)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left Accent Stripe
              Container(width: 12, color: data.accentColor),

              // Card Content
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(
                    left: 12,
                    top: 12,
                    bottom: 16,
                    right: 4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Title and 3-Dot Menu
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            data.name,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                          SizedBox(
                            height: 24,
                            width: 24,
                            child: PopupMenuButton<PigMenuAction>(
                              padding: EdgeInsets.zero,
                              icon: Icon(Icons.more_vert, color: textColor),
                              onSelected: (action) =>
                                  _handleMenuAction(context, action),
                              itemBuilder: (BuildContext context) => [
                                const PopupMenuItem(
                                  value: PigMenuAction.info,
                                  child: Text('Go to Pig Information'),
                                ),
                                const PopupMenuItem(
                                  value: PigMenuAction.updateWeight,
                                  child: Text('Update Pig Weight'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Info Grid
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoText(
                                  'Breed:',
                                  data.breed,
                                  labelColor,
                                  textColor,
                                ),
                                const SizedBox(height: 4),
                                _buildInfoText(
                                  'Sex:',
                                  data.sex,
                                  labelColor,
                                  textColor,
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoText(
                                  'Age:',
                                  data.age,
                                  labelColor,
                                  textColor,
                                ),
                                const SizedBox(height: 4),
                                _buildInfoText(
                                  'Current weight:',
                                  data.weight,
                                  labelColor,
                                  textColor,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Note Section
                      Row(
                        children: [
                          Icon(Icons.edit_square, size: 14, color: textColor),
                          const SizedBox(width: 4),
                          Text(
                            'NOTE:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: textColor,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        height: 40,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isDarkMode
                              ? const Color(0xFF2A2A2A)
                              : const Color(0xFFE0E0E0),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.black12),
                        ),
                        child: Text(
                          data.note,
                          style: TextStyle(fontSize: 13, color: textColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Helper method to build the label/value text pairs
  Widget _buildInfoText(
    String label,
    String value,
    Color labelColor,
    Color textColor,
  ) {
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(fontSize: 12, color: labelColor),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontSize: 12,
              color: textColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
