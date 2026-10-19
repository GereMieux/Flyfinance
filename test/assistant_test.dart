import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gere_mieux/data/database.dart';
import 'package:gere_mieux/data/repository.dart';
import 'package:gere_mieux/voice/assistant.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late Repository repo;
  late Assistant a;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = Repository(db);
    a = Assistant(repo);
    await repo.addProduct(
      name: 'Riz 25 kg',
      unit: 'sacs',
      price: 15000,
      alertMin: 5,
      initialQty: 18,
    );
    await repo.addContact('Fatou Koné');
  });
  tearDown(() => db.close());

  test('vente vocale : rien n’est écrit avant le oui', () async {
    final r = await a.handle(
      'Vends 3 sacs de riz à Fatou, elle paie la moitié par Wave',
    );
    expect(r.action, isNotNull);
    expect(r.lines.first.$2, '45.000 FCFA');
    expect(await repo.sales(), isEmpty);

    final done = await r.action!.run();
    expect(done, contains('Il reste 15 sacs'));
    final s = (await repo.sales()).single;
    expect(s.paid, 22500);
    expect(s.contact!.name, 'Fatou Koné');
  });

  test('nouveau client créé à la confirmation', () async {
    final r = await a.handle('Vends 1 riz à Moussa à crédit');
    expect(r.lines.last, ('Nouveau client', 'Moussa'));
    await r.action!.run();
    final d = await a.handle('Qui me doit ?');
    expect(d.text, contains('15 000 francs'));
  });

  test('stock insuffisant', () async {
    final r = await a.handle('Vends 30 riz');
    expect(r.action, isNull);
    expect(r.text, contains('18'));
  });

  test('rupture et entrée en stock', () async {
    final r = await a.handle("J'ai reçu 10 sacs de riz");
    await r.action!.run();
    final q = await a.handle('Combien de riz il reste ?');
    expect(q.text, contains('28 sacs'));
  });
}
