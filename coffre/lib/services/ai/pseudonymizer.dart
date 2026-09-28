/// Masque les données personnelles AVANT tout envoi à l'IA, puis les remet
/// dans la réponse. Pensé pour le secret professionnel en CPAS : les noms de
/// bénéficiaires, n° de registre national, téléphones, e-mails et IBAN ne
/// quittent jamais le téléphone.
///
/// Limite assumée : un nom sans civilité (« Dupont a appelé ») n'est pas
/// détecté. D'où le rappel dans l'interface : écrire « Mme Dupont ».
class Pseudonymizer {
  final Map<String, String> _toPlaceholder = {};
  final Map<String, String> _toOriginal = {};
  final Map<String, int> _counters = {};

  static final _rules = <(String, RegExp)>[
    // Registre national belge : 85.07.30-033.28 ou 85073003328.
    (
      'NUMERO',
      RegExp(r'\b\d{2}[.\s]?\d{2}[.\s]?\d{2}[-.\s]?\d{3}[.\s]?\d{2}\b'),
    ),
    (
      'IBAN',
      RegExp(r'\b[A-Z]{2}\d{2}(?:\s?[A-Z0-9]{4}){2,7}(?:\s?[A-Z0-9]{1,3})?\b'),
    ),
    ('EMAIL', RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b')),
    ('TELEPHONE', RegExp(r'(?:\+32\s?|\b0)4?\d{1,2}(?:[\s./]?\d{2}){3,4}\b')),
    // Civilité suivie d'un ou deux noms propres.
    (
      'PERSONNE',
      RegExp(
        r"\b(?:M\.|Mme|Mmes|Mlle|MM\.|Madame|Monsieur|Mademoiselle|Dr|Docteur|Me|Maître)\s+"
        r"[A-ZÀ-Ý][\p{L}'’-]+(?:\s+[A-ZÀ-Ý][\p{L}'’-]+)?",
        unicode: true,
      ),
    ),
  ];

  /// Remplace chaque donnée par un marqueur stable ([PERSONNE 1], [EMAIL 1]…).
  String mask(String text) {
    var result = text;
    for (final (label, pattern) in _rules) {
      result = result.replaceAllMapped(pattern, (m) {
        final original = m.group(0)!;
        final existing = _toPlaceholder[original];
        if (existing != null) return existing;
        final n = (_counters[label] ?? 0) + 1;
        _counters[label] = n;
        final placeholder = '[$label $n]';
        _toPlaceholder[original] = placeholder;
        _toOriginal[placeholder] = original;
        return placeholder;
      });
    }
    return result;
  }

  /// Remet les vraies valeurs dans la réponse de l'IA.
  String unmask(String text) {
    var result = text;
    _toOriginal.forEach((placeholder, original) {
      result = result.replaceAll(placeholder, original);
    });
    return result;
  }

  int get maskedCount => _toOriginal.length;
}
