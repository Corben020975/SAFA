import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../../core/app_services.dart';
import '../../core/date_labels.dart';
import '../../data/database.dart';
import '../../data/enums.dart';
import '../../services/notification_service.dart';
import '../theme.dart';
import '../widgets/dictation_button.dart';
import '../widgets/reminder_field.dart';
import '../widgets/selectors.dart';
import '../widgets/tags_editor.dart';

/// Détail = édition directe. Chaque changement est enregistré aussitôt
/// (texte : après une courte pause de frappe), pas de bouton « Sauver ».
class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.itemId});
  final int itemId;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late final AppServices _s = AppScope.of(context);
  final _text = TextEditingController();
  Item? _item;
  bool _loading = true;
  Timer? _debounce;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final item = await _s.db.getItem(widget.itemId);
    if (!mounted) return;
    setState(() {
      _item = item;
      _loading = false;
      _text.text = item?.content ?? '';
    });
  }

  @override
  void dispose() {
    // Enregistre la dernière frappe si on quitte avant la fin du délai
    // (sans setState : l'écran est en cours de destruction).
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      final item = _item;
      final text = _text.text.trim();
      if (item != null && text.isNotEmpty && text != item.content) {
        final db = _s.db;
        final notifications = _s.notifications;
        db.saveItem(item.copyWith(content: text)).then(notifications.schedule);
      }
    }
    if (_s.speech.isListening) _s.speech.stop();
    _text.dispose();
    super.dispose();
  }

  Future<void> _save(Item next, {bool reschedule = false}) async {
    setState(() => _item = next);
    final saved = await _s.db.saveItem(next);
    _item = saved;
    if (!reschedule) return;
    final outcome = await _s.notifications.schedule(saved);
    if (!mounted) return;
    if (saved.remindAt != null && saved.remindAt!.isAfter(DateTime.now())) {
      if (!await _s.notifications.areEnabled()) {
        _snack('Notifications désactivées : le rappel ne s\'affichera pas.');
      } else if (outcome == ScheduleOutcome.inexact) {
        _snack('Rappel approximatif : autorise « Alarmes et rappels ».');
      }
    }
  }

  void _onTextChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), _saveText);
  }

  void _saveText() {
    final item = _item;
    final text = _text.text.trim();
    if (item == null || text.isEmpty || text == item.content) return;
    // Reprogrammer pour mettre à jour le texte de la notification.
    _save(item.copyWith(content: text), reschedule: item.remindAt != null);
  }

  void _onDictated(String dictated) {
    if (!mounted) return;
    final updated = appendDictation(_text.text, dictated);
    _text.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
    _onTextChanged(updated);
  }

  Future<void> _toggleDone() async {
    final item = _item!;
    final done = item.status == ItemStatus.done;
    await _save(
      item.copyWith(status: done ? ItemStatus.todo : ItemStatus.done),
      reschedule: true,
    );
    if (!done && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop();
      messenger.showSnackBar(const SnackBar(content: Text('Marqué fait')));
    }
  }

  Future<void> _delete() async {
    final item = _item!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer définitivement ?'),
        content: const Text('Tu pourras annuler juste après.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Garder'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _debounce?.cancel();
    await _s.db.deleteItem(item.id);
    await _s.notifications.cancel(item.id);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final db = _s.db;
    final notifications = _s.notifications;
    Navigator.of(context).pop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Supprimé'),
        persist: false,
        duration: kUndoDuration,
        action: SnackBarAction(
          label: 'Annuler',
          onPressed: () async {
            await db.restoreItem(item);
            await notifications.schedule(item);
          },
        ),
      ),
    );
  }

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final item = _item;
    if (item == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Cet élément n\'existe plus.')),
      );
    }
    final theme = Theme.of(context);
    final done = item.status == ItemStatus.done;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.kind.label),
        actions: [
          IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline),
            onPressed: _delete,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          KindSelector(
            value: item.kind,
            onChanged: (k) => _save(
              item.copyWith(
                kind: k,
                // « En cours » n'a de sens que pour une tâche.
                status: k != ItemKind.task && item.status == ItemStatus.doing
                    ? ItemStatus.todo
                    : item.status,
              ),
              reschedule: item.remindAt != null,
            ),
          ),
          if (item.kind == ItemKind.task) ...[
            const SectionLabel('État'),
            StatusSelector(
              value: item.status,
              onChanged: (st) =>
                  _save(item.copyWith(status: st), reschedule: true),
            ),
          ],
          const SectionLabel('Contenu'),
          TextField(
            controller: _text,
            minLines: 3,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
            style: theme.textTheme.bodyLarge?.copyWith(fontSize: 18),
            onChanged: _onTextChanged,
            decoration: InputDecoration(
              suffixIcon: MicButton(onText: _onDictated),
            ),
          ),
          const SizedBox(height: 8),
          const DictationPanel(),
          if (item.raw != null && item.raw!.trim() != item.content.trim())
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Theme(
                data: theme.copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: const Icon(Icons.history_edu_outlined),
                  title: const Text('Texte d\'origine'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  expandedAlignment: Alignment.centerLeft,
                  children: [
                    SelectableText(
                      item.raw!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SectionLabel('Rappel'),
          ReminderField(
            value: item.remindAt,
            onChanged: (d) =>
                _save(item.copyWith(remindAt: Value(d)), reschedule: true),
          ),
          if (item.remindAt != null)
            PreAlertSwitch(
              value: item.preAlert,
              onChanged: (v) =>
                  _save(item.copyWith(preAlert: v), reschedule: true),
            ),
          const SectionLabel('Priorité'),
          PrioritySelector(
            value: item.priority,
            onChanged: (p) => _save(
              item.copyWith(priority: p),
              reschedule: item.remindAt != null,
            ),
          ),
          const SectionLabel('Contexte'),
          ContextSelector(
            value: item.context,
            onChanged: (c) => _save(
              item.copyWith(context: Value(c)),
              reschedule: item.remindAt != null,
            ),
          ),
          const SectionLabel('Tags'),
          TagsEditor(
            tags: item.tags,
            onChanged: (t) => _save(item.copyWith(tags: t)),
          ),
          const SectionLabel('Organisation'),
          Card(
            child: SwitchListTile(
              title: const Text('Dans l\'Inbox'),
              subtitle: const Text('Désactive pour classer l\'élément'),
              value: item.inbox,
              onChanged: (v) => _save(item.copyWith(inbox: v)),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            [
              'Créé ${formatLong(item.createdAt)}',
              'Modifié ${formatLong(item.updatedAt)}',
              if (item.doneAt != null) 'Fait ${formatLong(item.doneAt!)}',
            ].join('\n'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: done
              ? FilledButton.tonalIcon(
                  onPressed: _toggleDone,
                  icon: const Icon(Icons.undo),
                  label: const Text('Réactiver'),
                )
              : FilledButton.icon(
                  onPressed: _toggleDone,
                  icon: const Icon(Icons.check),
                  label: const Text('Marquer comme fait'),
                ),
        ),
      ),
    );
  }
}
