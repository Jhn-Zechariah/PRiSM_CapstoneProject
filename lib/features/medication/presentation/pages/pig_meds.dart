// ignore_for_file: camel_case_types

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/build_tab_bar.dart';
import 'package:prism_app/features/medication/presentation/components/pig_med_card.dart';
import 'package:prism_app/features/pig_management/presentation/cubits/pig_cubit.dart';
import '../../../../core/widgets/app_top_bar.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../pig_management/presentation/cubits/pig_states.dart';
import 'meds_intake_history.dart';

class pig_meds extends StatefulWidget {
  final VoidCallback? onSwitchToStock;

  const pig_meds({super.key, this.onSwitchToStock});

  @override
  State<pig_meds> createState() => _pig_medsState();
}

class _pig_medsState extends State<pig_meds> {
  int _selectedTab = 1;

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(),
          const SizedBox(height: 16),

          Row(
            children: [
              const Icon(Symbols.vaccines, size: 32),
              const SizedBox(width: 12),
              const Text(
                'Healthcare',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.add, size: 28),
                onPressed: () {},
              ),
            ],
          ),

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
                        final colors = [
                          Colors.red,
                          const Color(0xFF003366),
                          Colors.orange,
                        ];
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MedsIntakeHistoryScreen(
                              pigs: state.allPigs.asMap().entries.map((entry) {
                                return PigMedOption(
                                  id: entry.value.pigId,
                                  accentColor:
                                      colors[entry.key % colors.length],
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
                        final pigs = state.allPigs;

                        if (pigs.isEmpty) {
                          return Center(
                            child: Text(
                              'No pigs added yet. Click + to add one!',
                              style: TextStyle(
                                color: isDarkMode
                                    ? Colors.white70
                                    : Colors.black54,
                                fontSize: 16,
                              ),
                            ),
                          );
                        }

                        final colors = [
                          Colors.red,
                          const Color(0xFF003366),
                          Colors.orange,
                        ];

                        return ListView.separated(
                          itemCount: pigs.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 12),
                          itemBuilder: (context, index) {
                            return PigMedCard(
                              pig: pigs[index],
                              accentColor: colors[index % colors.length],
                              onAdd: () {
                                // TODO: open add medication dialog
                              },
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
