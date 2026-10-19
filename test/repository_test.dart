import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gere_mieux/data/database.dart';
import 'package:gere_mieux/data/repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late Repository repo;
  late Product riz;
  late int fatou;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = Repository(db);
    final id = await repo.addProduct(
      name: 'Riz 25 kg',
      price: 15000,
      cost: 12000,
      alertMin: 5,
      initialQty: 18,
    );
    riz = (await repo.products()).firstWhere((p) => p.id == id);
    fatou = await repo.addContact('Fatou Koné');
  });

  tearDown(() => db.close());

  test('une vente sort le stock et calcule le statut', () async {
    await repo.recordSale(
      lines: [CartLine(riz, 3)],
      contactId: fatou,
      paidNow: 22500,
    );
    expect(await repo.stockOf(riz.id), 15);
    final s = (await repo.sales()).single;
    expect(s.sale.total, 45000);
    expect(s.due, 22500);
    expect(s.status, SaleStatus.acompte);
  });

  test('un remboursement fait passer en reliquat puis soldée', () async {
    await repo.recordSale(lines: [CartLine(riz, 2)], contactId: fatou);
    expect((await repo.sales()).single.status, SaleStatus.nonPaye);
    await repo.receivePayment(fatou, 10000, method: 'wave');
    expect((await repo.sales()).single.status, SaleStatus.reliquat);
    final applied = await repo.receivePayment(fatou, 50000);
    expect(applied, 20000);
    expect((await repo.sales()).single.status, SaleStatus.soldee);
    expect(await repo.debtors(), isEmpty);
  });

  test('refuse de vendre plus que le stock', () async {
    expect(
      () => repo.recordSale(lines: [CartLine(riz, 19)], paidNow: 19 * 15000),
      throwsStateError,
    );
    expect(await repo.stockOf(riz.id), 18);
  });

  test('refuse un crédit sans client', () async {
    expect(
      () => repo.recordSale(lines: [CartLine(riz, 1)], paidNow: 0),
      throwsArgumentError,
    );
  });

  test('annuler une vente remet le stock et retire la dette', () async {
    final id = await repo.recordSale(
      lines: [CartLine(riz, 4)],
      contactId: fatou,
    );
    await repo.cancelSale(id);
    expect(await repo.stockOf(riz.id), 18);
    expect((await repo.sales()).single.status, SaleStatus.annulee);
    expect(await repo.debtors(), isEmpty);
  });

  test('alerte de rupture et statistiques', () async {
    await repo.recordSale(lines: [CartLine(riz, 13)], paidNow: 13 * 15000);
    final low = await repo.lowStock();
    expect(low.single.qty, 5);
    final stats = await repo.statsSince(DateTime(2000));
    expect(stats.sales, 195000);
    expect(stats.profit, 13 * 3000);
    expect(stats.cashIn, 195000);
  });

  test('la recherche ignore accents et majuscules', () async {
    await repo.addProduct(name: 'Crème fraîche', price: 900);
    expect((await repo.findProducts('creme')).single.name, 'Crème fraîche');
    expect((await repo.findContacts('KONE')).single.id, fatou);
  });
}
