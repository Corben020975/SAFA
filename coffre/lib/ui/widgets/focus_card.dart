import 'package:flutter/material.dart';

import '../../core/life_domain.dart';
import '../../data/database.dart';
import '../../data/enums.dart';
import '../item_actions.dart';
import '../theme.dart';

/// D'où vient l'élément (tag posé à la capture ou à l'import).
String? itemSource(Item item) {
  const names = {
    'notion': 'Notion',
    'outlook': 'Outlook',
    'gmail': 'Gmail',
    'teams': 'Teams',
    'whatsapp': 'WhatsApp',
    'sms': 'SMS',
    'web': 'le web',
  };
  for (final tag in item.tags) {
    if (names[tag] case final name?) return 'via $name';
  }
  return null;
}

/// Tag métier Notion (Réunion, Suivi…) s'il n'est pas déjà le contexte.
String? metierTag(Item item) {
  const known = {
    'réunion': 'Réunion',
    'reunion': 'Réunion',
    'appel': 'Appel',
    'suivi': 'Suivi',
    'autre': 'Autre',
  };
  for (final tag in item.tags) {
    if (known[tag.toLowerCase()] case final label?) {
      if (item.context != label) return label;
    }
  }
  return null;
}

Color priorityStripe(ItemPriority priority, Palette p) => switch (priority) {
  ItemPriority.urgent || ItemPriority.high => p.coral,
  ItemPriority.normal => p.sand,
  ItemPriority.low => p.faint,
};

/// Carte compacte des « 3 du jour » : un rond à cocher, un liseré de
/// priorité ; glisser à droite = fait, à gauche = plus tard.
class FocusCard extends StatelessWidget {
  const FocusCard({super.key, required this.item, required this.now});
  final Item item;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    final when = itemWhen(item, now);
    final overdue = when?.startsWith('En retard') ?? false;
    final fullTitle = item.content.trim().split('\n').first;
    final split = splitActionTitle(item.content);
    // Verbe en pastille seulement si le titre reste lisible sans lui
    // (todos Grok « Répondre à X — … »), pas pour « Appeler le médecin ».
    final showVerb =
        split.verb != null &&
        split.title.length >= 8 &&
        split.title != fullTitle;
    final meta = <InlineSpan>[];
    void add(String text, [Color? color]) {
      if (meta.isNotEmpty) meta.add(const TextSpan(text: ' · '));
      meta.add(
        TextSpan(
          text: text,
          style: color == null ? null : TextStyle(color: color),
        ),
      );
    }

    if (item.priority != ItemPriority.normal) add(item.priority.label);
    if (when != null) {
      add(overdue ? when.toLowerCase() : when, overdue ? p.coral : null);
    }
    if (item.status == ItemStatus.doing) add('en cours', p.blue);
    if (item.context != null) add(item.context!);
    if (metierTag(item) case final m?) add(m);
    if (itemSource(item) case final source?) add(source);

    final badge = statusBadgeFor(item);
    final radius = BorderRadius.circular(20);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('focus-${item.id}'),
        background: _swipe(
          p.sage,
          Icons.check,
          'Fait',
          Alignment.centerLeft,
          radius,
        ),
        secondaryBackground: _swipe(
          p.sand,
          Icons.schedule,
          'Plus tard',
          Alignment.centerRight,
          radius,
        ),
        confirmDismiss: (direction) async {
          if (direction == DismissDirection.startToEnd) {
            await ItemActions.toggleDone(context, item);
          } else {
            await ItemActions.later(context, item);
          }
          return false; // la liste se met à jour d'elle-même
        },
        child: Material(
          color: p.card,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(
              color: badge == 'Bloqué'
                  ? p.coral.withValues(alpha: 0.55)
                  : p.line,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => ItemActions.open(context, item),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    width: 4,
                    margin: const EdgeInsets.only(
                      left: 10,
                      top: 14,
                      bottom: 14,
                    ),
                    decoration: BoxDecoration(
                      color: priorityStripe(item.priority, p),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 2, right: 4),
                    child: IconButton(
                      tooltip: 'Fait',
                      onPressed: () => ItemActions.toggleDone(context, item),
                      icon: Icon(
                        Icons.radio_button_unchecked,
                        color: p.sage,
                        size: 28,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(0, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (showVerb || badge != null) ...[
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                if (showVerb) _MiniChip(split.verb!, p.sand, p),
                                if (badge != null)
                                  _MiniChip(
                                    badge,
                                    badge == 'Bloqué' ? p.coral : p.blue,
                                    p,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          Text(
                            showVerb ? split.title : fullTitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              height: 1.25,
                            ),
                          ),
                          if (meta.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text.rich(
                              TextSpan(children: meta),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: p.faint,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _swipe(
    Color color,
    IconData icon,
    String label,
    Alignment align,
    BorderRadius radius,
  ) => Container(
    alignment: align,
    padding: const EdgeInsets.symmetric(horizontal: 22),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.22),
      borderRadius: radius,
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
      ],
    ),
  );
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.text, this.color, this.p);
  final String text;
  final Color color;
  final Palette p;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.2,
      ),
    ),
  );
}
