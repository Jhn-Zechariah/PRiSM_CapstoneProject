import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// The local date and time when a feeding actually happened.
class FeedingDateTimeFields extends StatelessWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  const FeedingDateTimeFields({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return FormField<DateTime>(
      initialValue: value,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (_) => value.isAfter(DateTime.now())
          ? 'Feeding date and time cannot be in the future.'
          : null,
      builder: (field) {
        void update(DateTime selected) {
          field.didChange(selected);
          onChanged(selected);
        }

        final dateButton = OutlinedButton.icon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2000),
              lastDate: DateTime.now(),
            );
            if (picked == null || !context.mounted) return;
            update(DateTime(
              picked.year, picked.month, picked.day, value.hour, value.minute,
            ));
          },
          icon: const Icon(Icons.calendar_today_outlined, size: 18),
          label: Text('Date: ${DateFormat.yMMMd().format(value)}'),
        );
        final timeButton = OutlinedButton.icon(
          onPressed: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(value),
            );
            if (picked == null || !context.mounted) return;
            update(DateTime(
              value.year, value.month, value.day, picked.hour, picked.minute,
            ));
          },
          icon: const Icon(Icons.access_time, size: 18),
          label: Text('Time: ${TimeOfDay.fromDateTime(value).format(context)}'),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Feeding date and time',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [dateButton, timeButton],
            ),
            if (field.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  field.errorText!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
