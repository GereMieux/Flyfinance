import 'package:flutter/foundation.dart';

import 'data/repository.dart';
import 'security/lock_service.dart';

/// Format FCFA comme sur les reçus ivoiriens : 13.303.850 FCFA.
String fcfa(int amount, {bool hidden = false, bool unit = true}) {
  if (hidden) return unit ? '•••••• FCFA' : '••••••';
  final digits = amount.abs().toString();
  final b = StringBuffer(amount < 0 ? '−' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write('.');
    b.write(digits[i]);
  }
  if (unit) b.write(' FCFA');
  return b.toString();
}

/// Mots dits à voix haute : « 45 000 francs » se lit mieux que 45.000 FCFA.
String spokenFcfa(int amount) {
  final s = fcfa(amount, unit: false).replaceAll('.', ' ');
  return '$s francs';
}

/// Apparence choisie : comme le téléphone, toujours clair ou toujours sombre.
enum Appearance { auto, jour, nuit }

/// État partagé de l'application : préférences et signal de rafraîchissement
/// après chaque enregistrement.
class AppState extends ChangeNotifier {
  AppState(this.repo, {this.store});
  final Repository repo;

  /// Où sont gardées les préférences d'un lancement à l'autre (rien en test).
  final SecretStore? store;

  /// Relit les préférences enregistrées.
  Future<void> loadPrefs() async {
    final s = store;
    if (s == null) return;
    final a = await s.read('pref_appearance');
    _appearance = Appearance.values.firstWhere(
      (v) => v.name == a,
      orElse: () => Appearance.auto,
    );
    _hideAmounts = await s.read('pref_hide_amounts') == '1';
    notifyListeners();
  }

  Appearance _appearance = Appearance.auto;
  Appearance get appearance => _appearance;
  void setAppearance(Appearance a) {
    _appearance = a;
    store?.write('pref_appearance', a.name);
    notifyListeners();
  }

  /// Dernière visite de la corbeille : les annulations plus récentes
  /// s'affichent en notification sur l'accueil.
  DateTime? cancellationsSeenAt;
  void markCancellationsSeen(DateTime at) {
    cancellationsSeenAt = at;
    notifyListeners();
  }

  bool _hideAmounts = false;
  bool get hideAmounts => _hideAmounts;
  void toggleAmounts() {
    _hideAmounts = !_hideAmounts;
    store?.write('pref_hide_amounts', _hideAmounts ? '1' : '0');
    notifyListeners();
  }

  /// Langue de l'assistant : 'fr', 'en', 'ar' ou 'es'.
  String language = 'fr';

  /// Voix de l'assistant : 'female' ou 'male'.
  String voice = 'female';

  void setVoicePrefs({String? language, String? voice}) {
    if (language != null) this.language = language;
    if (voice != null) this.voice = voice;
    notifyListeners();
  }

  int _revision = 0;
  int get revision => _revision;

  /// À appeler après toute écriture pour que les écrans se mettent à jour.
  void changed() {
    _revision++;
    notifyListeners();
  }

  String money(int amount) => fcfa(amount, hidden: _hideAmounts);
}
