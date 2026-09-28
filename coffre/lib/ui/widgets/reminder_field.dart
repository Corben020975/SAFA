import 'package:flutter/material.dart';

import '../../core/date_labels.dart';

/// Choix du rappel : raccourcis en un tap + date/heure personnalisées.
class ReminderField extends StatelessWidget {
  const ReminderField({super.key, required this.value, required this.onChanged});
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    DateTime at(int addDays, int hour) =>
        DateTime(today.year, today.month, today.day + addDays, hour);
    final toMonday = (DateTime.monday - now.weekday) % 7;
    final nextMonday = at(toMonday == 0 ? 7 : toMonday, 9);

    final presets = <(String, DateTime)>[
      ('Dans 1 h', DateTime(now.year, now.month, now.day, now.hour + 1, now.minute)),
      if (now.hour < 18) ('Ce soir 18:00', at(0, 18)),
      ('Demain 09:00', at(1, 9)),
      ('Lundi 09:00', nextMonday),
    ];
    final scheme = Theme.of(context).colorScheme;
    final overdue = value != null && value!.isBefore(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value != null)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            color: overdue ? scheme.errorContainer : scheme.primaryContainer,
            child: ListTile(
              leading: Icon(overdue ? Icons.alarm_off : Icons.alarm_on),
              title: Text(formatReminder(value!)),
              subtitle: overdue ? const Text('Rappel passé') : Text(formatLong(value!)),
              trailing: IconButton(
                tooltip: 'Retirer le rappel',
                icon: const Icon(Icons.close),
                onPressed: () => onChanged(null),
              ),
              onTap: () => _pickCustom(context),
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, date) in presets)
              ActionChip(
                avatar: const Icon(Icons.alarm_add, size: 20),
                label: Text(label),
                onPressed: () => onChanged(date),
              ),
            ActionChip(
              avatar: const Icon(Icons.edit_calendar, size: 20),
              label: const Text('Choisir…'),
              onPressed: () => _pickCustom(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final now = DateTime.now();
    final initial = (value != null && value!.isAfter(now)) ? value! : now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      helpText: 'Date du rappel',
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      helpText: 'Heure du rappel',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !context.mounted) return;
    final chosen = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (!chosen.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette heure est déjà passée.')),
      );
      return;
    }
    onChanged(chosen);
  }
}
