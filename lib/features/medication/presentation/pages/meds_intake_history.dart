import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';

import '../cubits/medicine_cubit.dart';
import '../cubits/medicine_states.dart';
import '../../domain/model/app_medicine_intake.dart';

class PigMedOption {
  final String id;
  final String displayId;
  final String breed;
  final String status;
  final Color accentColor;

  PigMedOption({
    required this.id,
    required this.displayId,
    required this.breed,
    required this.status,
    required this.accentColor,
  });
}

class MedsIntakeHistoryScreen extends StatefulWidget {
  final List<PigMedOption> pigs;

  const MedsIntakeHistoryScreen({super.key, required this.pigs});

  @override
  State<MedsIntakeHistoryScreen> createState() =>
      _MedsIntakeHistoryScreenState();
}

class _MedsIntakeHistoryScreenState extends State<MedsIntakeHistoryScreen> {
  String _selectedFilter = 'All';
  String _currentFilter = 'Active';

  @override
  void initState() {
    super.initState();
    context.read<MedicineCubit>().listenToIntakes();
  }

  List<PigMedOption> get _filteredPigsByStatus {
    return widget.pigs.where((pig) {
      final statusLower = pig.status.toLowerCase();
      final isInactive = statusLower == 'sold' || statusLower == 'deceased';

      return _currentFilter == 'Active' ? !isInactive : isInactive;
    }).toList();
  }

  void _loadInitialPig() {
    setState(() {
      _selectedFilter = 'All';
    });
  }

  Widget _buildFiltersRow(bool isDark) {
    final displayPigs = _filteredPigsByStatus;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _currentFilter,
            icon: Icon(
              Icons.filter_list,
              size: 18,
              color: isDark ? Colors.white : Colors.black87,
            ),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
            dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            items: const [
              DropdownMenuItem(value: 'Active', child: Text('Current Pigs')),
              DropdownMenuItem(value: 'Inactive', child: Text('Removed Pigs')),
            ],
            onChanged: (value) {
              if (value != null && value != _currentFilter) {
                setState(() {
                  _currentFilter = value;
                  _loadInitialPig();
                });
              }
            },
          ),
        ),

        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: _selectedFilter,
            icon: const Icon(
              Icons.keyboard_arrow_down,
              size: 18,
              color: Color(0xFF2563EB),
            ),
            style: const TextStyle(
              color: Color(0xFF2563EB),
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            dropdownColor: isDark ? const Color(0xFF2C2C2C) : Colors.white,
            isDense: true,
            items: [
              const DropdownMenuItem<String>(
                value: 'All',
                child: Text(
                  'All Pigs',
                  style: TextStyle(
                    color: Color(0xFF2563EB),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ...displayPigs.map((pig) {
                return DropdownMenuItem(
                  value: pig.id,
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: pig.accentColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                      Text(
                        '${pig.breed} | ${pig.displayId}',
                        style: const TextStyle(
                          color: Color(0xFF2563EB),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            onChanged: (value) {
              if (value != null && value != _selectedFilter) {
                setState(() => _selectedFilter = value);
              }
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final validPigIds = _filteredPigsByStatus
        .where((p) {
          if (_selectedFilter == 'All') return true;
          return p.id == _selectedFilter;
        })
        .map((p) => p.id)
        .toSet();

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppTopBar(title: 'Medicine History', showBackButton: true),
              const SizedBox(height: 12),

              _buildFiltersRow(isDark),
              const SizedBox(height: 8),

              Expanded(
                child: validPigIds.isEmpty
                    ? Center(
                        child: Text(
                          _currentFilter == 'Active'
                              ? 'No active pigs found.'
                              : 'No inactive pigs found.',
                          style: TextStyle(
                            color: isDark ? Colors.white54 : Colors.black54,
                          ),
                        ),
                      )
                    : BlocBuilder<MedicineCubit, MedicineState>(
                        builder: (context, state) {
                          if (state is MedicineLoading ||
                              state is MedicineInitial) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }

                          if (state is MedicineError) {
                            return Center(
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Text(
                                  'Error: ${state.message}',
                                  style: TextStyle(color: Colors.red.shade400),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }

                          if (state is MedicineIntakesLoaded) {
                            final filteredIntakes = state.intakes.where((
                              intake,
                            ) {
                              return validPigIds.contains(intake.pigId);
                            }).toList();

                            if (filteredIntakes.isEmpty) {
                              return Center(
                                child: Text(
                                  'No intake records found for the selected filter.',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.white54
                                        : Colors.black54,
                                  ),
                                ),
                              );
                            }

                            return ListView.builder(
                              itemCount: filteredIntakes.length,
                              itemBuilder: (context, index) {
                                final intake = filteredIntakes[index];

                                final matchedPig = widget.pigs.firstWhere(
                                  (p) => p.id == intake.pigId,
                                  orElse: () => PigMedOption(
                                    id: intake.pigId,
                                    displayId: 'Unknown',
                                    breed: 'Unknown',
                                    status: 'Unknown',
                                    accentColor: Colors.grey,
                                  ),
                                );

                                return IntakeHistoryCard(
                                  intake: intake,
                                  displayId: matchedPig.breed,
                                  accentColor: matchedPig.accentColor,
                                  isDark: isDark,
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
      ),
    );
  }
}

class IntakeHistoryCard extends StatelessWidget {
  final MedicineIntake intake;
  final String displayId;
  final Color accentColor;
  final bool isDark;

  const IntakeHistoryCard({
    super.key,
    required this.intake,
    required this.displayId,
    required this.accentColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final date = intake.dateTaken;
    final formattedDate =
        "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2C) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.grey.shade300,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 10,
              decoration: BoxDecoration(
                color: accentColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  bottomLeft: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          displayId,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                            color: isDark ? Colors.white : Colors.black,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            intake.status,
                            style: TextStyle(
                              color: isDark ? Colors.white70 : accentColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildInfoRow(
                            '${intake.category}: ',
                            intake.medName,
                          ),
                        ),
                        Expanded(
                          child: _buildInfoRow(
                            'Dosage: ',
                            '${intake.dosage} ${intake.unitOfMeasurement}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    _buildInfoRow('Date Taken: ', formattedDate),
                    if (intake.purpose != null &&
                        intake.purpose!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      _buildInfoRow('Purpose: ', intake.purpose!),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.white60 : Colors.black54,
        ),
        children: [
          TextSpan(text: label),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
