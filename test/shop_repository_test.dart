import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/data/shop_database.dart';
import 'package:flyfinance/data/shop_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late ShopDatabase shopDb;
  late Repository repo;
  late ShopRepository shop;
  late int robe, basket;
  var t = DateTime(2026, 10, 19, 10);

  setUp(() async {
    t = DateTime(2026, 10, 19, 10);
    db = AppDatabase(NativeDatabase.memory());
    shopDb = ShopDatabase(NativeDatabase.memory());
    repo = Repository(db)..now = () => t;
    shop = ShopRepository(shopDb, repo);
    robe = await repo.addProduct(
      name: 'Robe wax',
      price: 20000,
      cost: 12000,
      initialQty: 5,
    );
    basket = await repo.addProduct(
      name: 'Baskets',
      price: 30000,
      cost: 20000,
      initialQty: 2,
    );
    await shop.saveItem(
      productId: robe,
      category: 'Vêtements',
      brand: 'Uniwax',
      sizes: ['S', 'M', 'L'],
      colors: ['Bleu', 'Rouge'],
    );
    await shop.saveItem(productId: basket, category: 'Chaussures');
  });

  tearDown(() async {
    await db.close();
    await shopDb.close();
  });

  Future<CatalogItem> item(int productId) async =>
      (await shop.catalog()).firstWhere((c) => c.product.id == productId);

  test('catalogue : catégories, marque, tailles et couleurs', () async {
    final r = await item(robe);
    expect(r.category!.name, 'Vêtements');
    expect(r.brand!.name, 'Uniwax');
    expect(r.sizes, ['S', 'M', 'L']);
    expect(r.colors, ['Bleu', 'Rouge']);
    expect(r.stock, 5);
    // Même catégorie écrite autrement : pas de doublon.
    expect(await shop.categoryId('vetements'), r.category!.id);
  });

  test('une promotion ne vaut qu’entre ses dates', () async {
    await shop.addPromotion(
      title: 'Fête des mères',
      percent: 25,
      startsAt: DateTime(2026, 10, 20),
      endsAt: DateTime(2026, 10, 27),
    );
    expect((await item(robe)).price, 20000);
    t = DateTime(2026, 10, 21, 9);
    expect((await item(robe)).price, 15000);
    expect((await item(robe)).onPromo, isTrue);
    t = DateTime(2026, 10, 27, 0, 1);
    expect((await item(robe)).price, 20000);
  });

  test('soldes par catégorie et prix promo : le meilleur prix gagne', () async {
    final cat = (await item(robe)).item.categoryId;
    await shop.addPromotion(
      title: 'Soldes vêtements',
      percent: 10,
      categoryId: cat,
      isSale: true,
      startsAt: DateTime(2026, 10, 1),
      endsAt: DateTime(2026, 11, 1),
    );
    expect((await item(robe)).price, 18000);
    expect((await item(basket)).price, 30000);
    await shop.addPromotion(
      title: 'Prix choc',
      promoPrice: 16000,
      itemId: (await item(robe)).item.id,
      startsAt: DateTime(2026, 10, 1),
      endsAt: DateTime(2026, 11, 1),
    );
    expect((await item(robe)).price, 16000);
    expect(
      () => shop.addPromotion(
        title: 'Mauvaise',
        percent: 10,
        startsAt: DateTime(2026, 11, 1),
        endsAt: DateTime(2026, 10, 1),
      ),
      throwsArgumentError,
    );
  });

  test('une commande réserve le stock', () async {
    await shop.createOrder(
      customerName: 'Awa',
      payMethod: 'wave',
      items: [OrderItem(await item(basket), 2)],
    );
    expect(
      () async => shop.createOrder(
        customerName: 'Koffi',
        payMethod: 'livraison',
        items: [OrderItem(await item(basket), 1)],
      ),
      throwsStateError,
    );
  });

  test('livrée : devient une vente, sort le stock, crée le client', () async {
    final id = await shop.createOrder(
      customerName: 'Awa Traoré',
      phone: '07 07 00 00 01',
      payMethod: 'orange',
      deliveryFee: 1000,
      items: [OrderItem(await item(robe), 2, size: 'M', color: 'Bleu')],
    );
    // Orange Money pas encore reçu : impossible de livrer.
    expect(() => shop.setStatus(id, OrderStatus.livree), throwsStateError);
    await shop.markPaid(id);
    await shop.setStatus(id, OrderStatus.livree);

    expect(await repo.stockOf(robe), 3);
    final sale = (await repo.sales()).single;
    expect(sale.sale.total, 40000);
    expect(sale.status, SaleStatus.soldee);
    expect(sale.contact!.name, 'Awa Traoré');
    final d = await shop.order(id);
    expect(d.status, OrderStatus.livree);
    expect(d.order.saleId, sale.sale.id);
    expect(d.toPay, 41000);
    expect((await shop.stats()).revenueMonth, 40000);
    expect(() => shop.setStatus(id, OrderStatus.annulee), throwsStateError);
  });

  test(
    'paiement à la livraison : encaissé en espèces à la livraison',
    () async {
      final id = await shop.createOrder(
        customerName: 'Koffi',
        payMethod: 'livraison',
        items: [OrderItem(await item(basket), 1)],
      );
      await shop.setStatus(id, OrderStatus.confirmee);
      await shop.setStatus(id, OrderStatus.livree);
      final pay = await db.select(db.payments).getSingle();
      expect(pay.method, 'especes');
      expect(pay.amount, 30000);
    },
  );

  test('annulée : le stock réservé est libéré', () async {
    final id = await shop.createOrder(
      customerName: 'Awa',
      payMethod: 'wave',
      items: [OrderItem(await item(basket), 2)],
    );
    await shop.setStatus(id, OrderStatus.annulee);
    expect(await shop.reserved(), isEmpty);
    expect(await repo.stockOf(basket), 2);
  });

  test('messages WhatsApp : paiement et catalogue', () async {
    await shop.saveInfo({
      'shop_name': 'Chez Awa',
      'wave_number': '0707000001',
      'orange_number': '0707000002',
      'cod': 'non',
    });
    final info = await shop.info();
    expect(info.methods, ['orange', 'wave']);
    final id = await shop.createOrder(
      customerName: 'Fatou',
      payMethod: 'wave',
      items: [OrderItem(await item(robe), 1, size: 'L')],
    );
    final msg = shop.paymentMessage(await shop.order(id), info);
    expect(msg, contains('Total à payer : 20.000 FCFA'));
    expect(msg, contains('Wave au 0707000001'));

    await shop.addAnnouncement(title: 'Nouvel arrivage');
    await shop.setPublished((await item(basket)).item.id, false);
    final cat = await shop.catalogMessage();
    expect(cat, contains('Chez Awa'));
    expect(cat, contains('Nouvel arrivage'));
    expect(cat, contains('Robe wax'));
    expect(cat, isNot(contains('Baskets')));
  });

  test('réglages : numéros nettoyés, lien Wave vérifié', () async {
    await shop.saveInfo({
      'wave_number': '07 07-00 00 01',
      'delivery_fee': '1 500',
    });
    final info = await shop.info();
    expect(info.waveNumber, '0707000001');
    expect(info.deliveryFee, 1500);
    for (final bad in [
      'http://pay.wave.com/m/abc',
      'https://wave.com.arnaque.ci/m/abc',
      'javascript:alert(1)',
    ]) {
      expect(() => shop.saveInfo({'wave_link': bad}), throwsArgumentError);
    }
    await shop.saveInfo({'wave_link': 'https://pay.wave.com/m/abc'});
    expect((await shop.info()).waveLink, 'https://pay.wave.com/m/abc');
  });

  test('refuse une quantité nulle ou des frais négatifs', () async {
    expect(
      () async => shop.createOrder(
        customerName: 'Awa',
        payMethod: 'wave',
        items: [OrderItem(await item(robe), 0)],
      ),
      throwsArgumentError,
    );
    expect(
      () async => shop.createOrder(
        customerName: 'Awa',
        payMethod: 'wave',
        deliveryFee: -500,
        items: [OrderItem(await item(robe), 1)],
      ),
      throwsArgumentError,
    );
  });
}
