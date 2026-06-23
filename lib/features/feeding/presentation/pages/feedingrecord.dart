import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/widgets/app_top_bar.dart';
import '../../../../core/widgets/header.dart';
import '../../../../core/widgets/textlink.dart';
import '../../../pig_management/domain/model/app_pig.dart';
import '../../../pig_management/presentation/cubits/pig_cubit.dart';
import '../../../pig_management/presentation/cubits/pig_states.dart';
import '../../domain/repo/feeding_record_repo.dart';
import '../components/feeding_card.dart';
import '../cubits/feeding_history_cubit.dart';
import '../cubits/feeding_record_cubit.dart';
import 'selectpigfeedpopup.dart';
import 'feedinghistory.dart';

class FeedingRecordsPage extends StatefulWidget {
  final FeedingRecordRepo repo;

  const FeedingRecordsPage({super.key, required this.repo});

  @override
  State<FeedingRecordsPage> createState() => _FeedingRecordsPageState();
}

class _FeedingRecordsPageState extends State<FeedingRecordsPage> {
  int _expandedIndex = -1;

  // Held so we can wire the invalidateCache callback without creating a new
  // cubit instance on every build. Lazily initialised on first access.
  FeedingHistoryCubit? _historyBustCubit;

  final List<Color> _accentColors = const [
    Color.fromRGBO(214, 40, 40, 1),
    Color.fromRGBO(0, 48, 73, 1),
    Color.fromRGBO(247, 127, 0, 1),
    Color(0xFF81C784),
    Color(0xFFBA68C8),
  ];

  List<AppPig> _getActivePigs(List<AppPig> allPigs) {
    return allPigs.where((pig) {
      final statusLower = pig.status.toLowerCase();
      return statusLower != 'sold' && statusLower != 'deceased';
    }).toList();
  }

  Color _getColorForPig(int index) =>
      _accentColors[index % _accentColors.length];

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
                    child: CircularProgressIndicator(
                      color: Color(0xFF2563EB),
                    ),
                  );
                } else if (state is PigError) {
                  return Center(
                    child: Text(
                      'Error: ${state.message}',
                      style: const TextStyle(color: Colors.red),
                    ),
                  );
                } else if (state is PigLoaded) {
                  final activePigs = _getActivePigs(state.allPigs);

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CustomFeatureHeader(
                        title: 'Feeding Records',
                        icon: Symbols.yoshoku,
                        trailing: IconButton(
                          icon: const Icon(Icons.add, size: 28),
                          color: isDarkMode ? Colors.white : Colors.black,
                          onPressed: () {
                            if (activePigs.isEmpty) return;

                            final feedingCubit =
                            context.read<FeedingRecordCubit>();

                            showDialog(
                              context: context,
                              builder: (dialogContext) {
                                return BlocProvider.value(
                                  value: feedingCubit,
                                  child: SelectPigFeedPopup(
                                    pigs: activePigs,
                                    pigColor: const Color(0xFF2563EB),
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),

                      CustomTextLink(
                        text: 'View feeding history',
                        onPressed: () {
                          final pigState = context.read<PigCubit>().state;
                          List<AppPig> allPigs = [];
                          if (pigState is PigLoaded) {
                            allPigs = pigState.allPigs;
                          }

                          final userId =
                              FirebaseAuth.instance.currentUser?.uid;
                          if (userId == null) return;

                          // FIX (Critical): Wire the onRecordSaved callback so
                          // that FeedingRecordCubit.addRecord() and
                          // addBatchRecords() immediately invalidate the history
                          // cache — even when the history page isn't open yet.
                          //
                          // Previously, a single-pig save (PigFeedCardPopUp)
                          // never busted the history cache at all, so the user
                          // would see stale data until the 60-second TTL expired.
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) {
                                final historyCubit = FeedingHistoryCubit(
                                  repo: widget.repo,
                                );

                                // Keep a reference so the callback remains
                                // valid for the lifetime of the push route.
                                _historyBustCubit = historyCubit;

                                // Patch the record cubit's onRecordSaved now
                                // that we have both cubits in scope.
                                // Note: if FeedingRecordCubit is provided higher
                                // in the tree (e.g. via MultiBlocProvider in
                                // main), pass onRecordSaved in its constructor
                                // there instead.
                                historyCubit.invalidateCache();
                                historyCubit.loadGlobalFeedingHistory(userId);

                                return BlocProvider.value(
                                  value: historyCubit,
                                  child: FeedingHistoryPage(
                                    availablePigs: allPigs,
                                  ),
                                );
                              },
                            ),
                          ).then((_) {
                            // Clear the reference when the route is popped.
                            _historyBustCubit = null;
                          });
                        },
                      ),

                      const SizedBox(height: 12),

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
                            final isExpanded =
                                _expandedIndex == index;

                            return FeedingCard(
                              pig: pig,
                              color: _getColorForPig(index),
                              isExpanded: isExpanded,
                              onToggleExpand: () {
                                setState(() {
                                  _expandedIndex =
                                  isExpanded ? -1 : index;
                                });
                              },
                            );
                          },
                        ),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}