import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/data/services_repository.dart';
import 'package:flyfinance/services/doc_pdf.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late Repository repo;
  late int awa;
  var clock = DateTime(2026, 10, 19, 10);

  final lines = [
    DocLineInput(
      label: 'Pose de carrelage',
      qty: 12.5,
      unit: 'm²',
      unitPrice: 4000,
    ),
    DocLineInput(label: 'Déplacement', qty: 1, unitPrice: 5000),
  ];

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = Repository(db)..now = () => clock;
    clock = DateTime(2026, 10, 19, 10);
    awa = await repo.addContact('Awa Traoré', phone: '0700000000');
  });

  tearDown(() => db.close());

  test('totaux avec remise et TVA', () {
    final t = DocTotals.of(lines, 5000, 18);
    expect(t.subtotal, 55000);
    expect(t.net, 50000);
    expect(t.tax, 9000);
    expect(t.total, 59000);
  });

  test('numérotation continue par type et par année', () async {
    final d1 = await repo.createDoc(
      kind: DocKind.devis,
      contactId: awa,
      lines: lines,
    );
    final d2 = await repo.createDoc(
      kind: DocKind.devis,
      contactId: awa,
      lines: lines,
    );
    final f1 = await repo.createDoc(
      kind: DocKind.facture,
      contactId: awa,
      lines: lines,
    );
    expect((await repo.doc(d1)).doc.number, 'DEV-2026-0001');
    expect((await repo.doc(d2)).doc.number, 'DEV-2026-0002');
    expect((await repo.doc(f1)).doc.number, 'FAC-2026-0001');
    clock = DateTime(2027, 1, 2);
    final d3 = await repo.createDoc(
      kind: DocKind.devis,
      contactId: awa,
      lines: lines,
    );
    expect((await repo.doc(d3)).doc.number, 'DEV-2027-0001');
  });

  test('un devis accepté devient une facture, une seule fois', () async {
    final q = await repo.createDoc(
      kind: DocKind.devis,
      contactId: awa,
      lines: lines,
      taxRate: 18,
      dueAt: DateTime(2026, 11, 1),
    );
    expect((await repo.doc(q)).status, DocStatus.brouillon);
    await repo.setQuoteStatus(q, 'envoye');
    expect((await repo.doc(q)).status, DocStatus.envoye);
    final f = await repo.invoiceFromQuote(q);
    expect(await repo.invoiceFromQuote(q), f);
    final inv = await repo.doc(f);
    expect(inv.doc.total, 64900);
    expect(inv.lines.length, 2);
    expect(inv.doc.sourceId, q);
    expect((await repo.doc(q)).status, DocStatus.facture);
    expect((await repo.doc(q)).pendingQuote, isFalse);
  });

  test('un devis non accepté expire après sa date', () async {
    final q = await repo.createDoc(
      kind: DocKind.devis,
      contactId: awa,
      lines: lines,
      dueAt: DateTime(2026, 10, 20),
    );
    expect((await repo.doc(q)).status, DocStatus.brouillon);
    clock = DateTime(2026, 10, 21);
    expect((await repo.doc(q)).status, DocStatus.expire);
  });

  test('paiements partiels, retard et solde', () async {
    final f = await repo.createDoc(
      kind: DocKind.facture,
      contactId: awa,
      lines: lines,
      dueAt: DateTime(2026, 10, 25),
    );
    expect((await repo.doc(f)).status, DocStatus.impayee);
    expect(await repo.payInvoice(f, 20000, method: 'wave'), 20000);
    expect((await repo.doc(f)).status, DocStatus.partielle);
    clock = DateTime(2026, 10, 26);
    var s = await repo.doc(f);
    expect(s.status, DocStatus.enRetard);
    expect(s.due, 35000);
    final dash = await repo.servicesDashboard();
    expect(dash.outstanding, 35000);
    expect(dash.overdue.single.doc.id, f);
    expect(dash.invoicedMonth, 55000);
    expect(dash.cashInMonth, 20000);
    expect(await repo.payInvoice(f, 99999), 35000);
    s = await repo.doc(f);
    expect(s.status, DocStatus.payee);
    expect(await repo.payInvoice(f, 1000), 0);
  });

  test('modifier une facture ne descend pas sous ce qui est payé', () async {
    final f = await repo.createDoc(
      kind: DocKind.facture,
      contactId: awa,
      lines: lines,
    );
    await repo.payInvoice(f, 30000);
    expect(
      () => repo.updateDoc(
        f,
        contactId: awa,
        lines: [DocLineInput(label: 'Petit travail', qty: 1, unitPrice: 10000)],
      ),
      throwsStateError,
    );
    await repo.updateDoc(f, contactId: awa, lines: lines, discount: 5000);
    expect((await repo.doc(f)).doc.total, 50000);
  });

  test('une facture annulée ne compte plus', () async {
    final f = await repo.createDoc(
      kind: DocKind.facture,
      contactId: awa,
      lines: lines,
    );
    await repo.cancelInvoice(f);
    final s = await repo.doc(f);
    expect(s.status, DocStatus.annulee);
    expect(s.due, 0);
    expect((await repo.servicesDashboard()).outstanding, 0);
    expect(() => repo.deleteQuote(f), throwsStateError);
  });

  test('supprimer et dupliquer un devis', () async {
    final q = await repo.createDoc(
      kind: DocKind.devis,
      contactId: awa,
      lines: lines,
    );
    final copy = await repo.duplicateDoc(q);
    expect((await repo.doc(copy)).lines.length, 2);
    await repo.deleteQuote(q);
    expect((await repo.docs(kind: DocKind.devis)).single.doc.id, copy);
  });

  test('refuse un document vide', () {
    expect(
      () => repo.createDoc(kind: DocKind.devis, contactId: awa, lines: []),
      throwsArgumentError,
    );
  });

  test('catalogue, agenda et fiche entreprise', () async {
    final id = await repo.addService(name: 'Vidange', price: 15000);
    await repo.updateService(
      id,
      name: 'Vidange complète',
      price: 18000,
      unit: 'forfait',
    );
    expect((await repo.services()).single.price, 18000);
    await repo.archiveService(id);
    expect(await repo.services(), isEmpty);

    await repo.addAppointment(
      title: 'Chantier Cocody',
      at: DateTime(2026, 10, 20, 8),
      contactId: awa,
    );
    await repo.addAppointment(title: 'Ancien', at: DateTime(2026, 10, 1));
    final dash = await repo.servicesDashboard();
    expect(dash.upcoming.single.appointment.title, 'Chantier Cocody');
    expect(dash.upcoming.single.contact?.name, 'Awa Traoré');

    await repo.saveBusinessInfo({
      'biz.name': 'Koffi Services',
      'biz.phone': '',
    });
    expect(await repo.businessInfo(), {'biz.name': 'Koffi Services'});
  });

  test('PDF et message WhatsApp', () async {
    final f = await repo.createDoc(
      kind: DocKind.facture,
      contactId: awa,
      lines: lines,
      taxRate: 18,
    );
    await repo.payInvoice(f, 10000);
    final s = await repo.doc(f);
    final bytes = await buildDocPdf(s, {'biz.name': 'Koffi Services'});
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final msg = docMessage(s, {'biz.name': 'Koffi Services'});
    expect(msg, contains('FAC-2026-0001'));
    expect(msg, contains('Reste à payer : 54.900 FCFA'));
    expect(qtyText(12.5), '12,5');
    expect(qtyText(2), '2');
  });

  test('une base de la version 1 reçoit les tables de prestation', () async {
    final dir = await Directory.systemTemp.createTemp('flyfinance');
    final file = File('${dir.path}/v1.db');
    // Base « ancienne » : on retire les tables de prestation et on la
    // marque version 1.
    final old = AppDatabase(NativeDatabase(file));
    await Repository(old).addContact('Ancien client');
    for (final t in [
      'service_payments',
      'service_doc_lines',
      'service_docs',
      'services',
      'appointments',
      'settings',
    ]) {
      await old.customStatement('DROP TABLE $t');
    }
    await old.customStatement('PRAGMA user_version = 1');
    await old.close();

    final db2 = AppDatabase(NativeDatabase(file));
    final r = Repository(db2);
    final c = (await r.contacts()).single;
    final id = await r.createDoc(
      kind: DocKind.facture,
      contactId: c.id,
      lines: lines,
    );
    expect((await r.doc(id)).doc.total, 55000);
    await db2.close();
    await dir.delete(recursive: true);
  });
}
