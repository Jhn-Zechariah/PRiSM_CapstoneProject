// ignore_for_file: camel_case_types

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/build_tab_bar.dart';
import 'package:prism_app/features/medication/presentation/components/pig_med_card.dart';
import 'package:prism_app/features/medication/presentation/pages/meds_intake_history.dart';
import 'package:prism_app/features/pig_management/presentation/cubits/pig_states.dart';
import 'package:prism_app/features/pig_management/presentation/cubits/pig_cubit.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/widgets/header.dart';
import '../../../pig_management/domain/model/app_pig.dart';
import '../cubits/medicine_cubit.dart';
import 'meds_intake_schedule.dart';

class pig_meds extends StatefulWidget {
  final VoidCallback? onSwitchToStock;

  const pig_meds({super.key, this.onSwitchToStock});

  @override
  State<pig_meds> createState() => _pig_medsState();
}

// Filter for Active pigs only (ignores Sold/Deceased)
List<AppPig> _getActivePigs(List<AppPig> allPigs) {
  return allPigs.where((pig) {
    final statusLower = pig.status.toLowerCase();
    return statusLower != 'sold' && statusLower != 'deceased';
  }).toList();
}

class _pig_medsState extends State<pig_meds> {
  int _selectedTab = 1;

  // 🔹 Define colors here so they stay synchronized across the file
  final List<Color> _accentColors = const [
    Colors.red,
    Color(0xFF003366),
    Colors.orange,
  ];

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(),
          const SizedBox(height: 11),

          CustomFeatureHeader(
            title: 'Healthcare',
            icon: Symbols.vaccines,
            trailing: IconButton(
              icon: const Icon(Icons.calendar_month_outlined, size: 28),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MedsIntakeScheduleScreen(
                      intakeStream: context.read<MedicineCubit>().repository.streamUpcomingIntakes(),
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 10),

          Expanded(
            child: Column(
              children: [
                CustomTabBar(
                  selectedIndex: _selectedTab,
                  tabs: const ["Stock", "Pig Medications"],
                  onTabSelected: (index) {
                    setState(() => _selectedTab = index);
                    if (index == 0) widget.onSwitchToStock?.call();
                  },
                ),
                const SizedBox(height: 8),

                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () {
                      final state = context.read<PigCubit>().state;
                      if (state is PigLoaded) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MedsIntakeHistoryScreen(
                              pigs: state.allPigs.asMap().entries.map((entry) {
                                final index = entry.key;
                                final pig = entry.value;

                                return PigMedOption(
                                  id: pig.pigId,
                                  displayId: pig.displayId,
                                  status: pig.status,
                                  breed: pig.breed,
                                  // 🔹 FIXED: Dynamically matches the exact color array layout index
                                  accentColor: _accentColors[index % _accentColors.length],
                                );
                              }).toList(),
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
                      'View Medicine history',
                      style: TextStyle(
                        color: Color(0xFF3B82F6),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),

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
                        final activePigs = _getActivePigs(state.allPigs);

                        if (activePigs.isEmpty) {
                          return Center(
                            child: Text(
                              'No active pigs found.',
                              style: TextStyle(
                                color: isDarkMode ? Colors.white70 : Colors.black54,
                                fontSize: 16,
                              ),
                            ),
                          );
                        }

                        return ListView.separated(
                          itemCount: activePigs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            // 🔹 Finding the global index from allPigs so colors don't change when filtering
                            final globalIndex = state.allPigs.indexOf(activePigs[index]);
                            final itemColor = _accentColors[globalIndex != -1
                                ? (globalIndex % _accentColors.length)
                                : (index % _accentColors.length)];

                            return PigMedCard(
                              pig: activePigs[index],
                              accentColor: itemColor,
                              onAdd: () {},
                            );
                          },
                        );
                      }

                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}