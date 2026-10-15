import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../core/widgets/app_top_bar.dart';
import '../../../../core/widgets/header.dart';
import '../../../../core/widgets/textlink.dart';
import '../../../pig_management/domain/model/app_pig.dart';
import '../../../pig_management/presentation/components/pig_profile_card.dart';
import '../../../pig_management/presentation/cubits/pig_cubit.dart';
import '../../../pig_management/presentation/cubits/pig_states.dart';
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
  // Tracked by id, not list index, so the open card stays with its pig when
  // a new pig is added at the top of the list.
  String? _expandedPigId;

  List<AppPig> _getActivePigs(List<AppPig> allPigs) =>
      allPigs.where((pig) => !pig.isInactive).toList();

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
                          // App-wide cubit (main.dart): its cache survives
                          // between visits and is busted whenever a record
                          // is saved, so reopening history is free.
                          final historyCubit =
                              context.read<FeedingHistoryCubit>();
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => BlocProvider.value(
                                value: historyCubit,
                                child: FeedingHistoryPage(
                                  availablePigs: state.allPigs,
                                ),
                              ),
                            ),
                          );
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
                            final isExpanded = _expandedPigId == pig.pigId;

                            return FeedingCard(
                              key: ValueKey(pig.pigId),
                              pig: pig,
                              color: pigAccentColor(index),
                              isExpanded: isExpanded,
                              onToggleExpand: () {
                                setState(() {
                                  _expandedPigId =
                                  isExpanded ? null : pig.pigId;
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