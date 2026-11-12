import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_services.dart';
import '../../data/database.dart';
import '../../data/enums.dart';
import '../../services/day_focus.dart';
import '../../services/system_channel.dart';
import '../theme.dart';
import '../widgets/ai_sheet.dart';
import '../widgets/focus_card.dart';
import '../widgets/focus_picker.dart';
import 'banners.dart';
import 'day_timeline.dart';

/// Accueil : la journée en une frise et 3 priorités. Le reste attend.
class JourView extends StatefulWidget {
  const JourView({
    super.key,
    required this.onTryExample,
    required this.onOpenInbox,
  });

  /// Remplit la barre de capture avec un exemple (écran vide).
  final ValueChanged<String> onTryExample;

  /// Bascule vers Flux › Inbox.
  final VoidCallback onOpenInbox;

  @override
  State<JourView> createState() => _JourViewState();
}

class _JourViewState extends State<JourView> {
  late final AppServices _s = AppScope.of(context);
  late final Stream<List<Item>> _open = _s.db.watchOpen();
  late final AppLifecycleListener _lifecycle;
  late final Timer _tick;
  List<CalendarEvent> _events = const [];
  bool _allowed = true;
  bool _started = false;
  bool _savingFocus = false;

  static const _examples = [
    'Appeler le médecin demain à 9h',
    'Idée : un carnet de prompts pour l\'équipe',
    'Échéance le 15 octobre, dossier impôts',
  ];

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _loadEvents);
    // L'heure, le repère « maintenant » et l'agenda bougent : rafraîchir.
    _tick = Timer.periodic(const Duration(minutes: 1), (t) {
      if (!mounted) return;
      setState(() {});
      if (t.tick % 5 == 0) _loadEvents();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _s.settings.addListener(_loadEvents);
    _loadEvents();
  }

  @override
  void dispose() {
    _s.settings.removeListener(_loadEvents);
    _lifecycle.dispose();
    _tick.cancel();
    super.dispose();
  }

  /// Rendez-vous d'aujourd'hui et de demain (agenda du téléphone).
  Future<void> _loadEvents() async {
    if (!_s.settings.agendaEnabled) {
      if (mounted && _events.isNotEmpty) setState(() => _events = const []);
      return;
    }
    final allowed = await _s.system.hasCalendarPermission();
    if (!allowed) {
      if (mounted) setState(() => _allowed = false);
      return;
    }
    final now = DateTime.now();
    final events = await _s.system.calendarEvents(
      DateTime(now.year, now.month, now.day),
      DateTime(now.year, now.month, now.day + 2),
    );
    if (mounted) {
      setState(() {
        _allowed = true;
        _events = events;
      });
    }
  }

  Future<void> _allow() async {
    await _s.system.requestCalendarPermission();
    await _loadEvents();
  }

  /// Premier passage de la journée : la suggestion devient le choix du jour.
  void _rememberFocus(List<Item> open, DateTime now) {
    if (_savingFocus) return;
    _savingFocus = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await DayFocus.ensure(_s.settings, open, now);
      _savingFocus = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _s.settings,
      builder: (context, _) => StreamBuilder<List<Item>>(
        stream: _open,
        builder: (context, snapshot) {
          final open = snapshot.data ?? const <Item>[];
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final tomorrow = DateTime(now.year, now.month, now.day + 1);

          final chosen = DayFocus.chosen(_s.settings, open, now);
          if (chosen == null && snapshot.hasData && open.isNotEmpty) {
            _rememberFocus(open, now);
          }
          final focus = chosen ?? DayFocus.suggest(open, now);
          final focusIds = {for (final i in focus) i.id};
          final tasks = open.where((i) => i.kind == ItemKind.task).toList();
          final overdue = tasks
              .where((i) => i.remindAt != null && i.remindAt!.isBefore(now))
              .length;
          final waiting = tasks.where((i) => !focusIds.contains(i.id)).length;
          final inbox = open.where((i) => i.inbox).length;
          final reminders = open
              .where(
                (i) =>
                    i.remindAt != null &&
                    !i.remindAt!.isBefore(today) &&
                    i.remindAt!.isBefore(tomorrow),
              )
              .toList();
          final todayEvents = _events
              .where((e) => e.begin.isBefore(tomorrow) && e.end.isAfter(today))
              .toList();
          final tomorrowEvents = _events
              .where((e) => !e.begin.isBefore(tomorrow))
              .length;
          final allDone =
              chosen != null &&
              chosen.isEmpty &&
              _s.settings.focusIds.isNotEmpty;

          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: _header(
                  context,
                  now: now,
                  open: open,
                  focus: focus,
                  allDone: allDone,
                  events: todayEvents.length,
                  overdue: overdue,
                  waiting: waiting,
                ),
              ),
              const SliverToBoxAdapter(child: ReminderHealthBanner()),
              const SliverToBoxAdapter(child: SetAsideBanner()),
              if (snapshot.hasData && open.isEmpty && todayEvents.isEmpty)
                SliverToBoxAdapter(child: _empty(context))
              else ...[
                _title(context, 'Ta journée', 'agenda + rappels'),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverToBoxAdapter(
                    child: DayTimeline(
                      now: now,
                      events: todayEvents,
                      reminders: reminders,
                      agendaOn: _s.settings.agendaEnabled,
                      allowed: _allowed,
                      onAllow: _allow,
                      tomorrowEvents: tomorrowEvents,
                    ),
                  ),
                ),
                _title(
                  context,
                  'Les 3 du jour',
                  chosen != null ? 'choisies ce matin' : 'suggestion',
                  action: tasks.isEmpty
                      ? null
                      : TextButton(
                          onPressed: () => showFocusPicker(context, open),
                          child: const Text('Changer'),
                        ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.list(
                    children: [
                      if (focus.isEmpty)
                        _doneCard(context, allDone: allDone, open: open)
                      else ...[
                        for (final item in focus)
                          FocusCard(
                            key: ValueKey('focus-${item.id}'),
                            item: item,
                            now: now,
                          ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Text(
                            'Glisse à droite : fait · à gauche : plus tard',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: Palette.of(context).faint),
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _Tile(
                              count: waiting,
                              label: waiting == 1
                                  ? 'autre tâche'
                                  : 'autres tâches',
                              action: 'Changer mes 3',
                              onTap: () => showFocusPicker(context, open),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _Tile(
                              count: inbox,
                              label: 'dans l\'Inbox',
                              action: 'Trier',
                              onTap: widget.onOpenInbox,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          );
        },
      ),
    );
  }

  Widget _header(
    BuildContext context, {
    required DateTime now,
    required List<Item> open,
    required List<Item> focus,
    required bool allDone,
    required int events,
    required int overdue,
    required int waiting,
  }) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    final date = DateFormat('EEEE d MMMM', 'fr').format(now);
    final headline = switch (focus.length) {
      _ when allDone => 'Bravo, c\'est fait.',
      0 when open.isEmpty => 'Journée libre.',
      0 => 'Choisis tes 3.',
      1 => 'Ta priorité.',
      final n => 'Tes $n priorités.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 8, 8, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Coffre', style: displayStyle(context, 18, color: p.muted)),
              const Spacer(),
              if (open.isNotEmpty)
                IconButton(
                  tooltip: 'Brief du jour par l\'IA',
                  onPressed: () => showDayBriefSheet(context, open),
                  icon: const Icon(Icons.auto_awesome_outlined),
                ),
              IconButton(
                tooltip: 'Réglages',
                onPressed: () => Navigator.of(context).pushNamed('/settings'),
                icon: const Icon(Icons.settings_outlined),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${date[0].toUpperCase()}${date.substring(1)}',
            style: theme.textTheme.bodyMedium?.copyWith(color: p.muted),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Text(headline, style: displayStyle(context, 36)),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (events > 0)
                _Pill(
                  events == 1 ? '1 rendez-vous' : '$events rendez-vous',
                  p.blue,
                ),
              if (overdue > 0) _Pill('$overdue en retard', p.coral),
              if (waiting > 0) _Pill('$waiting en attente', p.muted),
            ],
          ),
        ],
      ),
    );
  }

  Widget _title(
    BuildContext context,
    String title,
    String hint, {
    Widget? action,
  }) {
    final p = Palette.of(context);
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(22, 22, 12, 10),
      sliver: SliverToBoxAdapter(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                title,
                overflow: TextOverflow.ellipsis,
                style: displayStyle(context, 20),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                hint,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: p.faint),
              ),
            ),
            ?action,
          ],
        ),
      ),
    );
  }

  Widget _doneCard(
    BuildContext context, {
    required bool allDone,
    required List<Item> open,
  }) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    final hasTasks = open.any((i) => i.kind == ItemKind.task);
    return Material(
      color: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              allDone
                  ? 'Tes priorités du jour sont faites.'
                  : 'Aucune tâche à mettre en avant.',
              style: theme.textTheme.titleMedium,
            ),
            if (hasTasks)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => showFocusPicker(context, open),
                  child: const Text('En choisir d\'autres'),
                ),
              ),
          ],
        ),
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

class _Pill extends StatelessWidget {
  const _Pill(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color),
    ),
  );
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.count,
    required this.label,
    required this.action,
    required this.onTap,
  });
  final int count;
  final String label;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    return Material(
      color: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: p.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$count', style: displayStyle(context, 24)),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: p.muted),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      action,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: p.sage,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward, size: 16, color: p.sage),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
