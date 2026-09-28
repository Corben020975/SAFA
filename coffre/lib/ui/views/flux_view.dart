import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../data/database.dart';
import '../../data/enums.dart';
import '../item_actions.dart';
import '../theme.dart';
import '../widgets/item_tile.dart';

/// Tout le contenu : Inbox, filtres, recherche, tri, gestes de balayage.
class FluxView extends StatefulWidget {
  const FluxView({super.key});

  @override
  State<FluxView> createState() => _FluxViewState();
}

class _FluxViewState extends State<FluxView> {
  late final AppServices _s = AppScope.of(context);
  late final Stream<Map<InboxFilter, int>> _counts = _s.db.watchCounts();
  late Stream<List<Item>> _items;

  InboxFilter _filter = InboxFilter.inbox;
  String _query = '';
  final _search = TextEditingController();
  bool _started = false;

  /// Éléments glissés : masqués tout de suite, avant que le flux Drift
  /// ne se mette à jour (évite l'erreur « dismissed Dismissible still in tree »).
  final Set<int> _hidden = {};

  bool get _searching => _query.trim().isNotEmpty;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Appelé aussi à chaque animation du clavier (MediaQuery) : une seule fois.
    if (_started) return;
    _started = true;
    _items = _buildStream();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Stream<List<Item>> _buildStream() => _searching
      ? _s.db.watchSearch(_query)
      : _s.db.watchList(_filter, _s.settings.sort);

  void _rebuild() => setState(() {
    _hidden.clear();
    _items = _buildStream();
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return CustomScrollView(
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 12, 8, 0),
              child: Row(
                children: [
                  Text('Flux', style: displayStyle(context, 34)),
                  const Spacer(),
                  PopupMenuButton<SortMode>(
                    tooltip: 'Trier',
                    icon: const Icon(Icons.sort),
                    initialValue: _s.settings.sort,
                    onSelected: (mode) async {
                      await _s.settings.setSort(mode);
                      _rebuild();
                    },
                    itemBuilder: (_) => [
                      for (final mode in SortMode.values)
                        CheckedPopupMenuItem(
                          value: mode,
                          checked: mode == _s.settings.sort,
                          child: Text(mode.label),
                        ),
                    ],
                  ),
                  IconButton(
                    tooltip: 'Réglages',
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/settings'),
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Chercher dans tout le coffre',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _search.clear();
                          _query = '';
                          _rebuild();
                        },
                      )
                    : null,
              ),
              onChanged: (value) {
                _query = value;
                _rebuild();
              },
            ),
          ),
        ),
        if (!_searching) SliverToBoxAdapter(child: _filterBar()),
        StreamBuilder<List<Item>>(
          stream: _items,
          builder: (context, snapshot) {
            final items = (snapshot.data ?? const <Item>[])
                .where((i) => !_hidden.contains(i.id))
                .toList();
            if (!snapshot.hasData) {
              return const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (items.isEmpty) {
              return SliverFillRemaining(
                hasScrollBody: false,
                child: _EmptyState(filter: _filter, searching: _searching),
              );
            }
            return SliverPadding(
              padding: const EdgeInsets.only(top: 6),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) =>
                    Divider(indent: 60, endIndent: 18, color: p.line),
                itemBuilder: (context, index) => _row(items[index]),
              ),
            );
          },
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _row(Item item) {
    final tile = ItemTile(
      item: item,
      onTap: () => ItemActions.open(context, item),
      onToggleDone: () => ItemActions.toggleDone(context, item),
    );
    if (_searching) return tile;
    final scheme = Theme.of(context).colorScheme;
    final canArchive = _filter == InboxFilter.inbox;
    final done = item.status == ItemStatus.done;
    return Dismissible(
      key: ValueKey('item-${item.id}'),
      direction: canArchive
          ? DismissDirection.horizontal
          : DismissDirection.startToEnd,
      background: _swipe(
        done ? Icons.undo : Icons.check,
        done ? 'Réactiver' : 'Fait',
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Alignment.centerLeft,
      ),
      secondaryBackground: canArchive
          ? _swipe(
              Icons.inventory_2_outlined,
              'Classer',
              scheme.secondaryContainer,
              scheme.onSecondaryContainer,
              Alignment.centerRight,
            )
          : null,
      onDismissed: (direction) {
        setState(() => _hidden.add(item.id));
        if (direction == DismissDirection.startToEnd) {
          ItemActions.toggleDone(context, item);
        } else {
          ItemActions.archive(context, item);
        }
      },
      child: tile,
    );
  }

  Widget _swipe(
    IconData icon,
    String label,
    Color bg,
    Color fg,
    Alignment alignment,
  ) {
    final content = [
      Icon(icon, color: fg),
      const SizedBox(width: 8),
      Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w600),
      ),
    ];
    return Container(
      color: bg,
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: alignment == Alignment.centerLeft
            ? content
            : content.reversed.toList(),
      ),
    );
  }

  Widget _filterBar() {
    return StreamBuilder<Map<InboxFilter, int>>(
      stream: _counts,
      builder: (context, snapshot) {
        final counts = snapshot.data ?? const {};
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              for (final f in InboxFilter.values)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(
                      (counts[f] ?? 0) > 0 && f != InboxFilter.done
                          ? '${f.label} · ${counts[f]}'
                          : f.label,
                    ),
                    selected: f == _filter,
                    onSelected: (_) {
                      _filter = f;
                      _rebuild();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.searching});
  final InboxFilter filter;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = searching
        ? (Icons.search_off, 'Aucun résultat.')
        : switch (filter) {
            InboxFilter.inbox => (Icons.inbox_outlined, 'Inbox vide.'),
            InboxFilter.reminders => (Icons.alarm_off, 'Aucun rappel à venir.'),
            InboxFilter.done => (
              Icons.check_circle_outline,
              'Rien de terminé pour l\'instant.',
            ),
            _ => (Icons.folder_open, 'Rien ici pour l\'instant.'),
          };
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: p.faint),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: displayStyle(context, 20, color: p.muted),
          ),
        ],
      ),
    );
  }
}
