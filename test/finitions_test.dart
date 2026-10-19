import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/app_state.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/security/lock_service.dart';
import 'package:flyfinance/ui/widgets.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('les montants prennent leurs points pendant la saisie', () {
    const f = ThousandsFormatter();
    final v = f.formatEditUpdate(
      TextEditingValue.empty,
      const TextEditingValue(text: '1500000'),
    );
    expect(v.text, '1.500.000');
    expect(parseAmount(v.text), 1500000);
    expect(f.formatEditUpdate(v, const TextEditingValue(text: '')).text, '');
  });

  test('date de l’accueil en français', () {
    expect(longDate(DateTime(2026, 10, 19)), 'Lundi 19 octobre');
  });

  test('le mode jour/nuit et l’œil sont retenus', () async {
    final db = AppDatabase(NativeDatabase.memory());
    final store = MemorySecretStore();
    final a = AppState(Repository(db), store: store);
    a.setAppearance(Appearance.nuit);
    a.toggleAmounts();
    final b = AppState(Repository(db), store: store);
    await b.loadPrefs();
    expect(b.appearance, Appearance.nuit);
    expect(b.hideAmounts, isTrue);
    await db.close();
  });
}
