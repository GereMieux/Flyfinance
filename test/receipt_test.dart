import 'dart:io';

import 'package:drift/drift.dart' show Uint8List, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/receipt_repository.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/data/services_repository.dart';
import 'package:flutter/material.dart';
import 'package:flyfinance/services/receipt_pdf.dart';
import 'package:flyfinance/ui/theme.dart';
import 'package:flyfinance/ui/widgets.dart';
import 'package:pdf/widgets.dart' as pw;

final logo = File('test/fixtures/logo.png').readAsBytesSync();

ReceiptFonts fonts() {
  pw.Font f(String n) => pw.Font.ttf(
    File('assets/fonts/$n.ttf').readAsBytesSync().buffer.asByteData(),
  );
  return ReceiptFonts(
    f('Inter-Regular'),
    f('Inter-SemiBold'),
    f('Inter-Bold'),
    f('Rajdhani-Bold'),
  );
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late Repository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = Repository(db);
  });
  tearDown(() => db.close());

  test('le reçu d’une vente reprend lignes, client et paiements', () async {
    final id = await repo.addProduct(
      name: 'Riz 25 kg',
      price: 15000,
      initialQty: 10,
    );
    final riz = (await repo.products()).firstWhere((p) => p.id == id);
    final awa = await repo.addContact('Awa Traoré', phone: '0700000000');
    final sale = await repo.recordSale(
      lines: [CartLine(riz, 3)],
      contactId: awa,
      paidNow: 20000,
      method: 'wave',
    );
    final r = await repo.saleReceipt(sale);
    expect(r.number, 'V-${sale.toString().padLeft(6, '0')}');
    expect(r.clientName, 'Awa Traoré');
    expect(r.lines.single.total, 45000);
    expect(r.total, 45000);
    expect(r.payments.single.method, 'Wave');
    expect(r.due, 25000);
    expect(r.as(ReceiptKind.livraison).kind, ReceiptKind.livraison);
  });

  test('logo, modèle et phrase de fin sont gardés', () async {
    expect((await repo.brand()).style, ReceiptStyle.neon);
    await repo.saveBrand(
      logo: logo,
      style: ReceiptStyle.aurore,
      paper: PaperSize.ticket58,
      thanks: 'À demain !',
    );
    final b = await repo.brand();
    expect(b.logo, logo);
    expect(b.style, ReceiptStyle.aurore);
    expect(b.paper, PaperSize.ticket58);
    expect(b.thanksFor('V-000001'), 'À demain !');
    // Les réglages d'apparence ne se mélangent pas à la fiche entreprise.
    expect(await repo.businessInfo(), isEmpty);

    await repo.saveBrand(
      logo: null,
      style: ReceiptStyle.epure,
      paper: PaperSize.a4,
      thanks: '',
    );
    final c = await repo.brand();
    expect(c.logo, isNull);
    expect(thanksIdeas, contains(c.thanksFor('V-000001')));
  });

  test('tous les documents, modèles et papiers se construisent', () async {
    final data = ReceiptData(
      kind: ReceiptKind.recu,
      number: 'V-000128',
      date: DateTime(2026, 10, 19, 18, 30),
      clientName: 'Awa Traoré',
      clientPhone: '07 00 00 00 00',
      lines: const [
        ReceiptLine('Riz parfumé 25 kg', 2, 'sac', 15000),
        ReceiptLine('Huile 5 L', 1.5, 'bidon', 6000),
      ],
      subtotal: 39000,
      discount: 1000,
      taxRate: 18,
      tax: 6840,
      total: 44840,
      payments: [ReceiptPayment('Wave', 20000, DateTime(2026, 10, 19))],
      note: 'Livraison à Cocody — merci !',
    );
    final biz = {
      'biz.name': 'Boutique Chez Awa',
      'biz.phone': '07 00 00 00 00',
      'biz.address': 'Abidjan, Cocody',
    };
    final f = fonts();
    for (final kind in ReceiptKind.values) {
      for (final style in ReceiptStyle.values) {
        for (final paper in PaperSize.values) {
          final bytes = await buildReceiptPdf(
            data.as(kind),
            biz,
            BrandSettings(logo: logo, style: style),
            paper: paper,
            fonts: f,
          );
          expect(String.fromCharCodes(bytes.take(4)), '%PDF');
        }
      }
    }
    // Un logo illisible ne bloque pas le reçu.
    final broken = await buildReceiptPdf(
      data,
      biz,
      BrandSettings(logo: Uint8List.fromList([1, 2, 3])),
      fonts: f,
    );
    expect(String.fromCharCodes(broken.take(4)), '%PDF');

    // Sans polices embarquées, les caractères spéciaux sont remplacés.
    final plain = await buildReceiptPdf(
      data,
      biz,
      const BrandSettings(),
      paper: PaperSize.a4,
    );
    expect(String.fromCharCodes(plain.take(4)), '%PDF');

    // Exemples à regarder (variable FLYFINANCE_SAMPLES=dossier).
    final out = Platform.environment['FLYFINANCE_SAMPLES'];
    if (out != null) {
      for (final style in ReceiptStyle.values) {
        for (final (kind, paper) in [
          (ReceiptKind.recu, PaperSize.ticket80),
          (ReceiptKind.facture, PaperSize.a4),
        ]) {
          final bytes = await buildReceiptPdf(
            data.as(kind),
            biz,
            BrandSettings(logo: logo, style: style),
            paper: paper,
            fonts: f,
          );
          File('$out/${style.name}_${paper.name}.pdf').writeAsBytesSync(bytes);
        }
      }
    }
  });

  testWidgets('pavé numérique : taper 12 puis Valider', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    int? result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async => result = await askQuantity(
                context,
                title: 'Riz 25 kg',
                unitPrice: 15000,
                initial: 1,
                max: 20,
              ),
              child: const Text('Ouvrir'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    Finder key(String k) => find.text(k).last;
    await tester.tap(key('1'));
    await tester.tap(key('2'));
    await tester.pump();
    expect(find.text('= 180.000 FCFA'), findsOneWidget);
    await tester.tap(key('2'));
    await tester.pump();
    expect(find.text('Maximum 20'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();
    expect(result, 12);
  });
}
