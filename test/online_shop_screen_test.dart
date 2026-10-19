import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/app_state.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/data/shop_database.dart';
import 'package:flyfinance/data/shop_repository.dart';
import 'package:flyfinance/ui/online_shop_screen.dart';
import 'package:flyfinance/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('espace vente en ligne : onglets, vitrine et commande', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final shopDb = ShopDatabase(NativeDatabase.memory());
    final repo = Repository(db);
    final shop = ShopRepository(shopDb, repo);
    await tester.runAsync(() async {
      final id = await repo.addProduct(
        name: 'Robe wax',
        price: 20000,
        initialQty: 4,
      );
      await shop.saveItem(
        productId: id,
        category: 'Vêtements',
        sizes: ['M', 'L'],
        colors: ['Bleu'],
      );
      await shop.addPromotion(
        title: 'Soldes',
        percent: 20,
        isSale: true,
        startsAt: DateTime.now().subtract(const Duration(days: 1)),
        endsAt: DateTime.now().add(const Duration(days: 6)),
      );
      await shop.saveInfo({'wave_number': '0707000001'});
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => AppState(repo)),
          Provider.value(value: shop),
        ],
        child: MaterialApp(theme: buildTheme(), home: const OnlineShopScreen()),
      ),
    );
    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
    }

    await settle();
    expect(find.text('Nouvelle commande'), findsOneWidget);

    await tester.tap(find.text('Catalogue'));
    await settle();
    expect(find.text('Robe wax'), findsOneWidget);
    expect(find.text('16.000 FCFA'), findsOneWidget);

    await tester.tap(find.text('Promos'));
    await settle();
    expect(find.text('En cours'), findsOneWidget);

    await tester.tap(find.text('Annonces'));
    await settle();
    expect(find.text('Nouvelle annonce'), findsOneWidget);

    await tester.tap(find.byTooltip('Voir la vitrine comme un client'));
    await settle();
    expect(find.text('Vitrine'), findsOneWidget);
    expect(find.text('Wave'), findsOneWidget);
    await tester.pageBack();
    await settle();

    await tester.tap(find.text('Commandes'));
    await settle();
    await tester.tap(find.text('Nouvelle commande'));
    await settle();
    expect(find.text('Enregistrer la commande'), findsOneWidget);
    expect(find.text('Wave'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await db.close();
      await shopDb.close();
    });
  });
}
