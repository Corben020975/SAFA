import 'package:flutter/material.dart';

import '../../core/date_labels.dart';
import '../../data/database.dart';
import '../../data/enums.dart';
import '../theme.dart';

class ItemTile extends StatelessWidget {
  const ItemTile({
    super.key,
    required this.item,
    required this.onTap,
    required this.onToggleDone,
  });

  final Item item;
  final VoidCallback onTap;
  final VoidCallback onToggleDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final done = item.status == ItemStatus.done;
    final lines = item.content.trim().split('\n');
    final title = lines.first;
    final preview = lines.skip(1).join(' ').trim();
    final color = kindColor(item.kind, scheme);
    final reminder = item.remindAt;
    final overdue = !done && reminder != null && reminder.isBefore(DateTime.now());

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Zone tactile de 48 dp minimum : « fait » en un geste.
            IconButton(
              iconSize: 30,
              tooltip: done ? 'Réactiver' : 'Marquer fait',
              onPressed: onToggleDone,
              icon: Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done ? scheme.primary : color,
              ),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? scheme.onSurfaceVariant : null,
                      ),
                    ),
                    if (preview.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _Pill(icon: kindIcon(item.kind), text: item.kind.label, color: color),
                        if (item.status == ItemStatus.doing)
                          _Pill(icon: Icons.timelapse, text: 'En cours', color: scheme.secondary),
                        if (item.priority == ItemPriority.high)
                          _Pill(icon: Icons.flag, text: 'Haute', color: scheme.error),
                        if (item.priority == ItemPriority.low)
                          _Pill(icon: Icons.south, text: 'Basse', color: scheme.outline),
                        if (reminder != null)
                          _Pill(
                            icon: overdue ? Icons.alarm_off : Icons.alarm,
                            text: formatReminder(reminder),
                            color: overdue ? scheme.error : scheme.primary,
                          ),
                        for (final tag in item.tags.take(3))
                          _Pill(text: '#$tag', color: scheme.outline),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({this.icon, required this.text, required this.color});
  final IconData? icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
