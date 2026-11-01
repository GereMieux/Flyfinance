import 'package:drift/drift.dart' show driftRuntimeOptions;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/data/accounts_repository.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/management_repository.dart';
import 'package:flyfinance/data/repository.dart';

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
      alertMin: 2,
      initialQty: 10,
    );
    riz = (await repo.products()).firstWhere((p) => p.id == id);
    fatou = await repo.addContact('Fatou Koné');
  });

  tearDown(() => db.close());

  test('le bénéfice net retire les dépenses', () async {
    await repo.recordSale(lines: [CartLine(riz, 2)], paidNow: 30000);
    await repo.addExpense(label: 'Loyer', amount: 5000, category: 'Loyer');
    final t = DateTime.now();
    final r = await repo.result(
      DateTime(t.year, t.month),
      DateTime(t.year, t.month + 1),
    );
    expect(r.revenue, 30000);
    expect(r.margin, 6000);
    expect(r.net, 1000);
    final rep = await repo.report(DateTime(t.year, t.month));
    expect(rep.net, 1000);
    expect(rep.topProducts.single.name, 'Riz 25 kg');
    expect(rep.basket, 30000);
  });

  test('la caisse suit ventes, dépenses et clôture', () async {
    await repo.setOpeningCash(10000);
    await repo.recordSale(lines: [CartLine(riz, 1)], paidNow: 15000);
    await repo.addExpense(label: 'Transport', amount: 2000);
    expect(await repo.cashBalance(), 23000);
    final gap = await repo.closeCash(counted: 22500, note: 'billet perdu');
    expect(gap, -500);
    expect(await repo.cashBalance(), 22500);
    expect(await repo.closedToday(), isTrue);
    expect(await repo.dailyReport(), contains('manque de 500 F'));
  });

  test('un retour remet en stock et rend l’argent', () async {
    final sale = await repo.recordSale(
      lines: [CartLine(riz, 3)],
      paidNow: 45000,
    );
    final line = (await repo.saleLinesOf(sale)).single.$1;
    final refund = await repo.returnItems(sale, {line.id: 1});
    expect(refund, 15000);
    expect(await repo.stockOf(riz.id), 8);
    final s = (await repo.sales()).single;
    expect(s.sale.total, 30000);
    expect(s.due, 0);
    expect(() => repo.returnItems(sale, {line.id: 2}), throwsArgumentError);
  });

  test('une vente hors stock ne touche pas le stock', () async {
    final nido = await repo.adHocProduct(
      name: 'Lait Nido',
      price: 5000,
      cost: 4000,
    );
    await repo.recordSale(
      lines: [CartLine(nido, 2), CartLine(riz, 1)],
      paidNow: 25000,
    );
    expect(await repo.stockOf(riz.id), 9);
    expect((await repo.products()).map((p) => p.name), ['Riz 25 kg']);
    final hs = await repo.adHocThisMonth();
    expect(hs!.count, 1);
    expect(hs.profit, 2000);
    final again = await repo.adHocProduct(name: 'lait nido', price: 5500);
    expect(again.id, nido.id);
    await repo.moveToStock(nido.id);
    expect((await repo.products()).length, 2);
  });

  test('les vendeurs ont leur code et leurs ventes', () async {
    final id = await repo.addSeller('Awa', '1234');
    final awa = (await repo.sellers()).single;
    expect(await repo.checkSellerPin(awa, '1234'), isTrue);
    expect(await repo.checkSellerPin(awa, '0000'), isFalse);
    expect(() => repo.addSeller('awa', '5555'), throwsArgumentError);
    await repo.recordSale(
      lines: [CartLine(riz, 1)],
      paidNow: 15000,
      sellerId: id,
    );
    await repo.recordSale(lines: [CartLine(riz, 1)], paidNow: 15000);
    final rep = await repo.report(DateTime(2000));
    expect(
      rep.sellers.map((s) => s.name),
      containsAll(['Awa', 'Propriétaire']),
    );
    await repo.removeSeller(id);
    expect(await repo.sellers(), isEmpty);
  });

  test('l’inventaire corrige le stock et compte la perte', () async {
    final gaps = await repo.inventoryGaps({riz.id: 7});
    expect(gaps.single.value, -36000);
    await repo.applyInventory({riz.id: 7}, lossAsExpense: true);
    expect(await repo.stockOf(riz.id), 7);
    expect((await repo.expenses()).single.amount, 36000);
    expect((await repo.inventories()).single.missingValue, 36000);
  });

  test('le plan de versements suit les échéances et les ventes', () async {
    final four = await repo.addContact('Grossiste', kind: 'fournisseur');
    final p1 = await repo.recordPurchase(
      supplierId: four,
      lines: [
        PurchaseLineInput(label: 'Riz', qty: 10, unitCost: 12000, product: riz),
      ],
      paidNow: 20000,
    );
    await repo.setPurchaseTerms(
      p1,
      terms: 'ventes',
      dueDate: DateTime.now().add(const Duration(days: 20)),
    );
    await repo.recordSale(lines: [CartLine(riz, 4)], paidNow: 60000);
    final plan = await repo.paymentPlan();
    // 4 vendus × 12 000 = 48 000, moins 20 000 déjà versés.
    expect(plan.firstWhere((r) => r.kind == 'ventes').amount, 28000);
    expect(plan.firstWhere((r) => r.kind == 'attente').amount, 72000);
  });

  test('la sauvegarde se restaure à l’identique', () async {
    await repo.recordSale(lines: [CartLine(riz, 2)], contactId: fatou);
    await repo.addExpense(label: 'Loyer', amount: 5000);
    final json = await repo.backupJson();
    final db2 = AppDatabase(NativeDatabase.memory());
    final repo2 = Repository(db2);
    await repo2.addProduct(name: 'À effacer', price: 1);
    await repo2.restoreJson(json);
    expect((await repo2.products()).single.name, 'Riz 25 kg');
    expect(await repo2.stockOf(riz.id), 8);
    expect((await repo2.debtors()).single.due, 30000);
    expect((await repo2.expenses()).single.label, 'Loyer');
    expect(() => repo2.restoreJson('{"x":1}'), throwsArgumentError);
    await db2.close();
  });

  test('export CSV pour Excel', () async {
    await repo.addExpense(label: 'Loyer; mars', amount: 5000);
    final csv = await repo.exportCsv('depenses');
    expect(csv, contains('"Loyer; mars"'));
    expect(csv.split('\r\n').length, 2);
  });

  test('une base de la version 4 reçoit la gestion', () async {
    final dir = await Directory.systemTemp.createTemp('flyfinance');
    final file = File('${dir.path}/v4.db');
    final old = AppDatabase(NativeDatabase(file));
    await Repository(old).addProduct(name: 'Sucre', price: 1000, initialQty: 3);
    for (final t in ['expenses', 'cash_closings', 'sellers', 'inventories']) {
      await old.customStatement('DROP TABLE $t');
    }
    for (final (t, c) in [
      ('products', 'ad_hoc'),
      ('sales', 'seller_id'),
      ('sale_lines', 'unit_cost'),
      ('purchases', 'due_date'),
      ('purchases', 'terms'),
    ]) {
      await old.customStatement('ALTER TABLE $t DROP COLUMN $c');
    }
    await old.customStatement('PRAGMA user_version = 4');
    await old.close();

    final db2 = AppDatabase(NativeDatabase(file));
    final r = Repository(db2);
    final sucre = (await r.products()).single;
    await r.recordSale(lines: [CartLine(sucre, 1)], paidNow: 1000);
    await r.addExpense(label: 'Loyer', amount: 500);
    expect(await r.expensesTotal(DateTime(2000)), 500);
    await db2.close();
    await dir.delete(recursive: true);
  });
}
