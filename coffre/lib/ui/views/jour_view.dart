import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_services.dart';
import '../../data/database.dart';
import '../../services/day_board.dart';
import '../theme.dart';
import '../widgets/item_card.dart';
import '../widgets/ai_sheet.dart';
import 'agenda_section.dart';
import 'banners.dart';

/// Accueil : ce qui compte maintenant, aujourd'hui, cette semaine.
class JourView extends StatefulWidget {
  const JourView({super.key, required this.onTryExample});

  /// Remplit la barre de capture avec un exemple (écran vide).
  final ValueChanged<String> onTryExample;

  @override
  State<JourView> createState() => _JourViewState();
}

class _JourViewState extends State<JourView> {
  late final AppServices _s = AppScope.of(context);
  late final Stream<List<Item>> _open = _s.db.watchOpen();
  late final Timer _tick;

  static const _examples = [
    'Appeler le médecin demain à 9h',
    'Idée : un carnet de prompts pour l\'équipe',
    'Échéance le 15 octobre, dossier impôts',
  ];

  @override
  void initState() {
    super.initState();
    // Les rubriques dépendent de l'heure : on recalcule chaque minute.
    _tick = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = Theme.of(context);

    return StreamBuilder<List<Item>>(
      stream: _open,
      builder: (context, snapshot) {
        final now = DateTime.now();
        final board = DayBoard.compute(snapshot.data ?? const [], now);
        final date = DateFormat('EEEE d MMMM', 'fr').format(now);
        final count = board.openCount;

        return CustomScrollView(
          slivers: [
            SliverSafeArea(
              bottom: false,
              sliver: SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 12, 8, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Coffre',
                            style: displayStyle(context, 18, color: p.muted),
                          ),
                          const Spacer(),
                          if (!board.isEmpty)
                            IconButton(
                              tooltip: 'Brief du jour par l\'IA',
                              onPressed: () => showDayBriefSheet(
                                context,
                                snapshot.data ?? const [],
                              ),
                              icon: const Icon(Icons.auto_awesome_outlined),
                            ),
                          IconButton(
                            tooltip: 'Réglages',
                            onPressed: () =>
                                Navigator.of(context).pushNamed('/settings'),
                            icon: const Icon(Icons.settings_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '${date[0].toUpperCase()}${date.substring(1)}'
                        '${count > 0 ? ' · $count en cours' : ''}',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: Text(
                          board.headline,
                          style: displayStyle(context, 34),
                        ),
                      ),
                      if (!board.isEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          board.laterLine,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: p.muted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: ReminderHealthBanner()),
            SliverToBoxAdapter(
              child: ListenableBuilder(
                listenable: _s.settings,
                builder: (context, _) => _s.settings.agendaEnabled
                    ? const AgendaSection()
                    : const SizedBox.shrink(),
              ),
            ),
            const SliverToBoxAdapter(child: SetAsideBanner()),
            if (board.isEmpty)
              SliverToBoxAdapter(child: _empty(context))
            else ...[
              _section(context, 'Maintenant', board.soonItems, now),
              _section(context, 'Aujourd\'hui', board.todayItems, now),
              _section(context, 'Cette semaine', board.nextItems, now, max: 6),
              _section(context, 'Sans date', board.undatedItems, now, max: 3),
              if (board.spark != null)
                _section(context, 'À ne pas perdre', [board.spark!], now),
            ],
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }

  Widget _section(
    BuildContext context,
    String title,
    List<Item> items,
    DateTime now, {
    int? max,
  }) {
    if (items.isEmpty) {
      return const SliverToBoxAdapter(child: SizedBox.shrink());
    }
    final p = Palette.of(context);
    final shown = max == null ? items : items.take(max).toList();
    final hidden = items.length - shown.length;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      sliver: SliverList.list(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    style: displayStyle(context, 20),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${items.length}',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: p.faint),
                ),
              ],
            ),
          ),
          for (final item in shown)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ItemCard(
                key: ValueKey('card-${item.id}'),
                item: item,
                now: now,
              ),
            ),
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
              child: Text(
                '+ $hidden autre${hidden > 1 ? 's' : ''} dans Flux',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Écris ou dicte en bas de l\'écran. Coffre devine le type, la date et le contexte.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 18),
          for (final example in _examples)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 4,
                  ),
                  title: Text(example),
                  trailing: const Icon(Icons.north_west, size: 18),
                  onTap: () => widget.onTryExample(example),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
