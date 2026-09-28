import 'package:flutter/services.dart';

/// Pont vers le code Kotlin (MainActivity) : réglages Samsung/Android,
/// sélecteur de fichiers système (SAF) et raccourcis du widget.
class SystemChannel {
  SystemChannel() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onLaunchAction' && call.arguments is String) {
        onLaunchAction?.call(call.arguments as String);
      }
    });
  }

  static const _channel = MethodChannel('coffre/system');

  /// Appelé quand le widget relance l'app déjà ouverte.
  void Function(String uri)? onLaunchAction;

  /// Action reçue au démarrage (widget), consommée une seule fois.
  Future<String?> takeLaunchAction() => _call<String>('takeLaunchAction');

  Future<bool> isIgnoringBatteryOptimizations() async =>
      await _call<bool>('isIgnoringBatteryOptimizations') ?? false;

  /// Boîte de dialogue système « Autoriser en arrière-plan sans restriction ».
  Future<void> requestIgnoreBatteryOptimizations() =>
      _call<void>('requestIgnoreBatteryOptimizations');

  /// Page « Infos sur l'appli » (Batterie > Non restreinte chez Samsung).
  Future<void> openAppSettings() => _call<void>('openAppSettings');

  Future<void> openNotificationSettings() =>
      _call<void>('openNotificationSettings');

  Future<void> openExactAlarmSettings() =>
      _call<void>('openExactAlarmSettings');

  Future<String> appVersion() async => await _call<String>('appVersion') ?? '?';

  /// « Enregistrer sous » système : l'utilisateur choisit le dossier.
  Future<bool> saveDocument({
    required String name,
    required String mimeType,
    required Uint8List bytes,
  }) async =>
      await _call<bool>('saveDocument', {
        'name': name,
        'mimeType': mimeType,
        'bytes': bytes,
      }) ??
      false;

  Future<Uint8List?> openDocument({List<String> mimeTypes = const ['*/*']}) =>
      _call<Uint8List>('openDocument', {'mimeTypes': mimeTypes});

  Future<T?> _call<T>(String method, [Object? args]) async {
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on MissingPluginException {
      return null; // tests / plateforme non Android
    }
  }
}
