import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Clés d'API (Gemini, Claude, Notion) : Keystore Android, jamais dans la
/// base ni dans les exports.
class SecretStore {
  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());
  static const aiKey = 'coffre_claude_api_key';
  static const geminiKey = 'coffre_gemini_api_key';
  static const notionKey = 'coffre_notion_token';

  final Map<String, String?> _cache = {};

  Future<String?> read(String name) async {
    if (_cache.containsKey(name)) return _cache[name];
    try {
      final value = await _storage.read(key: name);
      _cache[name] = (value == null || value.trim().isEmpty)
          ? null
          : value.trim();
    } catch (_) {
      _cache[name] = null;
    }
    return _cache[name];
  }

  Future<void> write(String name, String? value) async {
    final clean = value?.trim();
    _cache[name] = (clean == null || clean.isEmpty) ? null : clean;
    if (_cache[name] == null) {
      await _storage.delete(key: name);
    } else {
      await _storage.write(key: name, value: clean);
    }
  }

  Future<bool> has(String name) async => await read(name) != null;
}
