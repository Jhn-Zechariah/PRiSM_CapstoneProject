import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/features/pig_management/presentation/pages/pig_weight_history.dart';

// Adjust these imports based on your exact folder structure
import '../../data/firestore_pig_repo.dart';
import '../../../../core/widgets/app_top_bar.dart';
import '../components/pig_profile_card.dart';
import '../cubits/pig_cubit.dart';
import '../cubits/pig_states.dart';
import '../cubits/weight_history_cubit.dart';
import 'pig_information.dart';

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
          const SizedBox(height: 5),

          //Wrap the Rest in BlocBuilder so the whole section reacts to the Cubit!
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
                  // Use the filtered list from your Cubit
                  final displayPigs = state.filteredPigs;

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Dropdown & Weight History Row
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // LEFT SIDE: Active/Inactive Dropdown
                          DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: state.currentFilter, // Read from state!
                              icon: Icon(Icons.filter_list, size: 18, color: isDarkMode ? Colors.white : Colors.black87),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode ? Colors.white : Colors.black87,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Active', child: Text('Active Pigs')),
                                DropdownMenuItem(value: 'Inactive', child: Text('Inactive Pigs')),
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  // Tell Cubit to change the filter!
                                  context.read<PigCubit>().changeFilter(value);
                                }
                              },
                            ),
                          ),

                          // RIGHT SIDE: View Weight History Link
                          TextButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => BlocProvider(
                                    create: (context) => WeightHistoryCubit(
                                      pigRepo: FirebasePigRepo(),
                                    ),
                                    child: WeightHistoryScreen(
                                      // Pass ALL pigs to history so it can show everything
                                      availablePigs: state.allPigs,
                                    ),
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
                        ],
                      ),
                      const SizedBox(height: 12),

                      //The List of Filtered Pig Cards
                      Expanded(
                        child: displayPigs.isEmpty
                            ? Center(
                          child: Text(
                            state.currentFilter == 'Active'
                                ? 'No active pigs added yet. Click + to add one!'
                                : 'No inactive pigs found.',
                            style: TextStyle(
                              color: isDarkMode ? Colors.white70 : Colors.black54,
                              fontSize: 16,
                            ),
                          ),
                        )
                            : ListView.separated(
                          // Added your 100px padding to clear the BottomNav!
                          padding: const EdgeInsets.only(bottom: 100),
                          itemCount: displayPigs.length,
                          separatorBuilder: (context, index) =>
                          const SizedBox(height: 16),
                          itemBuilder: (context, index) {
                            final colors = [
                              Colors.red,
                              const Color(0xFF003366),
                              Colors.orange,
                            ];
                            final assignedColor = colors[index % colors.length];

                            return PigProfileCard(
                              pig: displayPigs[index], // Use the filtered pigs array here
                              accentColor: assignedColor,
                              isDarkMode: isDarkMode,
                            );
                          },
                        ),
                      ),
                    ],
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