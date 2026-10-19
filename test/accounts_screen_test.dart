import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/app_state.dart';
import 'package:flyfinance/data/accounts_repository.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/ui/accounts/broadcast_screen.dart';
import 'package:flyfinance/ui/accounts/contacts_screen.dart';
import 'package:flyfinance/ui/accounts/reminders_screen.dart';
import 'package:flyfinance/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Repository repo;

  Future<void> start(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: AppState(repo),
        child: MaterialApp(theme: buildTheme(), home: home),
      ),
    );
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  }

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = Repository(db);
  });

  testWidgets('carnet : nouveau client avec adresse, puis son compte', (
    tester,
  ) async {
    await start(tester, const ContactsScreen());
    await settle(tester);
    expect(
      find.text('Aucun client.\nTouchez « Client » pour en ajouter un.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Client'));
    await settle(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Nom'), 'Aya Bamba');
    await tester.enterText(
      find.widgetWithText(TextField, 'Téléphone'),
      '0505050505',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Adresse'),
      'Yopougon Selmer',
    );
    await tester.tap(find.text('Enregistrer'));
    await settle(tester);

    expect(find.text('Compte client'), findsOneWidget);
    expect(find.text('Yopougon Selmer'), findsOneWidget);
    expect(find.text('Compte à jour'), findsOneWidget);

    await tester.tap(find.text('Provision').last);
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, '20000');
    await tester.tap(find.text('Wave'));
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await settle(tester);
    expect(find.text('Provision déposée'), findsOneWidget);
    expect(find.text('+ 20.000 FCFA'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('fournisseur : achat à crédit puis versement', (tester) async {
    await tester.runAsync(() async {
      await repo.addProduct(name: 'Huile 5 L', price: 6500, cost: 5000);
      await repo.addContact('SOTICI', kind: 'fournisseur');
    });
    await start(tester, const ContactsScreen(suppliers: true));
    await settle(tester);
    await tester.tap(find.text('SOTICI'));
    await settle(tester);
    expect(find.text('Compte fournisseur'), findsOneWidget);

    await tester.tap(find.text('Nouvel achat'));
    await settle(tester);
    await tester.tap(find.text('Article'));
    await settle(tester);
    await tester.tap(find.text('Huile 5 L'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Quantité reçue'),
      '10',
    );
    await tester.tap(find.text('Ajouter'));
    await settle(tester);
    expect(find.text('50.000 FCFA'), findsWidgets);
    await tester.tap(find.text('À crédit'));
    await tester.pump();
    await tester.ensureVisible(find.text('Enregistrer l’achat'));
    await tester.tap(find.text('Enregistrer l’achat'));
    await settle(tester);
    expect(find.text('Achat enregistré'), findsOneWidget);
    await tester.tap(find.text('Plus tard'));
    await settle(tester);

    expect(find.text('Je lui dois'), findsOneWidget);
    expect(find.text('50.000 FCFA'), findsWidgets);
    final stock = await tester.runAsync(() => repo.stock());
    expect(stock!.single.qty, 10);

    await tester.tap(find.text('Versement'));
    await settle(tester);
    await tester.tap(find.text('Orange Money'));
    await tester.tap(find.widgetWithText(FilledButton, 'Enregistrer'));
    await settle(tester);
    expect(find.text('Compte à jour'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('relances : le client en retard apparaît', (tester) async {
    await tester.runAsync(() async {
      final p = await repo.addProduct(
        name: 'Riz 25 kg',
        price: 15000,
        initialQty: 5,
      );
      final c = await repo.addContact('Koffi', phone: '0707070707');
      final riz = (await repo.products()).firstWhere((x) => x.id == p);
      repo.now = () => DateTime.now().subtract(const Duration(days: 10));
      await repo.recordSale(lines: [CartLine(riz, 1)], contactId: c);
      repo.now = DateTime.now;
      await repo.saveReminderSettings(
        const ReminderSettings(afterDays: 3, hour: 0),
      );
    });
    await start(tester, const RemindersScreen());
    await settle(tester);
    expect(find.text('À relancer maintenant (1)'), findsOneWidget);
    expect(find.text('Koffi'), findsOneWidget);
    expect(find.text('Jamais relancé'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('annonce : message d’arrivage prérempli', (tester) async {
    await tester.runAsync(
      () => repo.addContact('Aya', phone: '0505050505', address: 'Cocody'),
    );
    await start(
      tester,
      BroadcastScreen(initialText: arrivalMessage(['Huile 5 L', 'Riz'])),
    );
    await settle(tester);
    expect(
      find.textContaining('Nouvel arrivage à la boutique : Huile 5 L, Riz'),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Ou un par un (1)'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Ou un par un (1)'), findsOneWidget);
    expect(
      clientsVcard(await tester.runAsync(() => repo.contacts()) ?? []),
      contains('TEL;TYPE=CELL:+2250505050505'),
    );
    await finish(tester);
  });
}
