import 'package:flutter/material.dart';
import 'package:prism_app/core/widgets/app_top_bar.dart';
import 'package:prism_app/features/medication/domain/model/app_medicine_intake.dart';
import 'package:intl/intl.dart';

class MedsIntakeScheduleScreen extends StatelessWidget {
  final Stream<List<MedicineIntake>> intakeStream;

  const MedsIntakeScheduleScreen({super.key, required this.intakeStream});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              const AppTopBar(showBackButton: true, title: 'Upcoming Schedule',),
              Expanded(
                child: StreamBuilder<List<MedicineIntake>>(
                  stream: intakeStream,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    final schedules = snapshot.data!;
                    if (schedules.isEmpty) return const Center(child: Text("No upcoming schedules."));

                    return ListView.builder(
                      itemCount: schedules.length,
                      itemBuilder: (context, index) {
                        final intake = schedules[index];
                        final scheduleDate = DateTime.parse(intake.nextSchedule!);
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);
                        final targetDate = DateTime(scheduleDate.year, scheduleDate.month, scheduleDate.day);
                        
                        final int diffDays = targetDate.difference(today).inDays;
                        String displayDays;

                        if (diffDays == 0) {
                          displayDays = "Scheduled today";
                        } else if (diffDays == 1) {
                          displayDays = "Scheduled tomorrow";
                        } else {
                          displayDays = "Scheduled in $diffDays days";
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: ListTile(
                            title: Text(intake.medName, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text("${intake.category} • $displayDays"),
                            trailing: Chip(label: Text(DateFormat('MMM dd').format(scheduleDate))),
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
