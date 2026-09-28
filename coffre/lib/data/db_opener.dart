import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/common.dart' show CommonDatabase;
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';

/// Clé de chiffrement de la base : 256 bits aléatoires, conservés dans le
/// Keystore Android via flutter_secure_storage. Jamais affichée, jamais exportée.
class DbKeyStore {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());
  static const _keyName = 'coffre_db_key_v1';

  /// Lecture seule (isolate d'arrière-plan) : ne crée jamais de clé.
  static Future<String?> read() async {
    try {
      final key = await _storage.read(key: _keyName);
      return (key != null && key.length == 64) ? key : null;
    } catch (_) {
      return null;
    }
  }

  static Future<String> readOrCreate() async {
    final existing = await read();
    if (existing != null) return existing;
    final random = Random.secure();
    final key = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await _storage.write(key: _keyName, value: key);
    return key;
  }
}

class OpenedDatabase {
  OpenedDatabase(this.db, {this.setAsideFile});
  final AppDatabase db;

  /// Non nul si une base illisible a été mise de côté à l'ouverture.
  final String? setAsideFile;
}

Future<File> databaseFile() async {
  final dir = await getApplicationSupportDirectory();
  return File(p.join(dir.path, 'coffre.sqlite'));
}

/// Ouverture depuis l'interface. Si la base existe mais ne peut pas être
/// déchiffrée (clé Keystore perdue, restauration d'une sauvegarde système…),
/// le fichier est renommé — jamais supprimé — et une base vide est créée.
Future<OpenedDatabase> openDatabaseForUi() async {
  final key = await DbKeyStore.readOrCreate();
  final file = await databaseFile();
  String? setAside;
  if (await file.exists() && _isUnreadable(file, key)) {
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-');
    final aside = p.join(file.parent.path, 'coffre_illisible_$stamp.sqlite');
    await file.rename(aside);
    for (final suffix in const ['-wal', '-shm']) {
      final side = File('${file.path}$suffix');
      if (await side.exists()) await side.rename('$aside$suffix');
    }
    setAside = p.basename(aside);
  }
  return OpenedDatabase(AppDatabase(_connect(key)), setAsideFile: setAside);
}

/// Ouverture depuis l'isolate des actions de notification (app fermée).
Future<AppDatabase?> openDatabaseForBackground() async {
  final key = await DbKeyStore.read();
  if (key == null) return null;
  return AppDatabase(_connect(key));
}

QueryExecutor _connect(String key) {
  return driftDatabase(
    name: 'coffre',
    native: DriftNativeOptions(
      databasePath: () async => (await databaseFile()).path,
      // Un seul isolate SQLite partagé par l'UI et par l'isolate des actions
      // de notification : pas de « database is locked », et l'UI voit
      // immédiatement un snooze fait depuis la notification.
      shareAcrossIsolates: true,
      setup: (db) {
        applyKey(db, key);
        db.execute('PRAGMA journal_mode = WAL;');
        db.execute('PRAGMA busy_timeout = 5000;');
      },
    ),
  );
}

/// La clé est un hexadécimal généré par l'app : aucune injection possible.
void applyKey(CommonDatabase db, String key) {
  db.execute("PRAGMA key = '$key';");
}

bool _isUnreadable(File file, String key) {
  Database? db;
  try {
    db = sqlite3.open(file.path);
    applyKey(db, key);
    db.select('SELECT count(*) FROM sqlite_master;');
    return false;
  } on SqliteException catch (e) {
    // 26 = SQLITE_NOTADB : mauvaise clé ou fichier non SQLite.
    // Toute autre erreur (verrou, disque) ne doit PAS faire écarter la base.
    return (e.extendedResultCode & 0xff) == 26;
  } finally {
    db?.close();
  }
}

/// Vrai si la bibliothèque SQLite embarquée est bien la version chiffrante.
Future<bool> isEncryptionAvailable(AppDatabase db) async {
  try {
    final row = await db
        .customSelect('SELECT sqlite3mc_version() AS v')
        .getSingle();
    return (row.read<String>('v')).isNotEmpty;
  } catch (_) {
    return false;
  }
}
