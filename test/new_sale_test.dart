import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/app_state.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/security/lock_service.dart';
import 'package:flyfinance/ui/day_sales_screen.dart';
import 'package:flyfinance/ui/new_sale_screen.dart';
import 'package:flyfinance/ui/theme.dart';
import 'package:flyfinance/ui/trash_screen.dart';
import 'package:provider/provider.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('vente à un nouveau client via les barres de saisie', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final repo = Repository(db);
    await tester.runAsync(() async {
      await repo.addProduct(name: 'Riz 25 kg', price: 15000, initialQty: 10);
      await repo.addProduct(name: 'Huile 5 L', price: 6000, initialQty: 4);
      await repo.addContact('Fatou Koné');
    });

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(repo),
        child: MaterialApp(
          theme: buildTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const NewSaleScreen()),
                  ),
                  child: const Text('Ouvrir'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Ouvrir'));
    await settle();

    // Barre article : taper « riz » propose l'article, le toucher l'ajoute.
    await tester.enterText(
      find.widgetWithText(TextField, 'Taper le nom de l’article'),
      'riz',
    );
    await tester.pumpAndSettle();
    expect(find.text('10 en stock'), findsOneWidget);
    await tester.tap(find.text('10 en stock'));
    await tester.pumpAndSettle();
    expect(find.text('Panier · 1 article'), findsOneWidget);
    expect(find.text('15.000 FCFA × 1 = 15.000 FCFA'), findsOneWidget);

    // Barre client : un nom inconnu propose d'ajouter un nouveau client.
    await tester.tap(find.text('Client connu'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Nom du client'),
      'Awa Traoré',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Nouveau client : « Awa Traoré »'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '0700000000');
    await tester.tap(find.text('Ajouter'));
    await tester.pumpAndSettle();
    expect(find.text('Nouveau client · 0700000000'), findsOneWidget);

    await tester.tap(find.text('À crédit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Valider la vente'));
    await settle();

    final sale = (await tester.runAsync(repo.sales))!.single;
    expect(sale.contact!.name, 'Awa Traoré');
    expect(sale.contact!.phone, '0700000000');
    expect(sale.due, 15000);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('détail des ventes du jour', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final repo = Repository(db);
    await tester.runAsync(() async {
      final id = await repo.addProduct(
        name: 'Riz 25 kg',
        price: 15000,
        cost: 12000,
        initialQty: 10,
      );
      final riz = (await repo.products()).firstWhere((p) => p.id == id);
      await repo.recordSale(lines: [CartLine(riz, 2)], paidNow: 30000);
    });

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(repo),
        child: MaterialApp(theme: buildTheme(), home: const DaySalesScreen()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.text("Ventes d'aujourd'hui"), findsOneWidget);
    expect(find.text('6.000 FCFA'), findsOneWidget); // bénéfice du jour
    expect(find.text('2 vendus'), findsOneWidget);
    await tester.tap(find.text('Client de passage'));
    await tester.pumpAndSettle();
    expect(find.text('2 × Riz 25 kg'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('la corbeille montre les ventes annulées', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final repo = Repository(db);
    await tester.runAsync(() async {
      final id = await repo.addProduct(
        name: 'Riz 25 kg',
        price: 15000,
        initialQty: 10,
      );
      final riz = (await repo.products()).firstWhere((p) => p.id == id);
      final sale = await repo.recordSale(
        lines: [CartLine(riz, 2)],
        paidNow: 30000,
      );
      await repo.cancelSale(sale);
    });
    final app = AppState(repo);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(theme: buildTheme(), home: const TrashScreen()),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pumpAndSettle();

    expect(find.text("Aujourd'hui : 1 vente annulée"), findsOneWidget);
    expect(app.cancellationsSeenAt, isNotNull);
    await tester.tap(find.text('Client de passage'));
    await tester.pumpAndSettle();
    expect(find.text('2 × Riz 25 kg'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });

  testWidgets('vider la corbeille demande le code secret', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final repo = Repository(db);
    final lock = LockService(MemorySecretStore());
    await tester.runAsync(() async {
      await lock.setPin('2580');
      final id = await repo.addProduct(
        name: 'Riz 25 kg',
        price: 15000,
        initialQty: 10,
      );
      final riz = (await repo.products()).firstWhere((p) => p.id == id);
      await repo.cancelSale(
        await repo.recordSale(lines: [CartLine(riz, 1)], paidNow: 15000),
      );
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState(repo)),
          ChangeNotifierProvider.value(value: lock),
        ],
        child: MaterialApp(theme: buildTheme(), home: const TrashScreen()),
      ),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
    }

    await settle();

    Future<void> tryEmpty(String code) async {
      await tester.tap(find.byTooltip('Vider la corbeille'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), code);
      await tester.tap(find.text('Vider'));
      await settle();
    }

    await tryEmpty('1111');
    expect(
      find.text('Code incorrect. La corbeille n’a pas été vidée.'),
      findsOneWidget,
    );
    expect(await tester.runAsync(repo.cancelledSales), hasLength(1));

    await tryEmpty('2580');
    expect(await tester.runAsync(repo.cancelledSales), isEmpty);
    expect(find.text('Aucune vente annulée.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
