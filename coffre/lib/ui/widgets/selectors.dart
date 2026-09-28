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
  const PrioritySelector({super.key, required this.value, required this.onChanged});
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
            ButtonSegment(
              value: p,
              label: Text(p.label),
              icon: p == ItemPriority.high ? const Icon(Icons.flag) : null,
            ),
        ],
        selected: {value},
        onSelectionChanged: (s) => onChanged(s.first),
      ),
    );
  }
}

class StatusSelector extends StatelessWidget {
  const StatusSelector({super.key, required this.value, required this.onChanged});
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
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
