import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

/// Petit coffre clé/valeur. En production c'est le coffre sécurisé du
/// téléphone (Android Keystore, iOS Keychain) ; en test, une simple Map.
abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class DeviceSecretStore implements SecretStore {
  const DeviceSecretStore();
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

class MemorySecretStore implements SecretStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String key) async => _m[key];
  @override
  Future<void> write(String key, String value) async => _m[key] = value;
  @override
  Future<void> delete(String key) async => _m.remove(key);
}

String _random(int bytes) {
  final r = Random.secure();
  return base64UrlEncode(List.generate(bytes, (_) => r.nextInt(256)));
}

/// Clé de chiffrement de la base : tirée au hasard au premier lancement,
/// gardée uniquement dans le coffre du téléphone.
Future<String> databaseKey(SecretStore store) async {
  var key = await store.read('db_key');
  if (key == null) {
    key = _random(32);
    await store.write('db_key', key);
  }
  return key;
}

/// Code PIN, empreinte et verrouillage automatique.
class LockService extends ChangeNotifier {
  LockService(this.store, {LocalAuthentication? auth, this.now = DateTime.now})
    : _auth = auth; // ignore: prefer_initializing_formals

  final SecretStore store;
  final LocalAuthentication? _auth;
  final DateTime Function() now;

  static const autoLockAfter = Duration(minutes: 5);
  static const maxAttempts = 5;
  static const lockoutDuration = Duration(minutes: 1);

  bool _unlocked = false;
  DateTime? _pausedAt;
  int _failures = 0;
  DateTime? _lockedOutUntil;

  bool get unlocked => _unlocked;

  Future<bool> hasPin() async => await store.read('pin_hash') != null;

  /// Le PIN n'est jamais enregistré en clair : seulement son empreinte
  /// salée et étirée (10 000 tours de SHA-256).
  static String hashPin(String pin, String salt) {
    List<int> digest = utf8.encode('$salt:$pin');
    for (var i = 0; i < 10000; i++) {
      digest = sha256.convert(digest).bytes;
    }
    return base64Encode(digest);
  }

  Future<void> setPin(String pin) async {
    if (!RegExp(r'^\d{4}$').hasMatch(pin)) {
      throw ArgumentError('Le code doit faire 4 chiffres.');
    }
    final salt = _random(16);
    await store.write('pin_salt', salt);
    await store.write('pin_hash', hashPin(pin, salt));
    _unlocked = true;
    notifyListeners();
  }

  Duration? get lockoutRemaining {
    final until = _lockedOutUntil;
    if (until == null) return null;
    final left = until.difference(now());
    return left.isNegative ? null : left;
  }

  Future<bool> unlockWithPin(String pin) async {
    if (lockoutRemaining != null) return false;
    final salt = await store.read('pin_salt');
    final hash = await store.read('pin_hash');
    if (salt == null || hash == null) return false;
    if (hashPin(pin, salt) == hash) {
      _failures = 0;
      _unlocked = true;
      notifyListeners();
      return true;
    }
    _failures++;
    if (_failures >= maxAttempts) {
      _failures = 0;
      _lockedOutUntil = now().add(lockoutDuration);
    }
    notifyListeners();
    return false;
  }

  Future<bool> canUseBiometrics() async {
    final auth = _auth;
    if (auth == null) return false;
    try {
      return await auth.canCheckBiometrics && await auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> unlockWithBiometrics() async {
    final auth = _auth;
    if (auth == null || !await hasPin()) return false;
    try {
      final ok = await auth.authenticate(
        localizedReason: 'Déverrouiller Gère-mieux',
        biometricOnly: true,
      );
      if (ok) {
        _unlocked = true;
        notifyListeners();
      }
      return ok;
    } catch (_) {
      return false;
    }
  }

  void lock() {
    _unlocked = false;
    notifyListeners();
  }

  /// Appelé quand l'application passe en arrière-plan puis revient.
  void onPaused() => _pausedAt = now();
  void onResumed() {
    final at = _pausedAt;
    if (at != null && now().difference(at) >= autoLockAfter) lock();
    _pausedAt = null;
  }
}
