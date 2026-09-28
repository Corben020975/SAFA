import 'package:flutter/material.dart';

import '../../data/database.dart';
import '../item_actions.dart';
import '../theme.dart';

/// Carte de la vue Jour : lecture en un coup d'œil, « Fait » et « Plus tard »
/// sous le pouce, texte d'origine (« Brut ») à la demande.
class ItemCard extends StatefulWidget {
  const ItemCard({super.key, required this.item, required this.now});
  final Item item;
  final DateTime now;

  @override
  State<ItemCard> createState() => _ItemCardState();
}

class _ItemCardState extends State<ItemCard> {
  bool _showRaw = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final p = Palette.of(context);
    final lines = item.content.trim().split('\n');
    final extra = lines.skip(1).join(' ').trim();
    final when = itemWhen(item, widget.now);
    final overdue = when?.startsWith('En retard') ?? false;
    final accent = priorityColor(item.priority, scheme);
    final raw = item.raw?.trim();
    final hasRaw = raw != null && raw.isNotEmpty && raw != item.content.trim();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => ItemActions.open(context, item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    kindIcon(item.kind),
                    size: 16,
                    color: kindColor(item.kind, scheme),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      itemMeta(item),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: p.muted,
                      ),
                    ),
                  ),
                  if (accent != null) _Tag(item.priority.label, accent),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                lines.first,
                style: theme.textTheme.titleMedium,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              if (extra.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  extra,
                  style: theme.textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              if (when != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(
                      overdue ? Icons.alarm_off : Icons.alarm,
                      size: 16,
                      color: overdue ? p.coral : p.sage,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      when,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: overdue ? p.coral : p.sage,
                      ),
                    ),
                    if (item.preAlert) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.notifications_active_outlined,
                        size: 15,
                        color: p.muted,
                      ),
                    ],
                  ],
                ),
              ],
              if (_showRaw && hasRaw) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: p.field,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    raw,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => ItemActions.toggleDone(context, item),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Fait'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => ItemActions.later(context, item),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: const Text('Plus tard'),
                  ),
                  if (hasRaw)
                    TextButton(
                      onPressed: () => setState(() => _showRaw = !_showRaw),
                      child: Text(_showRaw ? 'Masquer' : 'Brut'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: color, fontWeight: FontWeight.w600),
    ),
  );
}
