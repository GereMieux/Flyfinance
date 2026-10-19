import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/app_state.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/data/services_repository.dart';
import 'package:flyfinance/ui/services/services_screen.dart';
import 'package:flyfinance/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('espace prestation : tableau, factures et encaissement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final repo = Repository(db);
    final state = AppState(repo);
    await tester.runAsync(() async {
      final awa = await repo.addContact('Awa Traoré');
      await repo.createDoc(
        kind: DocKind.devis,
        contactId: awa,
        lines: [
          DocLineInput(label: 'Peinture salon', qty: 1, unitPrice: 80000),
        ],
      );
      await repo.createDoc(
        kind: DocKind.facture,
        contactId: awa,
        lines: [DocLineInput(label: 'Réparation', qty: 2, unitPrice: 15000)],
      );
    });

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: buildTheme(), home: const ServicesScreen()),
      ),
    );
    await settle();
    expect(find.text('Espace prestation'), findsOneWidget);
    // Facturé ce mois et reste à encaisser.
    expect(find.text('30.000 FCFA'), findsNWidgets(2));
    expect(find.text('1 · 80.000 FCFA'), findsOneWidget); // devis en attente

    await tester.tap(find.text('Factures'));
    await settle();
    expect(find.textContaining('FAC-'), findsOneWidget);
    await tester.tap(find.text('Awa Traoré'));
    await settle();
    expect(find.text('Encaisser 30.000 FCFA'), findsOneWidget);
    await tester.tap(find.text('Encaisser 30.000 FCFA'));
    await settle();
    await tester.tap(find.text('Wave'));
    await tester.tap(find.widgetWithText(FilledButton, 'Encaisser'));
    await settle();
    expect(find.text('Payée'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('nouveau devis : client, ligne libre, enregistrement', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final repo = Repository(db);
    await tester.runAsync(() => repo.addContact('Koffi Yao'));

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: AppState(repo),
        child: MaterialApp(theme: buildTheme(), home: const ServicesScreen()),
      ),
    );
    await settle();
    await tester.tap(find.text('Faire un devis'));
    await settle();
    await tester.tap(find.text('Choisir ou ajouter un client'));
    await settle();
    await tester.tap(find.text('Koffi Yao'));
    await settle();
    await tester.tap(find.text('Ajouter un travail'));
    await settle();
    final fields = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'Main d’œuvre');
    await tester.enterText(fields.at(1), '2,5');
    await tester.enterText(fields.at(2), '10000');
    await tester.tap(find.text('Valider'));
    await settle();
    expect(find.text('25.000 FCFA'), findsWidgets);
    await tester.tap(find.text('Enregistrer · 25.000 FCFA'));
    await settle();
    expect(find.text('DEV-${DateTime.now().year}-0001'), findsOneWidget);
    expect(find.text('Le client accepte : faire la facture'), findsOneWidget);
    await tester.tap(find.text('Le client accepte : faire la facture'));
    await settle();
    expect(find.text('FAC-${DateTime.now().year}-0001'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
