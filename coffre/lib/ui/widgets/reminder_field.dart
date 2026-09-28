import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/date_labels.dart';
import '../../core/reminder_defaults.dart';
import '../theme.dart';

/// Choix du rappel : raccourcis en un tap, puis date et heure réglables
/// séparément (touche la date ou l'heure pour la changer).
class ReminderField extends StatelessWidget {
  const ReminderField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final (mh, mm) = ReminderDefaults.morning;
    final (eh, em) = ReminderDefaults.evening;
    DateTime at(int addDays, int hour, int minute) =>
        DateTime(now.year, now.month, now.day + addDays, hour, minute);
    final toMonday = (DateTime.monday - now.weekday) % 7;
    final tonight = at(0, eh, em);
    final morning = ReminderDefaults.label(ReminderDefaults.morning);

    final presets = <(String, DateTime)>[
      (
        'Dans 1 h',
        DateTime(now.year, now.month, now.day, now.hour + 1, now.minute),
      ),
      if (now.isBefore(tonight))
        (
          'Ce soir ${ReminderDefaults.label(ReminderDefaults.evening)}',
          tonight,
        ),
      ('Demain $morning', at(1, mh, mm)),
      ('Lundi $morning', at(toMonday == 0 ? 7 : toMonday, mh, mm)),
    ];
    final scheme = Theme.of(context).colorScheme;
    final p = Palette.of(context);
    final overdue = value != null && value!.isBefore(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (value != null)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            decoration: BoxDecoration(
              color: overdue ? scheme.errorContainer : scheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      overdue ? Icons.alarm_off : Icons.alarm_on,
                      color: overdue
                          ? scheme.onErrorContainer
                          : scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        overdue
                            ? 'Rappel passé · ${formatReminder(value!)}'
                            : formatReminder(value!),
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              color: overdue
                                  ? scheme.onErrorContainer
                                  : scheme.onPrimaryContainer,
                            ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Retirer le rappel',
                      icon: const Icon(Icons.close),
                      onPressed: () => onChanged(null),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _Pick(
                        icon: Icons.calendar_today_outlined,
                        label: DateFormat('EEE d MMM y', 'fr').format(value!),
                        tooltip: 'Changer la date',
                        onTap: () => _pickDate(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _Pick(
                      icon: Icons.schedule,
                      label: DateFormat.Hm('fr').format(value!),
                      tooltip: 'Changer l\'heure',
                      onTap: () => _pickTime(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (label, date) in presets)
              ActionChip(
                avatar: Icon(Icons.alarm_add, size: 20, color: p.sage),
                label: Text(label),
                onPressed: () => onChanged(date),
              ),
            ActionChip(
              avatar: Icon(Icons.edit_calendar, size: 20, color: p.sage),
              label: const Text('Date et heure…'),
              onPressed: () => _pickCustom(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickCustom(BuildContext context) async {
    final chosen = await pickReminderDateTime(context, value);
    if (chosen != null) onChanged(chosen);
  }

  /// Change le jour en gardant l'heure.
  Future<void> _pickDate(BuildContext context) async {
    final current = value!;
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current.isBefore(now) ? now : current,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 5),
      helpText: 'Date du rappel',
    );
    if (date == null || !context.mounted) return;
    _commit(
      context,
      DateTime(date.year, date.month, date.day, current.hour, current.minute),
    );
  }

  /// Change l'heure en gardant le jour.
  Future<void> _pickTime(BuildContext context) async {
    final current = value!;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: 'Heure du rappel',
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (time == null || !context.mounted) return;
    _commit(
      context,
      DateTime(
        current.year,
        current.month,
        current.day,
        time.hour,
        time.minute,
      ),
    );
  }

  void _commit(BuildContext context, DateTime chosen) {
    if (!chosen.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette heure est déjà passée.')),
      );
      return;
    }
    onChanged(chosen);
  }
}

class _Pick extends StatelessWidget {
  const _Pick({
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: scheme.surface.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: scheme.onPrimaryContainer),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge
                        ?.copyWith(color: scheme.onPrimaryContainer),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.edit,
                  size: 14,
                  color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sélecteur date puis heure (format 24 h). Refuse une heure passée.
Future<DateTime?> pickReminderDateTime(
  BuildContext context,
  DateTime? current,
) async {
  final now = DateTime.now();
  final initial = (current != null && current.isAfter(now))
      ? current
      : now.add(const Duration(hours: 1));
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(now.year, now.month, now.day),
    lastDate: DateTime(now.year + 5),
    helpText: 'Date du rappel',
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    helpText: 'Heure du rappel',
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  if (time == null || !context.mounted) return null;
  final chosen = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  if (!chosen.isAfter(DateTime.now())) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cette heure est déjà passée.')),
    );
    return null;
  }
  return chosen;
}
