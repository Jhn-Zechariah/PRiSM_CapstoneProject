import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import 'package:prism_app/features/medication/domain/model/app_medicine_intake.dart';

class MedsIntakeScheduleScreen extends StatelessWidget {
  final Stream<List<MedicineIntake>> intakeStream;

  const MedsIntakeScheduleScreen({
    super.key,
    required this.intakeStream,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const AppTopBar(
                showBackButton: true,
                title: 'Upcoming Schedule',
              ),

              const SizedBox(height: 12),

              Expanded(
                child: StreamBuilder<List<MedicineIntake>>(
                  stream: intakeStream,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          'Error: ${snapshot.error}',
                        ),
                      );
                    }

                    if (snapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }

                    // 🔹 Filter out any records with no schedule date at all,
                    // since nextSchedule is nullable.
                    final schedules = (snapshot.data ?? [])
                        .where((intake) => intake.nextSchedule != null)
                        .toList();

                    if (schedules.isEmpty) {
                      return const Center(
                        child: Text(
                          'No upcoming schedules.',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey,
                          ),
                        ),
                      );
                    }

                    final today = DateTime.now();
                    final todayOnly = DateTime(
                      today.year,
                      today.month,
                      today.day,
                    );

                    return ListView.builder(
                      itemCount: schedules.length,
                      itemBuilder: (context, index) {
                        final intake = schedules[index];

                        // 🔹 No more DateTime.parse — nextSchedule is
                        // already a DateTime, set directly from Firestore.
                        final scheduleDate = intake.nextSchedule!;

                        final targetDate = DateTime(
                          scheduleDate.year,
                          scheduleDate.month,
                          scheduleDate.day,
                        );

                        final diffDays =
                            targetDate.difference(todayOnly).inDays;

                        String displayDays;

                        if (diffDays < 0) {
                          // 🔹 Handles overdue schedules gracefully instead
                          // of showing a confusing negative day count.
                          displayDays = "Overdue";
                        } else if (diffDays == 0) {
                          displayDays = "Scheduled today";
                        } else if (diffDays == 1) {
                          displayDays = "Scheduled tomorrow";
                        } else {
                          displayDays =
                          "Scheduled in $diffDays days";
                        }

                        return Card(
                          margin:
                          const EdgeInsets.only(bottom: 12),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                            BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            contentPadding:
                            const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            title: Text(
                              intake.medName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              '${intake.category} • $displayDays',
                            ),
                            trailing: Chip(
                              label: Text(
                                DateFormat('MMM dd')
                                    .format(scheduleDate),
                              ),
                            ),
                          ),
                        );
                      },
                    );
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