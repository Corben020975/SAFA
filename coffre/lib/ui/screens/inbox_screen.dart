import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../data/database.dart';
import '../../data/enums.dart';
import '../widgets/item_tile.dart';
import 'capture_screen.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key});

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  late final AppServices _s = AppScope.of(context);
  late final AppLifecycleListener _lifecycle;

  InboxFilter _filter = InboxFilter.inbox;
  bool _searching = false;
  String _query = '';
  final _searchController = TextEditingController();

  /// Éléments glissés : masqués tout de suite, avant que le flux Drift
  /// ne se mette à jour (évite l'erreur « dismissed Dismissible still in tree »).
  final Set<int> _hidden = {};

  late Stream<List<Item>> _items;
  late final Stream<Map<InboxFilter, int>> _counts = _s.db.watchCounts();

  bool _remindersHealthy = true;
  bool _setAsideDismissed = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _checkReminderHealth);
  }

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Appelé aussi à chaque animation du clavier (MediaQuery) : une seule fois.
    if (_started) return;
    _started = true;
    _items = _buildStream();
    _checkReminderHealth();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<Item>> _buildStream() => _searching && _query.trim().isNotEmpty
      ? _s.db.watchSearch(_query)
      : _s.db.watchList(_filter, _s.settings.sort);

  void _rebuildStream() => setState(() {
    _hidden.clear();
    _items = _buildStream();
  });

  Future<void> _checkReminderHealth() async {
    final ok =
        await _s.notifications.areEnabled() &&
        await _s.notifications.canScheduleExact() &&
        await _s.system.isIgnoringBatteryOptimizations();
    if (mounted && ok != _remindersHealthy) setState(() => _remindersHealthy = ok);
  }

  Future<void> _toggleDone(Item item) async {
    final wasDone = item.status == ItemStatus.done;
    final updated = await _s.db.setStatus(
      item.id,
      wasDone ? ItemStatus.todo : ItemStatus.done,
    );
    if (updated != null) await _s.notifications.schedule(updated);
    if (!mounted) return;
    _snack(
      wasDone ? 'Réactivé' : 'Marqué fait',
      onUndo: () async {
        final restored = await _s.db.setStatus(item.id, item.status);
        if (restored != null) await _s.notifications.schedule(restored);
        setState(() => _hidden.remove(item.id));
      },
    );
  }

  Future<void> _archive(Item item) async {
    await _s.db.setInbox(item.id, false);
    if (!mounted) return;
    _snack(
      'Classé (retrouvable dans ${item.kind.plural})',
      onUndo: () async {
        await _s.db.setInbox(item.id, true);
        setState(() => _hidden.remove(item.id));
      },
    );
  }

  void _snack(String text, {VoidCallback? onUndo}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          action: onUndo == null
              ? null
              : SnackBarAction(label: 'Annuler', onPressed: onUndo),
        ),
      );
  }

  void _openCapture({bool voice = false}) {
    Navigator.of(context).pushNamed(
      '/capture',
      arguments: CaptureArgs(startWithVoice: voice),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _searching
        ? 'Recherche'
        : (_filter == InboxFilter.inbox ? 'Coffre' : _filter.label);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Grand titre façon One UI : le contenu commence plus bas,
          // à portée de pouce sur un grand écran.
          SliverAppBar.large(title: Text(title)),
          if (_s.setAsideDbFile != null && !_setAsideDismissed)
            SliverToBoxAdapter(child: _setAsideBanner(scheme)),
          if (!_remindersHealthy && !_searching)
            SliverToBoxAdapter(child: _healthBanner(scheme)),
          if (!_searching) SliverToBoxAdapter(child: _filterBar()),
          StreamBuilder<List<Item>>(
            stream: _items,
            builder: (context, snapshot) {
              final items = (snapshot.data ?? const <Item>[])
                  .where((i) => !_hidden.contains(i.id))
                  .toList();
              if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData) {
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
              return SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(height: 1, indent: 60),
                itemBuilder: (context, index) => _row(items[index], scheme),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
      floatingActionButton: _searching
          ? null
          : FloatingActionButton.extended(
              onPressed: _openCapture,
              icon: const Icon(Icons.add, size: 28),
              label: const Text('Ajouter'),
              elevation: 0,
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endContained,
      // Remonte la barre au-dessus du clavier en mode recherche.
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _searching ? _searchBar() : _bottomBar(),
      ),
    );
  }

  Widget _row(Item item, ColorScheme scheme) {
    final tile = ItemTile(
      item: item,
      onTap: () => Navigator.of(context).pushNamed('/item', arguments: item.id),
      onToggleDone: () => _toggleDone(item),
    );
    if (_searching) return tile;
    final canArchive = _filter == InboxFilter.inbox;
    final done = item.status == ItemStatus.done;
    return Dismissible(
      key: ValueKey('item-${item.id}'),
      direction: canArchive
          ? DismissDirection.horizontal
          : DismissDirection.startToEnd,
      background: _swipeBackground(
        done ? Icons.undo : Icons.check,
        done ? 'Réactiver' : 'Fait',
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        Alignment.centerLeft,
      ),
      secondaryBackground: canArchive
          ? _swipeBackground(
              Icons.inventory_2_outlined,
              'Classer',
              scheme.tertiaryContainer,
              scheme.onTertiaryContainer,
              Alignment.centerRight,
            )
          : null,
      onDismissed: (direction) {
        setState(() => _hidden.add(item.id));
        if (direction == DismissDirection.startToEnd) {
          _toggleDone(item);
        } else {
          _archive(item);
        }
      },
      child: tile,
    );
  }

  Widget _swipeBackground(
    IconData icon,
    String label,
    Color bg,
    Color fg,
    Alignment alignment,
  ) {
    final content = [
      Icon(icon, color: fg),
      const SizedBox(width: 8),
      Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
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
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
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
                      _rebuildStream();
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _bottomBar() {
    return BottomAppBar(
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'Dicter une capture',
            iconSize: 28,
            onPressed: () => _openCapture(voice: true),
            icon: const Icon(Icons.mic),
          ),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Rechercher',
            onPressed: () => setState(() => _searching = true),
            icon: const Icon(Icons.search),
          ),
          PopupMenuButton<SortMode>(
            tooltip: 'Trier',
            icon: const Icon(Icons.sort),
            initialValue: _s.settings.sort,
            onSelected: (mode) async {
              await _s.settings.setSort(mode);
              _rebuildStream();
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
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }

  Widget _searchBar() {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: 'Chercher dans tout le coffre',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (value) {
                    _query = value;
                    _rebuildStream();
                  },
                ),
              ),
              IconButton(
                tooltip: 'Fermer la recherche',
                onPressed: () {
                  _searchController.clear();
                  _query = '';
                  _searching = false;
                  _rebuildStream();
                },
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _healthBanner(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        color: scheme.errorContainer,
        child: ListTile(
          leading: Icon(Icons.notifications_off_outlined, color: scheme.onErrorContainer),
          title: Text(
            'Rappels pas encore fiables',
            style: TextStyle(color: scheme.onErrorContainer),
          ),
          subtitle: Text(
            'Un réglage Samsung manque. Touche pour corriger.',
            style: TextStyle(color: scheme.onErrorContainer),
          ),
          onTap: () async {
            await Navigator.of(context).pushNamed('/onboarding');
            _checkReminderHealth();
          },
        ),
      ),
    );
  }

  Widget _setAsideBanner(ColorScheme scheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        color: scheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ancienne base illisible',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                'La clé de chiffrement a été perdue (restauration système, '
                'changement de téléphone…). L\'ancien fichier est conservé '
                '(${_s.setAsideDbFile}). Restaure ta dernière sauvegarde JSON '
                'depuis Réglages.',
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => setState(() => _setAsideDismissed = true),
                    child: const Text('Compris'),
                  ),
                  FilledButton.tonal(
                    onPressed: () => Navigator.of(context).pushNamed('/settings'),
                    child: const Text('Réglages'),
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter, required this.searching});
  final InboxFilter filter;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = searching
        ? (Icons.search_off, 'Aucun résultat.')
        : switch (filter) {
            InboxFilter.inbox => (
              Icons.inbox_outlined,
              'Inbox vide.\nTouche « Ajouter » ou le micro pour capturer.',
            ),
            InboxFilter.reminders => (Icons.alarm_off, 'Aucun rappel à venir.'),
            InboxFilter.done => (Icons.check_circle_outline, 'Rien de terminé pour l\'instant.'),
            _ => (Icons.folder_open, 'Rien ici pour l\'instant.'),
          };
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 56, color: color),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}
