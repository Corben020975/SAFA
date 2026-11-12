import '../data/database.dart';

/// Filtre de la journée : tout, travail (Grok / SAFA), ou perso.
enum DayMode {
  all('Tout'),
  pro('Pro'),
  perso('Perso');

  const DayMode(this.label);
  final String label;
}

/// Tags Notion / Grokbot qui signalent le monde professionnel.
const kProNotionTags = {
  'réunion',
  'reunion',
  'appel',
  'suivi',
  'admin',
  'autre',
  'délégué',
  'delegue',
  'bloqué',
  'bloque',
};

const kPersoNotionTags = {'perso', 'santé', 'sante', 'privé', 'prive'};

/// Contextes Coffre considérés comme « Pro ».
const kProContexts = {'Travail', 'Admin', 'Déplacement'};

/// Contextes Coffre considérés comme « Perso ».
const kPersoContexts = {'Perso', 'Santé'};

/// Convertit un tag / libellé Notion (Contexte Grokbot) en contexte Coffre.
String? mapNotionLabelToContext(String raw) {
  final t = raw.trim().toLowerCase();
  return switch (t) {
    'santé' || 'sante' => 'Santé',
    'perso' || 'privé' || 'prive' => 'Perso',
    'admin' => 'Admin',
    'réunion' ||
    'reunion' ||
    'appel' ||
    'suivi' ||
    'autre' ||
    'travail' => 'Travail',
    'déplacement' || 'deplacement' => 'Déplacement',
    _ => null,
  };
}

/// Choisit le contexte Coffre à partir des tags Notion (Contexte, Domaine…).
String? mapNotionTagsToContext(Iterable<String> tags) {
  for (final tag in tags) {
    final mapped = mapNotionLabelToContext(tag);
    if (mapped != null) return mapped;
  }
  return null;
}

bool itemIsPro(Item item) {
  if (item.context != null && kProContexts.contains(item.context)) return true;
  if (item.context != null && kPersoContexts.contains(item.context)) {
    return false;
  }
  for (final tag in item.tags) {
    final t = tag.toLowerCase();
    if (kPersoNotionTags.contains(t)) return false;
    if (kProNotionTags.contains(t)) return true;
  }
  // Import Notion sans contexte clair : pro (Grokbot = Todos pro).
  if (item.tags.any((t) => t.toLowerCase() == 'notion')) return true;
  return false;
}

bool itemIsPerso(Item item) => !itemIsPro(item);

List<Item> filterByDayMode(List<Item> items, DayMode mode) => switch (mode) {
  DayMode.all => items,
  DayMode.pro => items.where(itemIsPro).toList(),
  DayMode.perso => items.where(itemIsPerso).toList(),
};

/// Tags d'état Grokbot à afficher en badge.
String? statusBadgeFor(Item item) {
  for (final tag in item.tags) {
    final t = tag.toLowerCase();
    if (t == 'bloqué' || t == 'bloque') return 'Bloqué';
    if (t == 'délégué' || t == 'delegue') return 'Délégué';
  }
  return null;
}

/// Premier verbe d'action du titre (mails / todos Grok), pour scannabilité.
///
/// Ne découpe que les formulations du type « Répondre à X — … » /
/// « Voir Dominique : … », pas « Appeler le médecin ».
({String? verb, String title}) splitActionTitle(String content) {
  final first = content.trim().split('\n').first.trim();
  if (first.isEmpty) return (verb: null, title: first);
  final match = RegExp(
    r'^(Répondre|Voir|Dire|Aller|Convoquer|Valider|Lire|Appeler|'
    r'Écrire|Se renseigner|Faire le point|Mise en demeure|'
    r'Demander|Relancer|Envoyer|Préparer|Planifier)\b'
    r'(?:\s+à\s+|\s*[:–—-]\s+)',
    caseSensitive: false,
  ).firstMatch(first);
  if (match == null) return (verb: null, title: first);
  final verb = match.group(1)!;
  final rest = first.substring(match.end).trim();
  if (rest.length < 4) return (verb: null, title: first);
  final nice = '${verb[0].toUpperCase()}${verb.substring(1).toLowerCase()}';
  return (verb: nice, title: rest);
}
