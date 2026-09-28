import 'package:flutter/material.dart';

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
  }

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
