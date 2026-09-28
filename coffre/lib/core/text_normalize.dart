// Recherche « plein texte » tolérante : minuscules, sans accents, sans ponctuation.
// On stocke une version normalisée (colonne search_text) et on cherche avec LIKE :
// « idee » trouve « Idée », « dup » trouve « Dupont ».

const Map<String, String> _foldMap = {
  'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'å': 'a',
  'ç': 'c',
  'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
  'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
  'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o',
  'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
  'ÿ': 'y', 'ñ': 'n',
  'œ': 'oe', 'æ': 'ae',
};

final RegExp _nonAlnum = RegExp(r'[^a-z0-9]+');

/// Minuscules, accents retirés, tout le reste devient un espace simple.
String normalizeForSearch(String input) {
  final lower = input.toLowerCase();
  final buffer = StringBuffer();
  for (final rune in lower.runes) {
    final ch = String.fromCharCode(rune);
    buffer.write(_foldMap[ch] ?? ch);
  }
  return buffer.toString().replaceAll(_nonAlnum, ' ').trim();
}

/// Texte indexé : contenu + tags. Entouré d'espaces pour d'éventuelles
/// recherches « mot entier » plus tard.
String buildSearchText(String content, List<String> tags) {
  final parts = [normalizeForSearch(content), ...tags.map(normalizeForSearch)];
  return ' ${parts.where((p) => p.isNotEmpty).join(' ')} ';
}

/// Mots de la requête, déjà sûrs pour un LIKE (uniquement [a-z0-9]).
List<String> searchWords(String query) =>
    normalizeForSearch(query).split(' ').where((w) => w.isNotEmpty).toList();

/// Tag propre : sans #, minuscule, espaces → tirets, 30 caractères max.
String? normalizeTag(String raw) {
  var tag = raw.trim().replaceAll(RegExp(r'^#+'), '').toLowerCase();
  tag = tag.replaceAll(RegExp(r'[\s,;]+'), '-').replaceAll(RegExp(r'-+'), '-');
  tag = tag.replaceAll(RegExp(r'^-|-$'), '');
  if (tag.isEmpty) return null;
  return tag.length > 30 ? tag.substring(0, 30) : tag;
}

/// Même longueur que l'entrée (1 caractère → 1 caractère) : permet d'utiliser
/// les positions d'une regex sur le texte replié pour découper l'original.
String foldKeepingLength(String input) {
  final buffer = StringBuffer();
  for (final unit in input.split('')) {
    final lower = unit.toLowerCase();
    final folded = _foldMap[lower] ?? lower;
    buffer.write(folded.length == 1 ? folded : folded[0]);
  }
  return buffer.toString();
}
