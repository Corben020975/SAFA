import 'dart:convert';

import 'package:enough_mail/enough_mail.dart';

import '../core/app_services.dart';
import '../data/app_settings.dart';
import '../data/database.dart';
import '../data/enums.dart';
import 'ai/ai_assistant.dart';
import 'notification_service.dart';
import 'secret_store.dart';
import 'system_channel.dart';

/// Ce qu'on garde d'un mail pour le tri : expéditeur, objet, début du texte.
class MailDigest {
  const MailDigest({
    required this.uid,
    required this.from,
    required this.subject,
    this.date,
    this.text = '',
  });
  final int uid;
  final String from;
  final String subject;
  final DateTime? date;
  final String text;
}

/// Action repérée par l'IA dans un mail.
class MailAction {
  const MailAction({
    required this.mail,
    required this.type,
    required this.title,
    this.date,
    this.hasTime = false,
  });

  /// Index du mail (1, 2…) dans la liste envoyée.
  final int mail;

  /// facture | rdv | action
  final String type;
  final String title;
  final DateTime? date;
  final bool hasTime;
}

class MailException implements Exception {
  const MailException(this.message);
  final String message;

  @override
  String toString() => message;
}

class MailTriageResult {
  const MailTriageResult(this.read, this.added);
  final int read;
  final List<Item> added;
}

/// Lecture IMAP de Gmail avec un mot de passe d'application : pas de
/// connexion Google dans l'app, rien n'est marqué comme lu.
class GmailReader {
  static const _host = 'imap.gmail.com';
  static const maxMails = 30;
  static const _textChars = 900;

  /// Recherche Gmail (extension IMAP X-GM-RAW).
  static const gmailFilter =
      'X-GM-RAW "-category:promotions -category:social -category:forums"';

  /// Nouveaux mails de la boîte de réception depuis [afterUid] (ou les
  /// 3 derniers jours au premier passage). Renvoie aussi le nouveau curseur.
  static Future<(List<MailDigest>, int?, int?)> fetchNew({
    required String address,
    required String password,
    int? afterUid,
    int? uidValidity,
    DateTime? now,
  }) async {
    final client = ImapClient();
    try {
      await client.connectToServer(_host, 993);
      try {
        await client.login(address, password.replaceAll(' ', ''));
      } on ImapException {
        throw const MailException(
          'Gmail refuse la connexion : vérifie l\'adresse et le mot de passe d\'application.',
        );
      }
      final box = await client.selectInbox();
      final validity = box.uidValidity;
      final sameBox = afterUid != null && validity == uidValidity;
      final since = (now ?? DateTime.now()).subtract(const Duration(days: 3));
      // Onglets Gmail : on écarte Promotions, Réseaux sociaux et Forums.
      // « Mises à jour » reste lu : Gmail y range souvent les factures.
      final criteria =
          '${sameBox ? 'UID ${afterUid + 1}:*' : 'SINCE ${_imapDate(since)}'} '
          '$gmailFilter';
      final search = await client.uidSearchMessages(searchCriteria: criteria);
      final uids =
          (search.matchingSequence?.toList() ?? const <int>[])
              .where((u) => !sameBox || u > afterUid)
              .toList()
            ..sort();
      if (uids.isEmpty) return (const <MailDigest>[], afterUid, validity);
      final recent = uids.length > maxMails
          ? uids.sublist(uids.length - maxMails)
          : uids;

      final heads = await client.uidFetchMessages(
        MessageSequence.fromIds(recent, isUid: true),
        '(UID ENVELOPE BODYSTRUCTURE)',
      );
      final mails = <MailDigest>[];
      for (final m in heads.messages) {
        final uid = m.uid;
        if (uid == null) continue;
        final env = m.envelope;
        final sender = env?.from?.firstOrNull;
        var text = '';
        final part = _textPart(m.body);
        if (part != null) {
          try {
            final fetched = await client.uidFetchMessage(
              uid,
              '(BODY.PEEK[${part.$1}])',
            );
            final raw = fetched.messages.firstOrNull
                ?.getPart(part.$1)
                ?.decodeContentText();
            text = cleanText(raw ?? '', html: part.$2);
          } catch (_) {
            text = ''; // l'objet suffit souvent
          }
        }
        mails.add(
          MailDigest(
            uid: uid,
            from: sender == null
                ? '?'
                : [
                    if ((sender.personalName ?? '').isNotEmpty)
                      sender.personalName!,
                    '<${sender.email}>',
                  ].join(' '),
            subject: env?.subject ?? '(sans objet)',
            date: env?.date,
            text: text.length > _textChars
                ? '${text.substring(0, _textChars)}…'
                : text,
          ),
        );
      }
      return (mails, uids.last, validity);
    } finally {
      try {
        await client.logout();
      } catch (_) {}
    }
  }

  /// Partie texte à lire : text/plain de préférence, sinon text/html.
  static (String, bool)? _textPart(BodyPart? body) {
    if (body == null) return null;
    (String, bool)? html;
    (String, bool)? plain;
    void walk(BodyPart part) {
      final children = part.parts;
      if (children != null && children.isNotEmpty) {
        children.forEach(walk);
        return;
      }
      final sub = part.contentType?.mediaType.sub;
      final size = part.size ?? 0;
      if (size > 300000) return;
      final id = part.fetchId ?? '1';
      if (sub == MediaSubtype.textPlain) plain ??= (id, false);
      if (sub == MediaSubtype.textHtml) html ??= (id, true);
    }

    walk(body);
    return plain ?? html;
  }

  static String _imapDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day}-${months[d.month - 1]}-${d.year}';
  }

  /// Texte lisible : balises HTML retirées, blancs resserrés.
  static String cleanText(String raw, {bool html = false}) {
    var t = raw;
    if (html) {
      t = t
          .replaceAll(
            RegExp(r'<(style|script)[^>]*>.*?</\1>', dotAll: true),
            ' ',
          )
          .replaceAll(RegExp(r'<br\s*/?>|</p>|</div>|</tr>'), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), ' ')
          .replaceAll('&nbsp;', ' ')
          .replaceAll('&amp;', '&')
          .replaceAll('&euro;', '€');
    }
    return t
        .replaceAll(RegExp(r'[ \t ]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), '\n')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .trim();
  }
}

/// Mails → texte numéroté pour l'IA.
String describeMails(List<MailDigest> mails) => [
  for (var i = 0; i < mails.length; i++)
    [
      '--- Mail ${i + 1}',
      'De : ${mails[i].from}',
      'Objet : ${mails[i].subject}',
      if (mails[i].text.isNotEmpty) mails[i].text,
    ].join('\n'),
].join('\n\n');

/// Réponse de l'IA (tableau JSON) → actions, en ignorant le reste.
List<MailAction> parseMailActions(String answer, int count) {
  final start = answer.indexOf('[');
  final end = answer.lastIndexOf(']');
  if (start < 0 || end <= start) return const [];
  Object? json;
  try {
    json = jsonDecode(answer.substring(start, end + 1));
  } catch (_) {
    return const [];
  }
  if (json is! List) return const [];
  final actions = <MailAction>[];
  for (final entry in json.whereType<Map>()) {
    final index = entry['mail'];
    final title = '${entry['titre'] ?? ''}'.trim();
    final type = '${entry['type'] ?? ''}'.trim().toLowerCase();
    if (index is! int || index < 1 || index > count || title.isEmpty) continue;
    if (!const {'facture', 'rdv', 'action'}.contains(type)) continue;
    DateTime? date;
    var hasTime = false;
    final rawDate = entry['date'];
    if (rawDate is String) {
      final d = DateTime.tryParse(rawDate.trim());
      if (d != null) date = DateTime(d.year, d.month, d.day);
    }
    final rawTime = entry['heure'];
    if (date != null && rawTime is String) {
      final m = RegExp(r'^(\d{1,2})[:h](\d{2})').firstMatch(rawTime.trim());
      if (m != null) {
        date = date.add(
          Duration(
            hours: int.parse(m.group(1)!),
            minutes: int.parse(m.group(2)!),
          ),
        );
        hasTime = true;
      }
    }
    actions.add(
      MailAction(
        mail: index,
        type: type,
        title: title.length > 120 ? '${title.substring(0, 118)}…' : title,
        date: date,
        hasTime: hasTime,
      ),
    );
  }
  return actions;
}

/// Quand sonner : la veille à 9 h pour une facture, à l'heure (avec
/// pré-alerte) pour un rendez-vous, à 9 h le jour dit sinon.
DateTime? reminderFor(MailAction a, DateTime now) {
  final d = a.date;
  if (d == null) return null;
  DateTime at;
  if (a.type == 'facture') {
    final day = DateTime(d.year, d.month, d.day - 1, 9);
    at = day.isAfter(now) ? day : DateTime(d.year, d.month, d.day, 9);
  } else if (a.hasTime) {
    at = d;
  } else {
    at = DateTime(d.year, d.month, d.day, 9);
  }
  if (!at.isAfter(now)) {
    // Échéance du jour déjà passée à 9 h : rappel dans l'heure.
    final sameDay =
        d.year == now.year && d.month == now.month && d.day == now.day;
    return sameDay ? now.add(const Duration(minutes: 30)) : null;
  }
  return at;
}

/// Relève Gmail, fait trier par Claude (Haiku), crée les rappels côté Perso.
Future<MailTriageResult> runMailTriage({
  required AppDatabase db,
  required AppSettings settings,
  required SecretStore secrets,
  required AiAssistant ai,
  required NotificationService notifications,
  DateTime? now,
}) async {
  final address = settings.gmailAddress;
  final password = await secrets.read(SecretStore.gmailPassword);
  if (address == null || password == null) {
    throw const MailException(
      'Ajoute ton adresse Gmail et ton mot de passe d\'application.',
    );
  }
  final at = now ?? DateTime.now();
  final (mails, lastUid, validity) = await GmailReader.fetchNew(
    address: address,
    password: password,
    afterUid: settings.mailLastUid,
    uidValidity: settings.mailUidValidity,
    now: at,
  );
  final added = <Item>[];
  if (mails.isNotEmpty) {
    final answer = await ai.mailTriage(describeMails(mails), at);
    for (final a in parseMailActions(answer, mails.length)) {
      final mail = mails[a.mail - 1];
      final remind = reminderFor(a, at);
      final item = await db.createItem(
        kind: ItemKind.task,
        content: a.title,
        priority: a.type == 'facture' ? ItemPriority.high : ItemPriority.normal,
        tags: ['gmail', a.type],
        remindAt: remind,
        preAlert: a.type == 'rdv' && a.hasTime,
        context: 'Perso',
        raw: 'Mail de ${mail.from}\nObjet : ${mail.subject}',
      );
      await notifications.schedule(item);
      added.add(item);
    }
  }
  if (lastUid != null) await settings.setMailCursor(lastUid, validity);
  return MailTriageResult(mails.length, added);
}

/// Rendez-vous trouvés dans les mails : tag « hors agenda » s'il n'y a rien
/// dans l'agenda du téléphone à ±90 min. Au premier plan uniquement.
Future<void> flagRdvOutsideAgenda(AppServices s) async {
  final rdv = (await s.db.allItems()).where(
    (i) =>
        i.status != ItemStatus.done &&
        i.tags.contains('gmail') &&
        i.tags.contains('rdv') &&
        !i.tags.contains('hors agenda') &&
        !i.tags.contains('agenda ok') &&
        i.remindAt != null,
  );
  if (rdv.isEmpty) return;
  try {
    if (!await s.system.hasCalendarPermission()) return;
  } catch (_) {
    return;
  }
  for (final item in rdv) {
    final at = item.remindAt!;
    List<CalendarEvent> events;
    try {
      events = await s.system.calendarEvents(
        at.subtract(const Duration(minutes: 90)),
        at.add(const Duration(minutes: 90)),
      );
    } catch (_) {
      return;
    }
    final tag = events.any((e) => !e.allDay) ? 'agenda ok' : 'hors agenda';
    await s.db.saveItem(item.copyWith(tags: [...item.tags, tag]));
  }
}

/// Tri à l'ouverture de l'app, au plus une fois par heure.
class MailAutoTriage {
  MailAutoTriage(this._s);
  final AppServices _s;
  DateTime? _last;
  bool _running = false;

  Future<MailTriageResult?> run() async {
    final settings = _s.settings;
    final now = DateTime.now();
    if (!settings.mailTriage || _running) return null;
    if (!settings.consentFor(AiProvider.claude)) return null;
    if (_last != null && now.difference(_last!) < const Duration(hours: 1)) {
      return null;
    }
    _running = true;
    _last = now;
    try {
      final result = await runMailTriage(
        db: _s.db,
        settings: settings,
        secrets: _s.secrets,
        ai: _s.ai,
        notifications: _s.notifications,
      );
      await flagRdvOutsideAgenda(_s);
      return result;
    } catch (_) {
      return null; // hors ligne… on réessaiera
    } finally {
      _running = false;
    }
  }
}
