import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/reminder_defaults.dart';
import 'database.dart';
import 'enums.dart';

/// Réglages persistés dans la table `prefs`. Notifie l'UI à chaque changement.
class AppSettings extends ChangeNotifier {
  AppSettings(this._db);
  final AppDatabase _db;

  ThemeMode themeMode = ThemeMode.dark;
  double textScale = 1.0;
  SortMode sort = SortMode.recent;
  String dictationLocale = 'fr_BE';
  bool onDeviceDictation = false;
  bool onboardingDone = false;
  ItemKind lastKind = ItemKind.task;
  DateTime? lastExportAt;

  /// Heures par défaut (minutes depuis minuit).
  int morningMinutes = 9 * 60;
  int eveningMinutes = 18 * 60;

  /// Moteur IA : Gemini (offre gratuite, par défaut) ou Claude (payant).
  AiProvider aiProvider = AiProvider.gemini;

  /// Assistant IA : données personnelles masquées avant envoi (par défaut).
  bool aiMask = true;
  bool aiConsent = false; // Claude
  bool aiConsentGemini = false;

  /// Verrouillage par empreinte ou code du téléphone.
  bool appLock = false;

  /// Agenda du téléphone (Google Agenda synchronisé).
  bool agendaEnabled = false;
  int? agendaCalendarId;
  String? agendaCalendarName;

  /// Base Notion de destination : {id, name, titleProp, dateProp}.
  Map<String, String>? notionTarget;

  Future<void> load() async {
    final p = await _db.allPrefs();
    themeMode = ThemeMode.values.asNameMap()[p['theme']] ?? ThemeMode.dark;
    textScale = double.tryParse(p['textScale'] ?? '') ?? 1.0;
    sort = SortMode.values.asNameMap()[p['sort']] ?? SortMode.recent;
    dictationLocale = p['dictationLocale'] ?? 'fr_BE';
    onDeviceDictation = p['onDeviceDictation'] == 'true';
    onboardingDone = p['onboardingDone'] == 'true';
    lastKind = ItemKind.values.asNameMap()[p['lastKind']] ?? ItemKind.task;
    lastExportAt = DateTime.tryParse(p['lastExportAt'] ?? '');
    morningMinutes = int.tryParse(p['morning'] ?? '') ?? 9 * 60;
    eveningMinutes = int.tryParse(p['evening'] ?? '') ?? 18 * 60;
    aiProvider =
        AiProvider.values.asNameMap()[p['aiProvider']] ?? AiProvider.gemini;
    aiMask = p['aiMask'] != 'false';
    aiConsent = p['aiConsent'] == 'true';
    aiConsentGemini = p['aiConsentGemini'] == 'true';
    appLock = p['appLock'] == 'true';
    agendaEnabled = p['agendaEnabled'] == 'true';
    agendaCalendarId = int.tryParse(p['agendaCalendarId'] ?? '');
    agendaCalendarName = p['agendaCalendarName'];
    try {
      final raw = p['notionTarget'];
      notionTarget = raw == null
          ? null
          : Map<String, String>.from(jsonDecode(raw) as Map);
    } catch (_) {
      notionTarget = null;
    }
    _applyDefaults();
  }

  void _applyDefaults() {
    ReminderDefaults.morning = (morningMinutes ~/ 60, morningMinutes % 60);
    ReminderDefaults.evening = (eveningMinutes ~/ 60, eveningMinutes % 60);
  }

  Future<void> setMorning(int minutes) => _set(
    () {
      morningMinutes = minutes;
      _applyDefaults();
    },
    'morning',
    '$minutes',
  );
  Future<void> setEvening(int minutes) => _set(
    () {
      eveningMinutes = minutes;
      _applyDefaults();
    },
    'evening',
    '$minutes',
  );
  Future<void> setAiProvider(AiProvider value) =>
      _set(() => aiProvider = value, 'aiProvider', value.name);
  Future<void> setAiMask(bool value) =>
      _set(() => aiMask = value, 'aiMask', '$value');

  /// Accord donné une fois par moteur (les conditions diffèrent).
  bool consentFor(AiProvider provider) => switch (provider) {
    AiProvider.gemini => aiConsentGemini,
    AiProvider.claude => aiConsent,
  };
  Future<void> setAiConsent(AiProvider provider, bool value) =>
      switch (provider) {
        AiProvider.gemini => _set(
          () => aiConsentGemini = value,
          'aiConsentGemini',
          '$value',
        ),
        AiProvider.claude => _set(
          () => aiConsent = value,
          'aiConsent',
          '$value',
        ),
      };
  Future<void> setAppLock(bool value) =>
      _set(() => appLock = value, 'appLock', '$value');
  Future<void> setAgendaEnabled(bool value) =>
      _set(() => agendaEnabled = value, 'agendaEnabled', '$value');
  Future<void> setAgendaCalendar(int id, String name) async {
    agendaCalendarName = name;
    await _db.setPref('agendaCalendarName', name);
    await _set(() => agendaCalendarId = id, 'agendaCalendarId', '$id');
  }

  Future<void> setNotionTarget(Map<String, String>? target) => _set(
    () => notionTarget = target,
    'notionTarget',
    target == null ? '' : jsonEncode(target),
  );

  Future<void> setThemeMode(ThemeMode value) =>
      _set(() => themeMode = value, 'theme', value.name);
  Future<void> setTextScale(double value) =>
      _set(() => textScale = value, 'textScale', '$value');
  Future<void> setSort(SortMode value) =>
      _set(() => sort = value, 'sort', value.name);
  Future<void> setDictationLocale(String value) =>
      _set(() => dictationLocale = value, 'dictationLocale', value);
  Future<void> setOnDeviceDictation(bool value) =>
      _set(() => onDeviceDictation = value, 'onDeviceDictation', '$value');
  Future<void> setOnboardingDone(bool value) =>
      _set(() => onboardingDone = value, 'onboardingDone', '$value');
  Future<void> setLastKind(ItemKind value) =>
      _set(() => lastKind = value, 'lastKind', value.name);
  Future<void> markExported() {
    final now = DateTime.now();
    return _set(
      () => lastExportAt = now,
      'lastExportAt',
      now.toIso8601String(),
    );
  }

  Future<void> _set(void Function() apply, String key, String value) async {
    apply();
    notifyListeners();
    await _db.setPref(key, value);
  }
}

enum AiProvider {
  gemini('Gemini', 'Google'),
  claude('Claude', 'Anthropic');

  const AiProvider(this.label, this.company);
  final String label;
  final String company;
}
