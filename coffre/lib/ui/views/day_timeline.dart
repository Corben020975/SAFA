import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_services.dart';
import '../../data/database.dart';
import '../../services/system_channel.dart';
import '../item_actions.dart';
import '../theme.dart';

class _Entry {
  const _Entry({
    required this.start,
    this.end,
    required this.title,
    this.subtitle,
    this.event = false,
    this.allDay = false,
    this.onTap,
  });
  final DateTime start;
  final DateTime? end;
  final String title;
  final String? subtitle;
  final bool event;
  final bool allDay;
  final VoidCallback? onTap;

  DateTime get finish => end ?? start.add(const Duration(minutes: 15));
}

/// « Ta journée » : rendez-vous et rappels du jour sur une seule frise,
/// avec les créneaux libres et un repère pour l'heure qu'il est.
class DayTimeline extends StatelessWidget {
  const DayTimeline({
    super.key,
    required this.now,
    required this.events,
    required this.reminders,
    required this.agendaOn,
    required this.allowed,
    required this.onAllow,
    this.tomorrowEvents = 0,
  });

  final DateTime now;
  final List<CalendarEvent> events;
  final List<Item> reminders;
  final bool agendaOn;
  final bool allowed;
  final VoidCallback onAllow;
  final int tomorrowEvents;

  static final _hm = DateFormat.Hm('fr');

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = Palette.of(context);
    final theme = Theme.of(context);

    final entries =
        <_Entry>[
          for (final e in events)
            _Entry(
              start: e.begin,
              end: e.end,
              title: e.title,
              subtitle: e.allDay
                  ? 'Journée${e.location == null ? '' : ' · ${e.location}'}'
                  : '${_hm.format(e.begin)} – ${_hm.format(e.end)}'
                        '${e.location == null ? '' : ' · ${e.location}'}',
              event: true,
              allDay: e.allDay,
              onTap: () => s.system.openEvent(e.id),
            ),
          for (final item in reminders)
            _Entry(
              start: item.remindAt!,
              title: item.content.trim().split('\n').first,
              subtitle: [
                'Rappel',
                if (item.context != null) item.context!,
              ].join(' · '),
              onTap: () => ItemActions.open(context, item),
            ),
        ]..sort((a, b) {
          if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
          return a.start.compareTo(b.start);
        });

    final rows = <Widget>[];
    var nowShown = false;
    DateTime? cursor;
    for (final entry in entries) {
      if (!entry.allDay) {
        if (!nowShown && entry.start.isAfter(now) && rows.isNotEmpty) {
          rows.add(_NowMarker(time: _hm.format(now)));
          nowShown = true;
        }
        // Créneau libre d'au moins une heure, à venir.
        final from = cursor == null || cursor.isBefore(now) ? now : cursor;
        if (cursor != null && entry.start.difference(from).inMinutes >= 60) {
          rows.add(
            _Row(
              // Juste après le repère « maintenant » : pas d'heure en double.
              time: from == now ? '' : _hm.format(from),
              free: 'Libre jusqu\'à ${_hm.format(entry.start)}',
            ),
          );
        }
        if (cursor == null || entry.finish.isAfter(cursor)) {
          cursor = entry.finish;
        }
      }
      rows.add(
        _Row(
          time: entry.allDay ? 'Journée' : _hm.format(entry.start),
          entry: entry,
          past: !entry.allDay && entry.finish.isBefore(now),
        ),
      );
    }

    Widget body;
    if (entries.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              agendaOn
                  ? 'Rien de prévu aujourd\'hui.'
                  : 'Aucun rappel aujourd\'hui.',
              style: theme.textTheme.bodyLarge?.copyWith(color: p.muted),
            ),
            if (agendaOn && !allowed)
              TextButton.icon(
                onPressed: onAllow,
                icon: const Icon(Icons.lock_open, size: 18),
                label: const Text('Autoriser l\'accès à l\'agenda'),
              ),
          ],
        ),
      );
    } else {
      body = Column(children: rows);
    }

    return Material(
      color: p.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            body,
            if (tomorrowEvents > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 0, 6),
                child: Text(
                  tomorrowEvents == 1
                      ? 'Demain : 1 rendez-vous'
                      : 'Demain : $tomorrowEvents rendez-vous',
                  style: theme.textTheme.bodySmall?.copyWith(color: p.faint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.time, this.entry, this.free, this.past = false});
  final String time;
  final _Entry? entry;
  final String? free;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    final e = entry;
    final dotColor = e == null ? null : (e.event ? p.blue : p.sage);

    final Widget content;
    if (e == null) {
      content = Padding(
        padding: const EdgeInsets.only(top: 1, bottom: 14),
        child: Text(
          free!,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: p.faint,
            fontStyle: FontStyle.italic,
          ),
        ),
      );
    } else {
      final texts = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            e.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(height: 1.25),
          ),
          if (e.subtitle != null)
            Text(
              e.subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: p.faint),
            ),
        ],
      );
      content = Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: InkWell(
          onTap: e.onTap,
          borderRadius: BorderRadius.circular(10),
          child: e.event
              ? Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
                  decoration: BoxDecoration(
                    color: p.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border(left: BorderSide(color: p.blue, width: 3)),
                  ),
                  child: texts,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: texts,
                ),
        ),
      );
    }

    return Opacity(
      opacity: past ? 0.45 : 1,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 52,
              child: Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Text(
                  time,
                  textAlign: TextAlign.right,
                  style: theme.textTheme.labelMedium?.copyWith(color: p.muted),
                ),
              ),
            ),
            SizedBox(
              width: 16,
              child: Column(
                children: [
                  const SizedBox(height: 5),
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      shape: BoxShape.circle,
                      border: dotColor == null
                          ? Border.all(color: p.faint, width: 1.5)
                          : null,
                    ),
                  ),
                  Expanded(child: Container(width: 2, color: p.line)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class _NowMarker extends StatelessWidget {
  const _NowMarker({required this.time});
  final String time;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                time,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: p.coral,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(color: p.coral, shape: BoxShape.circle),
          ),
          Expanded(
            child: Container(
              height: 2,
              decoration: BoxDecoration(
                color: p.coral.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
