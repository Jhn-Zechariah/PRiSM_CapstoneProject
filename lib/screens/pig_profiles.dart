import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

// Adjust these imports based on your exact folder structure
import '../features/auth/presentation/components/app_top_bar.dart';
import '../features/auth/presentation/components/pig_profile_card.dart';
import '../features/auth/presentation/cubits/pig_cubit.dart';
import 'pig_information.dart';
import '../features/auth/presentation/cubits/pig_states.dart';
import 'pig_weight_history.dart';

class PigProfilesScreen extends StatelessWidget {
  const PigProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Custom App Bar
          const AppTopBar(),
          const SizedBox(height: 16),

          // Header Row
          Row(
            children: [
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
                      builder: (context) => const PigInformationScreen(),
                    ),
                  );
                },
              ),
            ],
          ),

          // View Weight History Link
          // View Weight History Link
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {
                final state = context.read<PigCubit>().state;

                if (state is PigLoaded) {
                  final colors = [
                    Colors.red,
                    const Color(0xFF003366),
                    Colors.orange,
                  ];

                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WeightHistoryScreen(
                        pigs: state.pigs.asMap().entries.map((entry) {
                          final index = entry.key;
                          final pig = entry.value;
                          return PigOption(
                            id: pig.pigId, // your pig model's id field
                            // your pig model's name field
                            accentColor: colors[index % colors.length],
                          );
                        }).toList(),
                        weightRecords:
                            const [], // replace with real records later
                        isLoading: false,
                      ),
                    ),
                  );
                }
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

          // List of Profile Cards using BlocBuilder
          Expanded(
            child: BlocBuilder<PigCubit, PigState>(
              builder: (context, state) {
                if (state is PigLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is PigError) {
                  return Center(
                    child: Text(
                      state.message,
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                }

                if (state is PigLoaded) {
                  final pigs = state.pigs;

                  if (pigs.isEmpty) {
                    return Center(
                      child: Text(
                        'No pigs added yet. Click + to add one!',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white70 : Colors.black54,
                          fontSize: 16,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: pigs.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 16),
                    itemBuilder: (context, index) {
                      // Looping color logic for the left accent stripe
                      final colors = [
                        Colors.red,
                        const Color(0xFF003366),
                        Colors.orange,
                      ];
                      final assignedColor = colors[index % colors.length];

                      return PigProfileCard(
                        pig: pigs[index],
                        accentColor: assignedColor,
                        isDarkMode: isDarkMode,
                      );
                    },
                  );
                }

                // Fallback for PigInitial or any other unhandled state
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}
