import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../../data/enums.dart';
import '../item_actions.dart';
import '../theme.dart';

/// Ligne compacte de la vue Flux : rond « fait » à gauche, une ligne d'infos.
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
    final p = Palette.of(context);
    final done = item.status == ItemStatus.done;
    final title = item.content.trim().split('\n').first;
    final when = itemWhen(item, DateTime.now());
    final overdue = when?.startsWith('En retard') ?? false;
    final accent = priorityColor(item.priority, scheme);
    final meta = [
      itemMeta(item),
      if (item.status == ItemStatus.doing) 'En cours',
      ...item.tags.take(2).map((t) => '#$t'),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 18, 6),
        child: Row(
          children: [
            // Zone tactile de 48 dp : « fait » en un geste.
            IconButton(
              iconSize: 28,
              tooltip: done ? 'Réactiver' : 'Marquer fait',
              onPressed: onToggleDone,
              icon: Icon(
                done ? Icons.check_circle : Icons.radio_button_unchecked,
                color: done
                    ? p.sage
                    : kindColor(item.kind, scheme).withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(width: 2),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        decoration: done ? TextDecoration.lineThrough : null,
                        color: done ? p.muted : p.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: meta),
                          if (when != null)
                            TextSpan(
                              text: '  ·  $when',
                              style: TextStyle(
                                color: overdue ? p.coral : p.sage,
                              ),
                            ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: p.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (accent != null)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Tooltip(
                  message: 'Priorité ${item.priority.label.toLowerCase()}',
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
