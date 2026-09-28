import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_services.dart';
import '../../core/date_labels.dart';
import '../../services/system_channel.dart';
import '../theme.dart';

/// Rendez-vous d'aujourd'hui et de demain, lus dans l'agenda du téléphone
/// (Google Agenda synchronisé). Lecture seule ; un tap ouvre l'événement.
class AgendaSection extends StatefulWidget {
  const AgendaSection({super.key});

  @override
  State<AgendaSection> createState() => _AgendaSectionState();
}

class _AgendaSectionState extends State<AgendaSection> {
  late final AppServices _s = AppScope.of(context);
  late final AppLifecycleListener _lifecycle;
  Timer? _timer;
  List<CalendarEvent>? _events;
  bool _allowed = true;
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _load);
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => _load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
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
        _events = events.where((e) => e.end.isAfter(now)).toList();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    final events = _events;

    Widget body;
    if (!_allowed) {
      body = TextButton.icon(
        onPressed: () async {
          await _s.system.requestCalendarPermission();
          _load();
        },
        icon: const Icon(Icons.lock_open),
        label: const Text('Autoriser l\'accès à l\'agenda'),
      );
    } else if (events == null) {
      body = const SizedBox(height: 8);
    } else if (events.isEmpty) {
      body = Text(
        'Rien à l\'agenda aujourd\'hui ni demain.',
        style: theme.textTheme.bodyMedium,
      );
    } else {
      final now = DateTime.now();
      final rows = <Widget>[];
      int? lastDay;
      for (final e in events.take(8)) {
        final day = calendarDaysBetween(now, e.begin).clamp(0, 1);
        if (day != lastDay) {
          lastDay = day;
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: rows.isEmpty ? 0 : 10, bottom: 4),
              child: Text(
                day == 0 ? 'Aujourd\'hui' : 'Demain',
                style: theme.textTheme.labelLarge?.copyWith(color: p.muted),
              ),
            ),
          );
        }
        rows.add(_EventRow(event: e, onTap: () => _s.system.openEvent(e.id)));
      }
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.event_outlined, size: 18, color: p.blue),
                  const SizedBox(width: 8),
                  Text('Agenda', style: displayStyle(context, 20)),
                ],
              ),
              const SizedBox(height: 10),
              body,
            ],
          ),
        ),
      ),
    );
  }
}

class _EventRow extends StatelessWidget {
  const _EventRow({required this.event, required this.onTap});
  final CalendarEvent event;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final theme = Theme.of(context);
    final time = event.allDay
        ? 'Journée'
        : '${DateFormat.Hm('fr').format(event.begin)}–${DateFormat.Hm('fr').format(event.end)}';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 4,
              height: 36,
              decoration: BoxDecoration(
                color: Color(event.color).withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 92,
              child: Text(
                time,
                style: theme.textTheme.labelLarge?.copyWith(color: p.blue),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.title,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (event.location != null)
                    Text(
                      event.location!,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
