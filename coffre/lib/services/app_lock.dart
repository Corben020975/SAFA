import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';

import '../data/app_settings.dart';

/// Verrouillage de Coffre par empreinte (ou code du téléphone).
/// Verrouillé au démarrage et au retour après [grace] en arrière-plan.
class AppLock extends ChangeNotifier {
  AppLock(
    this._settings, {
    Future<bool> Function(String reason)? authenticate,
    this.grace = const Duration(seconds: 60),
  }) : _authenticate = authenticate ?? _system,
       locked = _settings.appLock;

  final AppSettings _settings;
  final Future<bool> Function(String reason) _authenticate;
  final Duration grace;

  bool locked;
  String? error;
  bool _busy = false;
  DateTime? _pausedAt;

  static Future<bool> _system(String reason) => LocalAuthentication()
      .authenticate(localizedReason: reason, persistAcrossBackgrounding: true);

  void onPaused() {
    // La fenêtre d'empreinte ou de code peut mettre l'app en pause.
    if (!_busy) _pausedAt ??= DateTime.now();
  }

  void onResumed() {
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (_settings.appLock &&
        !locked &&
        pausedAt != null &&
        DateTime.now().difference(pausedAt) >= grace) {
      locked = true;
      error = null;
      notifyListeners();
    }
  }

  Future<void> unlock() async {
    if (await _check('Déverrouiller Coffre')) {
      locked = false;
      notifyListeners();
    }
  }

  /// Active le verrou après une vérification (évite de s'enfermer dehors).
  Future<bool> enable() async {
    if (!await _check('Activer le verrouillage de Coffre')) return false;
    await _settings.setAppLock(true);
    return true;
  }

  Future<void> disable() => _settings.setAppLock(false);

  Future<bool> _check(String reason) async {
    if (_busy) return false;
    _busy = true;
    error = null;
    notifyListeners();
    try {
      return await _authenticate(reason);
    } on LocalAuthException catch (e) {
      switch (e.code) {
        case LocalAuthExceptionCode.noCredentialsSet ||
            LocalAuthExceptionCode.noBiometricHardware:
          // Aucun verrou sur le téléphone : impossible de protéger Coffre,
          // on désactive plutôt que de bloquer l'accès.
          error =
              'Aucune empreinte ni code configuré sur le téléphone : '
              'verrouillage désactivé.';
          await _settings.setAppLock(false);
          locked = false;
        case LocalAuthExceptionCode.temporaryLockout ||
            LocalAuthExceptionCode.biometricLockout:
          error = 'Trop d\'essais. Réessaie dans un moment.';
        case LocalAuthExceptionCode.userCanceled ||
            LocalAuthExceptionCode.systemCanceled:
          error = null;
        default:
          error = 'Vérification impossible (${e.code.name}).';
      }
      return false;
    } catch (e) {
      error = 'Vérification impossible : $e';
      return false;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
