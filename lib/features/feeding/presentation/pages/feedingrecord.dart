import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

// --- Core Widgets ---
import '../../../../core/widgets/app_top_bar.dart';

// --- Domain & State ---
import '../../../../core/widgets/header.dart';
import '../../../../core/widgets/textlink.dart';
import '../../../pig_management/domain/model/app_pig.dart';
import '../../../pig_management/presentation/cubits/pig_cubit.dart';
import '../../../pig_management/presentation/cubits/pig_states.dart';

// --- Feature Widgets & Pages ---
import '../../data/firestore_feeding_record_repo.dart';
import '../components/feeding_card.dart';
import '../cubits/feeding_history_cubit.dart';
import '../cubits/feeding_record_cubit.dart';
import 'selectpigfeedpopup.dart';
import 'feedinghistory.dart';

class FeedingRecordsPage extends StatefulWidget {
  const FeedingRecordsPage({super.key});

  @override
  State<FeedingRecordsPage> createState() => _FeedingRecordsPageState();
}

class _FeedingRecordsPageState extends State<FeedingRecordsPage> {
  int _expandedIndex = -1;

  // Consistent UI colors for pigs
  final List<Color> _accentColors = const [
    Color.fromRGBO(214, 40, 40, 1),
    Color.fromRGBO(0, 48, 73, 1),
    Color.fromRGBO(247, 127, 0, 1),
    Color(0xFF81C784),
    Color(0xFFBA68C8),
  ];

  @override
  void initState() {
    super.initState();
    // No need to call fetchAllPigs() here anymore.
    // PigCubit handles it automatically via _listenToAuthChanges()
  }

  // Filter for Active pigs only (ignores Sold/Deceased)
  List<AppPig> _getActivePigs(List<AppPig> allPigs) {
    return allPigs.where((pig) {
      final statusLower = pig.status.toLowerCase();
      return statusLower != 'sold' && statusLower != 'deceased';
    }).toList();
  }

  // Assign a consistent color strip to each pig based on index
  Color _getColorForPig(int index) {
    return _accentColors[index % _accentColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppTopBar(),
          const SizedBox(height: 16),
          Expanded(
            child: BlocBuilder<PigCubit, PigState>(
              builder: (context, state) {
                if (state is PigLoading) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFF2563EB)),
                  );
                } else if (state is PigError) {
                  return Center(
                    child: Text(
                      'Error: ${state.message}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                } else if (state is PigLoaded) {
                  // Filter out inactive pigs for this specific screen
                  final activePigs = _getActivePigs(state.allPigs);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Global Header Component ─────────────────────────────
                      CustomFeatureHeader(
                        title: 'Feeding Records',
                        icon: Symbols.yoshoku,
                        trailing: IconButton(
                          icon: const Icon(Icons.add, size: 28),
                          color: isDarkMode ? Colors.white : Colors.black,
                          onPressed: () {
                            if (activePigs.isEmpty) return;

                            // 1. Grab the Cubit context safely
                            final feedingCubit = context
                                .read<FeedingRecordCubit>();

                            showDialog(
                              context: context,
                              builder: (dialogContext) {
                                return BlocProvider.value(
                                  value: feedingCubit,
                                  child: SelectPigFeedPopup(
                                    pigs: activePigs,
                                    pigColor: const Color(
                                      0xFFF2563EB,
                                    ), //  Replaced Colors.blue with your matching accent theme color
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),

                      // ── Global Text Link Component ──────────────────────────
                      CustomTextLink(
                        text: 'View feeding history',
                        onPressed: () {
                          // Make sure you look up your active/loaded pig state context here
                          final pigState = context.read<PigCubit>().state;
                          List<AppPig> allPigs = [];
                          if (pigState is PigLoaded) {
                            allPigs = pigState.allPigs;
                          }

                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BlocProvider(
                                create: (context) => FeedingHistoryCubit(
                                  repo: FirestoreFeedingRecordRepo(),
                                )..loadGlobalFeedingHistory(),
                                child: FeedingHistoryPage(
                                  availablePigs: allPigs,
                                ), //  Passed pigs list here
                              ),
                            ),
                          );
                        },
                      ),

                      const SizedBox(height: 12),

                      // ── Feeding Cards List ──────────────────────────────────
                      Expanded(
                        child: activePigs.isEmpty
                            ? Center(
                                child: Text(
                                  'No active pigs available for feeding.',
                                  style: TextStyle(
                                    color: isDarkMode
                                        ? Colors.white54
                                        : Colors.black54,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: activePigs.length,
                                itemBuilder: (context, index) {
                                  final pig = activePigs[index];
                                  final isExpanded = _expandedIndex == index;

                                  return FeedingCard(
                                    pig: pig, //  Pass the object here!
                                    color: _getColorForPig(index),
                                    isExpanded: isExpanded,
                                    onToggleExpand: () {
                                      setState(() {
                                        _expandedIndex = isExpanded
                                            ? -1
                                            : index;
                                      });
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink(); // Failsafe for PigInitial state
              },
            ),
          ),
        ],
      ),
    );
  }
}
