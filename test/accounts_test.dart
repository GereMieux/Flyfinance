import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/data/accounts_repository.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/data/services_repository.dart';

import 'old_schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late Repository repo;
  late Product riz;
  late int fatou;
  late int sotici;
  var clock = DateTime(2026, 10, 1, 10);

  setUp(() async {
    clock = DateTime(2026, 10, 1, 10);
    db = AppDatabase(NativeDatabase.memory());
    repo = Repository(db)..now = () => clock;
    final id = await repo.addProduct(
      name: 'Riz 25 kg',
      price: 15000,
      cost: 12000,
      initialQty: 2,
    );
    riz = (await repo.products()).firstWhere((p) => p.id == id);
    fatou = await repo.addContact(
      'Fatou Koné',
      phone: '0707070707',
      address: 'Adjamé, près du marché',
    );
    sotici = await repo.addContact('SOTICI', kind: 'fournisseur');
  });

  tearDown(() => db.close());

  group('fournisseurs', () {
    test('un achat entre en stock et met à jour le prix d’achat', () async {
      await repo.recordPurchase(
        supplierId: sotici,
        lines: [
          PurchaseLineInput(
            product: riz,
            label: riz.name,
            qty: 10,
            unitCost: 12500,
          ),
          PurchaseLineInput(label: 'Transport', qty: 1, unitCost: 5000),
        ],
        paidNow: 50000,
        method: 'wave',
        reference: 'BL-118',
      );
      expect(await repo.stockOf(riz.id), 12);
      expect((await repo.products()).single.cost, 12500);
      final a = await repo.supplierAccount(sotici);
      expect(a.bought, 130000);
      expect(a.paid, 50000);
      expect(a.balance, 80000);
      expect(a.purchases.single.status, PurchaseStatus.partiel);
      expect(a.moves.map((m) => m.title), containsAll(['Achat', 'Versement']));
      expect(await repo.supplierDebt(), 80000);
    });

    test('les versements soldent les achats les plus anciens', () async {
      await repo.recordPurchase(
        supplierId: sotici,
        lines: [PurchaseLineInput(label: 'Lot A', qty: 1, unitCost: 30000)],
      );
      clock = clock.add(const Duration(days: 1));
      await repo.recordPurchase(
        supplierId: sotici,
        lines: [PurchaseLineInput(label: 'Lot B', qty: 1, unitCost: 20000)],
      );
      await repo.paySupplier(sotici, 40000, method: 'virement');
      final a = await repo.supplierAccount(sotici);
      // Du plus récent au plus ancien.
      expect(a.purchases[1].status, PurchaseStatus.paye);
      expect(a.purchases[0].status, PurchaseStatus.partiel);
      expect(a.purchases[0].due, 10000);
      await repo.paySupplier(sotici, 15000);
      expect((await repo.supplierAccount(sotici)).balance, -5000);
    });

    test('annuler un achat ressort le stock, sauf s’il est vendu', () async {
      final id = await repo.recordPurchase(
        supplierId: sotici,
        lines: [
          PurchaseLineInput(
            product: riz,
            label: riz.name,
            qty: 3,
            unitCost: 12000,
          ),
        ],
      );
      await repo.recordSale(lines: [CartLine(riz, 4)], paidNow: 60000);
      await expectLater(repo.cancelPurchase(id), throwsStateError);
      await repo.adjustStock(riz.id, 5, 'achat');
      await repo.cancelPurchase(id);
      expect(await repo.stockOf(riz.id), 3);
      final a = await repo.supplierAccount(sotici);
      expect(a.bought, 0);
      expect(a.purchases.single.status, PurchaseStatus.annule);
    });

    test('un versement annulé n’est plus compté', () async {
      final v = await repo.paySupplier(sotici, 10000);
      await repo.cancelEntry(v);
      expect((await repo.supplierAccount(sotici)).paid, 0);
    });
  });

  group('clients', () {
    test('le compte montre achats, versements et reste à payer', () async {
      await repo.recordSale(
        lines: [CartLine(riz, 2)],
        contactId: fatou,
        paidNow: 10000,
        method: 'orange',
      );
      await repo.receivePayment(fatou, 5000);
      final a = await repo.clientAccount(fatou);
      expect(a.contact.address, 'Adjamé, près du marché');
      expect(a.bought, 30000);
      expect(a.paid, 15000);
      expect(a.due, 15000);
      expect(a.moves.length, 3);
    });

    test('la provision règle les ventes puis les factures', () async {
      await repo.recordSale(lines: [CartLine(riz, 1)], contactId: fatou);
      final f = await repo.createDoc(
        kind: DocKind.facture,
        contactId: fatou,
        lines: [DocLineInput(label: 'Livraison', qty: 1, unitPrice: 5000)],
      );
      await repo.addProvision(fatou, 25000, method: 'wave');
      expect(await repo.provisionOf(fatou), 25000);
      expect(await repo.useProvision(fatou), 20000);
      final a = await repo.clientAccount(fatou);
      expect(a.due, 0);
      expect(a.provision, 5000);
      expect((await repo.doc(f)).status, DocStatus.payee);
      expect(
        a.moves.map((m) => m.title),
        containsAll(['Provision déposée', 'Provision utilisée']),
      );
      await expectLater(repo.returnProvision(fatou, 6000), throwsStateError);
      await repo.returnProvision(fatou, 5000);
      expect(await repo.provisionOf(fatou), 0);
    });

    test('l’encaissé compte la provision une seule fois', () async {
      await repo.addProvision(fatou, 15000);
      await repo.recordSale(lines: [CartLine(riz, 1)], contactId: fatou);
      await repo.useProvision(fatou);
      final day = DateTime(2026, 10, 1);
      expect((await repo.statsSince(day)).cashIn, 15000);
    });

    test('une provision utilisée ne s’annule pas', () async {
      final p = await repo.addProvision(fatou, 15000);
      await repo.recordSale(lines: [CartLine(riz, 1)], contactId: fatou);
      await repo.useProvision(fatou);
      await expectLater(repo.cancelEntry(p), throwsStateError);
    });

    test('le carnet d’adresses se modifie', () async {
      await repo.updateContact(
        fatou,
        name: 'Fatou K.',
        phone: '0101010101',
        address: '',
      );
      final c = await repo.contact(fatou);
      expect(c.name, 'Fatou K.');
      expect(c.address, isNull);
    });
  });

  group('relances', () {
    test('après le délai, à l’heure choisie, puis tous les X jours', () async {
      await repo.saveReminderSettings(
        const ReminderSettings(afterDays: 3, everyDays: 2, hour: 9),
      );
      await repo.recordSale(lines: [CartLine(riz, 1)], contactId: fatou);
      clock = DateTime(2026, 10, 3, 10);
      expect(await repo.remindersDue(), isEmpty, reason: 'trop tôt');
      clock = DateTime(2026, 10, 4, 8);
      expect(await repo.remindersDue(), isEmpty, reason: 'avant 9 h');
      clock = DateTime(2026, 10, 4, 9, 5);
      final due = await repo.remindersDue();
      expect(due.single.debtor.contact.id, fatou);
      await repo.markReminded(fatou);
      clock = DateTime(2026, 10, 5, 10);
      expect(await repo.remindersDue(), isEmpty);
      clock = DateTime(2026, 10, 6, 10);
      expect(await repo.remindersDue(), hasLength(1));
      final s = await repo.reminderSettings();
      expect(
        s.messageFor('Fatou', '15.000 FCFA'),
        contains('Bonjour Fatou, petit rappel : il reste 15.000 FCFA'),
      );
    });

    test('désactivées, rien n’est proposé', () async {
      await repo.saveReminderSettings(
        const ReminderSettings(enabled: false, afterDays: 0),
      );
      await repo.recordSale(lines: [CartLine(riz, 1)], contactId: fatou);
      clock = DateTime(2026, 10, 9, 12);
      expect(await repo.remindersDue(), isEmpty);
    });
  });

  test('une base de la version 2 reçoit les comptes', () async {
    final dir = await Directory.systemTemp.createTemp('flyfinance');
    final file = File('${dir.path}/v2.db');
    final old = AppDatabase(NativeDatabase(file));
    final r1 = Repository(old);
    await r1.addProduct(name: 'Sucre', price: 1000, initialQty: 4);
    await r1.addContact('Ancien client', phone: '0102030405');
    await downgradeToV2(old);
    await old.close();

    final db2 = AppDatabase(NativeDatabase(file));
    final r = Repository(db2);
    final sucre = (await r.products()).single;
    expect(await r.stockOf(sucre.id), 4);
    final c = (await r.contacts()).single;
    expect(c.phone, '0102030405');
    expect(c.address, isNull);
    final f = await r.addContact('Grossiste', kind: 'fournisseur');
    await r.recordPurchase(
      supplierId: f,
      lines: [
        PurchaseLineInput(
          product: sucre,
          label: 'Sucre',
          qty: 6,
          unitCost: 800,
        ),
      ],
    );
    expect(await r.stockOf(sucre.id), 10);
    await db2.close();
    await dir.delete(recursive: true);
  });
}
