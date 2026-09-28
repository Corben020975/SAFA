import 'package:flutter/material.dart';

import '../../data/enums.dart';
import '../theme.dart';

class KindSelector extends StatelessWidget {
  const KindSelector({super.key, required this.value, required this.onChanged});
  final ItemKind value;
  final ValueChanged<ItemKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<ItemKind>(
        showSelectedIcon: false,
        segments: [
          for (final kind in ItemKind.values)
            ButtonSegment(
              value: kind,
              icon: Icon(kindIcon(kind)),
              label: Text(kind.label),
            ),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class PrioritySelector extends StatelessWidget {
  const PrioritySelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final ItemPriority value;
  final ValueChanged<ItemPriority> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<ItemPriority>(
        showSelectedIcon: false,
        segments: [
          for (final p in ItemPriority.values)
            ButtonSegment(value: p, label: Text(p.label)),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class StatusSelector extends StatelessWidget {
  const StatusSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final ItemStatus value;
  final ValueChanged<ItemStatus> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<ItemStatus>(
        showSelectedIcon: false,
        segments: [
          for (final s in ItemStatus.values)
            ButtonSegment(value: s, label: Text(s.label)),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

/// Contexte : Travail, Santé… (un seul, ou aucun).
class ContextSelector extends StatelessWidget {
  const ContextSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final String? value;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = [
      ...kContexts,
      if (value != null && !kContexts.contains(value)) value!,
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in options)
          ChoiceChip(
            label: Text(c),
            selected: c == value,
            onSelected: (selected) => onChanged(selected ? c : null),
          ),
      ],
    );
  }
}

/// Notification supplémentaire 1 h 30 avant le rappel (utile pour un rendez-vous).
class PreAlertSwitch extends StatelessWidget {
  const PreAlertSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        secondary: const Icon(Icons.notifications_active_outlined),
        title: const Text('Pré-alerte 1 h 30 avant'),
        subtitle: const Text('Pour un rendez-vous ou un départ'),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

/// « Répéter » : visible dès qu'un rappel est posé.
class RecurrenceField extends StatelessWidget {
  const RecurrenceField({
    super.key,
    required this.value,
    required this.onChanged,
  });
  final Recurrence value;
  final ValueChanged<Recurrence> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: const Icon(Icons.repeat),
      title: const Text('Répéter'),
      trailing: DropdownButton<Recurrence>(
        value: value,
        underline: const SizedBox.shrink(),
        borderRadius: BorderRadius.circular(16),
        onChanged: (r) {
          if (r != null) onChanged(r);
        },
        items: [
          for (final r in Recurrence.values)
            DropdownMenuItem(value: r, child: Text(r.label)),
        ],
      ),
    );
  }
}

/// Petit titre de section, lisible et discret.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8, left: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleSmall
            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
