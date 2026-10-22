import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../data/database.dart';
import '../../services/day_focus.dart';
import '../item_actions.dart';
import '../theme.dart';
import 'focus_card.dart';

/// « Choisis tes 3 » : les plus urgentes en haut, 3 cases au maximum.
Future<void> showFocusPicker(BuildContext context, List<Item> open) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _FocusPicker(open: open),
  );
}

class _FocusPicker extends StatefulWidget {
  const _FocusPicker({required this.open});
  final List<Item> open;

  @override
  State<_FocusPicker> createState() => _FocusPickerState();
}

class _FocusPickerState extends State<_FocusPicker> {
  late final DateTime _now = DateTime.now();
  late final List<Item> _ranked = DayFocus.ranked(widget.open, _now);
  late final Set<int> _selected = {
    for (final i
        in DayFocus.chosen(AppScope.of(context).settings, widget.open, _now) ??
            DayFocus.suggest(widget.open, _now))
      i.id,
  };

  Future<void> _save() async {
    final settings = AppScope.of(context).settings;
    final ids = [
      for (final i in _ranked)
        if (_selected.contains(i.id)) i.id,
    ];
    await settings.setFocus(DayFocus.dayKey(_now), ids);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    final full = _selected.length >= DayFocus.size;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      builder: (context, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Choisis tes 3',
                    style: displayStyle(context, 24),
                  ),
                ),
                Text(
                  '${_selected.length}/${DayFocus.size}',
                  style: theme.textTheme.titleMedium?.copyWith(color: p.sage),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
            child: Text(
              'Les retards et les priorités hautes sont en haut. Le reste attend demain.',
              style: theme.textTheme.bodyMedium?.copyWith(color: p.muted),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: _ranked.length,
              itemBuilder: (context, index) {
                final item = _ranked[index];
                final on = _selected.contains(item.id);
                final when = itemWhen(item, _now);
                return CheckboxListTile(
                  value: on,
                  onChanged: !on && full
                      ? null
                      : (v) => setState(() {
                          v == true
                              ? _selected.add(item.id)
                              : _selected.remove(item.id);
                        }),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    item.content.trim().split('\n').first,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    [item.priority.label, ?when, ?itemSource(item)].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  secondary: Container(
                    width: 4,
                    height: 32,
                    decoration: BoxDecoration(
                      color: priorityStripe(item.priority, p),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  child: Text(
                    _selected.isEmpty
                        ? 'Aucune aujourd\'hui'
                        : 'Valider mes ${_selected.length}',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
