import 'package:drift/drift.dart';

import '../app_state.dart';
import 'database.dart';
import 'repository.dart';
import 'shop_database.dart';

/// Modes de paiement de la vente en ligne. Le paiement mobile se fait pour
/// l'instant par transfert vers le numéro du commerçant ; le paiement
/// automatique viendra avec les comptes marchands Orange et Wave.
const onlinePayMethods = {
  'orange': 'Orange Money',
  'wave': 'Wave',
  'livraison': 'Paiement à la livraison',
};

enum OrderStatus { nouvelle, confirmee, livraison, livree, annulee }

extension OrderStatusLabel on OrderStatus {
  String get label => switch (this) {
    OrderStatus.nouvelle => 'Nouvelle',
    OrderStatus.confirmee => 'Confirmée',
    OrderStatus.livraison => 'En livraison',
    OrderStatus.livree => 'Livrée',
    OrderStatus.annulee => 'Annulée',
  };
  bool get open => this != OrderStatus.livree && this != OrderStatus.annulee;
}

OrderStatus orderStatus(Order o) => OrderStatus.values.byName(o.status);

List<String> splitOptions(String s) => [
  for (final p in s.split(','))
    if (p.trim().isNotEmpty) p.trim(),
];

/// Un article du catalogue avec tout ce qu'il faut pour l'afficher.
class CatalogItem {
  CatalogItem({
    required this.item,
    required this.product,
    required this.stock,
    required this.category,
    required this.brand,
    required this.promotion,
  });
  final ShopItem item;
  final Product product;
  final int stock;
  final ShopCategory? category;
  final ShopBrand? brand;

  /// Meilleure promotion en cours, s'il y en a une.
  final Promotion? promotion;

  String get name => product.name;
  int get basePrice => item.onlinePrice ?? product.price;
  int get price =>
      promotion == null ? basePrice : promoPrice(promotion!, basePrice);
  bool get onPromo => price < basePrice;
  List<String> get sizes => splitOptions(item.sizes);
  List<String> get colors => splitOptions(item.colors);
}

int promoPrice(Promotion p, int base) {
  if (p.promoPrice != null) return p.promoPrice!.clamp(0, base);
  final pct = (p.percent ?? 0).clamp(0, 100);
  return (base * (100 - pct) / 100).round();
}

class OrderItem {
  OrderItem(this.item, this.qty, {this.size = '', this.color = ''});
  final CatalogItem item;
  final int qty;
  final String size;
  final String color;
  int get total => qty * item.price;
}

class OrderDetail {
  OrderDetail(this.order, this.lines);
  final Order order;
  final List<OrderLine> lines;
  OrderStatus get status => orderStatus(order);
  int get toPay => order.total + order.deliveryFee;
}

class ShopInfo {
  ShopInfo(this.values);
  final Map<String, String> values;
  String get shopName => values['shop_name'] ?? 'Ma boutique';
  String get whatsapp => values['whatsapp'] ?? '';
  String get orangeNumber => values['orange_number'] ?? '';
  String get waveNumber => values['wave_number'] ?? '';
  String get waveLink => values['wave_link'] ?? '';
  bool get cashOnDelivery => values['cod'] != 'non';
  int get deliveryFee => int.tryParse(values['delivery_fee'] ?? '') ?? 0;

  /// Modes que le commerçant a activés (un numéro rempli ou la livraison).
  List<String> get methods => [
    if (orangeNumber.isNotEmpty) 'orange',
    if (waveNumber.isNotEmpty || waveLink.isNotEmpty) 'wave',
    if (cashOnDelivery) 'livraison',
  ];
}

class ShopStats {
  ShopStats(this.toHandle, this.revenueMonth, this.deliveredMonth);
  final int toHandle;
  final int revenueMonth;
  final int deliveredMonth;
}

/// Règles de la vente en ligne. Le stock et les ventes restent dans
/// [Repository] : une commande livrée devient une vente de la boutique.
class ShopRepository {
  ShopRepository(this.db, this.main);
  final ShopDatabase db;
  final Repository main;

  DateTime now() => main.now();

  // ---------- Catégories et marques ----------

  Future<List<ShopCategory>> categories() => (db.select(
    db.categories,
  )..orderBy([(c) => OrderingTerm.asc(c.name)])).get();

  Future<List<ShopBrand>> brands() =>
      (db.select(db.brands)..orderBy([(b) => OrderingTerm.asc(b.name)])).get();

  /// Renvoie la catégorie de ce nom, en la créant si besoin.
  Future<int> categoryId(String name) async {
    final n = normalize(name);
    for (final c in await categories()) {
      if (normalize(c.name) == n) return c.id;
    }
    return db
        .into(db.categories)
        .insert(CategoriesCompanion.insert(name: name.trim()));
  }

  Future<int> brandId(String name) async {
    final n = normalize(name);
    for (final b in await brands()) {
      if (normalize(b.name) == n) return b.id;
    }
    return db.into(db.brands).insert(BrandsCompanion.insert(name: name.trim()));
  }

  // ---------- Catalogue ----------

  /// Met un article du stock en ligne, ou met à jour sa présentation.
  Future<int> saveItem({
    required int productId,
    String? category,
    String? brand,
    String description = '',
    List<String> sizes = const [],
    List<String> colors = const [],
    int? onlinePrice,
    bool published = true,
  }) async {
    final cat = category == null || category.trim().isEmpty
        ? null
        : await categoryId(category);
    final br = brand == null || brand.trim().isEmpty
        ? null
        : await brandId(brand);
    final row = ShopItemsCompanion.insert(
      productId: productId,
      categoryId: Value(cat),
      brandId: Value(br),
      description: Value(description.trim()),
      sizes: Value(sizes.map((s) => s.trim()).join(', ')),
      colors: Value(colors.map((s) => s.trim()).join(', ')),
      onlinePrice: Value(onlinePrice),
      published: Value(published),
    );
    return db
        .into(db.shopItems)
        .insert(
          row,
          onConflict: DoUpdate((_) => row, target: [db.shopItems.productId]),
        );
  }

  Future<void> setPublished(int itemId, bool published) =>
      (db.update(db.shopItems)..where((i) => i.id.equals(itemId))).write(
        ShopItemsCompanion(published: Value(published)),
      );

  Future<void> removeItem(int itemId) => db.transaction(() async {
    await (db.delete(
      db.promotions,
    )..where((p) => p.itemId.equals(itemId))).go();
    await (db.delete(db.shopItems)..where((i) => i.id.equals(itemId))).go();
  });

  /// Le catalogue, avec le prix du jour. `onlyPublished` donne ce que voit
  /// le client.
  Future<List<CatalogItem>> catalog({bool onlyPublished = false}) async {
    final stock = {for (final s in await main.stock()) s.product.id: s};
    final cats = {for (final c in await categories()) c.id: c};
    final brs = {for (final b in await brands()) b.id: b};
    final promos = await activePromotions();
    final items = await db.select(db.shopItems).get();
    final out = <CatalogItem>[];
    for (final i in items) {
      final s = stock[i.productId];
      if (s == null) continue; // article archivé dans le stock
      if (onlyPublished && !i.published) continue;
      final base = i.onlinePrice ?? s.product.price;
      Promotion? best;
      for (final p in promos) {
        final applies =
            p.itemId == i.id ||
            (p.itemId == null &&
                (p.categoryId == null || p.categoryId == i.categoryId));
        if (!applies) continue;
        if (best == null || promoPrice(p, base) < promoPrice(best, base)) {
          best = p;
        }
      }
      out.add(
        CatalogItem(
          item: i,
          product: s.product,
          stock: s.qty,
          category: cats[i.categoryId],
          brand: brs[i.brandId],
          promotion: best != null && promoPrice(best, base) < base
              ? best
              : null,
        ),
      );
    }
    return out..sort((a, b) => normalize(a.name).compareTo(normalize(b.name)));
  }

  // ---------- Promotions, soldes et annonces ----------

  Future<int> addPromotion({
    required String title,
    String details = '',
    int? percent,
    int? promoPrice,
    int? itemId,
    int? categoryId,
    bool isSale = false,
    required DateTime startsAt,
    required DateTime endsAt,
  }) {
    if ((percent == null) == (promoPrice == null)) {
      throw ArgumentError('Indiquez un pourcentage ou un prix promotionnel.');
    }
    if (percent != null && (percent <= 0 || percent >= 100)) {
      throw ArgumentError('Le pourcentage doit être entre 1 et 99.');
    }
    if (promoPrice != null && itemId == null) {
      throw ArgumentError('Un prix promotionnel vaut pour un seul article.');
    }
    if (!endsAt.isAfter(startsAt)) {
      throw ArgumentError('La fin doit être après le début.');
    }
    return db
        .into(db.promotions)
        .insert(
          PromotionsCompanion.insert(
            title: title.trim(),
            details: Value(details.trim()),
            percent: Value(percent),
            promoPrice: Value(promoPrice),
            itemId: Value(itemId),
            categoryId: Value(categoryId),
            isSale: Value(isSale),
            startsAt: startsAt,
            endsAt: endsAt,
          ),
        );
  }

  Future<void> deletePromotion(int id) =>
      (db.delete(db.promotions)..where((p) => p.id.equals(id))).go();

  Future<List<Promotion>> promotions() => (db.select(
    db.promotions,
  )..orderBy([(p) => OrderingTerm.desc(p.startsAt)])).get();

  Future<List<Promotion>> activePromotions() {
    final t = now();
    return (db.select(db.promotions)..where(
          (p) =>
              p.startsAt.isSmallerOrEqualValue(t) &
              p.endsAt.isBiggerThanValue(t),
        ))
        .get();
  }

  Future<int> addAnnouncement({
    required String title,
    String body = '',
    DateTime? startsAt,
    DateTime? endsAt,
  }) => db
      .into(db.announcements)
      .insert(
        AnnouncementsCompanion.insert(
          title: title.trim(),
          body: Value(body.trim()),
          startsAt: startsAt ?? now(),
          endsAt: Value(endsAt),
        ),
      );

  Future<void> deleteAnnouncement(int id) =>
      (db.delete(db.announcements)..where((a) => a.id.equals(id))).go();

  Future<List<Announcement>> announcements({bool onlyActive = false}) async {
    final all = await (db.select(
      db.announcements,
    )..orderBy([(a) => OrderingTerm.desc(a.startsAt)])).get();
    if (!onlyActive) return all;
    final t = now();
    return all
        .where(
          (a) =>
              !a.startsAt.isAfter(t) &&
              (a.endsAt == null || a.endsAt!.isAfter(t)),
        )
        .toList();
  }

  // ---------- Réglages ----------

  Future<ShopInfo> info() async => ShopInfo({
    for (final s in await db.select(db.shopSettings).get()) s.key: s.value,
  });

  Future<void> saveInfo(Map<String, String> values) => db.batch(
    (b) => b.insertAllOnConflictUpdate(db.shopSettings, [
      for (final e in values.entries)
        ShopSettingsCompanion.insert(key: e.key, value: e.value.trim()),
    ]),
  );

  // ---------- Commandes ----------

  /// Quantités déjà promises à des commandes pas encore livrées.
  Future<Map<int, int>> reserved({int? exceptOrder}) async {
    final rows =
        await (db.select(db.orderLines).join([
              innerJoin(
                db.orders,
                db.orders.id.equalsExp(db.orderLines.orderId),
              ),
            ])..where(
              db.orders.status.isIn(['nouvelle', 'confirmee', 'livraison']),
            ))
            .get();
    final out = <int, int>{};
    for (final r in rows) {
      if (r.readTable(db.orders).id == exceptOrder) continue;
      final l = r.readTable(db.orderLines);
      out[l.productId] = (out[l.productId] ?? 0) + l.qty;
    }
    return out;
  }

  /// Enregistre une commande reçue (WhatsApp, appel, vitrine). Refuse de
  /// promettre plus que le stock non réservé.
  Future<int> createOrder({
    required String customerName,
    String phone = '',
    String address = '',
    String note = '',
    required String payMethod,
    int deliveryFee = 0,
    required List<OrderItem> items,
  }) async {
    if (customerName.trim().isEmpty) {
      throw ArgumentError('Indiquez le nom du client.');
    }
    if (items.isEmpty) throw ArgumentError('La commande est vide.');
    if (!onlinePayMethods.containsKey(payMethod)) {
      throw ArgumentError('Mode de paiement inconnu : $payMethod');
    }
    return db.transaction(() async {
      final taken = await reserved();
      final wanted = <int, int>{};
      for (final i in items) {
        wanted[i.item.product.id] = (wanted[i.item.product.id] ?? 0) + i.qty;
      }
      for (final i in items) {
        final pid = i.item.product.id;
        final free = await main.stockOf(pid) - (taken[pid] ?? 0);
        if (wanted[pid]! > free) {
          throw StateError(
            'Stock insuffisant pour ${i.item.name} : ${free < 0 ? 0 : free} disponible(s).',
          );
        }
      }
      final id = await db
          .into(db.orders)
          .insert(
            OrdersCompanion.insert(
              customerName: customerName.trim(),
              phone: Value(phone.trim()),
              address: Value(address.trim()),
              note: Value(note.trim()),
              createdAt: now(),
              payMethod: payMethod,
              deliveryFee: Value(deliveryFee),
              total: items.fold(0, (s, i) => s + i.total),
            ),
          );
      for (final i in items) {
        await db
            .into(db.orderLines)
            .insert(
              OrderLinesCompanion.insert(
                orderId: id,
                productId: i.item.product.id,
                name: i.item.name,
                size: Value(i.size),
                color: Value(i.color),
                qty: i.qty,
                unitPrice: i.item.price,
              ),
            );
      }
      return id;
    });
  }

  Future<List<OrderDetail>> orders() async {
    final list = await (db.select(
      db.orders,
    )..orderBy([(o) => OrderingTerm.desc(o.createdAt)])).get();
    final lines = await db.select(db.orderLines).get();
    final byOrder = <int, List<OrderLine>>{};
    for (final l in lines) {
      byOrder.putIfAbsent(l.orderId, () => []).add(l);
    }
    return [for (final o in list) OrderDetail(o, byOrder[o.id] ?? [])];
  }

  Future<OrderDetail> order(int id) async =>
      (await orders()).firstWhere((o) => o.order.id == id);

  Future<void> markPaid(int orderId, {bool paid = true}) =>
      (db.update(db.orders)..where((o) => o.id.equals(orderId))).write(
        OrdersCompanion(paid: Value(paid)),
      );

  /// Avance la commande. À la livraison, elle devient une vente de la
  /// boutique : le stock sort et l'argent est compté dans le tableau de
  /// bord. Une commande payée à la livraison est encaissée à ce moment-là.
  Future<void> setStatus(int orderId, OrderStatus status) async {
    final d = await order(orderId);
    if (!d.status.open) {
      throw StateError(
        'Cette commande est déjà ${d.status.label.toLowerCase()}.',
      );
    }
    if (status == OrderStatus.livree) {
      if (!d.order.paid && d.order.payMethod != 'livraison') {
        throw StateError(
          'Le paiement ${onlinePayMethods[d.order.payMethod]} n’est pas encore reçu.',
        );
      }
      final products = {for (final p in await main.products()) p.id: p};
      final lines = [
        for (final l in d.lines)
          if (products[l.productId] != null)
            CartLine(products[l.productId]!, l.qty, unitPrice: l.unitPrice),
      ];
      final contactId = await _contactFor(d.order);
      final saleId = await main.recordSale(
        lines: lines,
        contactId: contactId,
        paidNow: lines.fold(0, (s, l) => s + l.total),
        method: d.order.payMethod == 'livraison'
            ? 'especes'
            : d.order.payMethod,
      );
      await (db.update(db.orders)..where((o) => o.id.equals(orderId))).write(
        OrdersCompanion(
          status: Value(status.name),
          paid: const Value(true),
          saleId: Value(saleId),
        ),
      );
      return;
    }
    await (db.update(db.orders)..where((o) => o.id.equals(orderId))).write(
      OrdersCompanion(status: Value(status.name)),
    );
  }

  /// Le client de la commande dans le carnet d'adresses, créé s'il est
  /// nouveau (même téléphone ou même nom).
  Future<int> _contactFor(Order o) async {
    final phone = o.phone.replaceAll(RegExp(r'[^0-9]'), '');
    for (final c in await main.contacts(kind: 'client')) {
      final cp = (c.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      if (phone.isNotEmpty && cp == phone) return c.id;
      if (normalize(c.name) == normalize(o.customerName) &&
          (phone.isEmpty || cp.isEmpty)) {
        return c.id;
      }
    }
    return main.addContact(
      o.customerName,
      phone: o.phone.isEmpty ? null : o.phone,
    );
  }

  Future<ShopStats> stats() async {
    final t = now();
    final month = DateTime(t.year, t.month);
    var open = 0, revenue = 0, delivered = 0;
    for (final d in await orders()) {
      if (d.status.open) open++;
      if (d.status == OrderStatus.livree &&
          !d.order.createdAt.isBefore(month)) {
        delivered++;
        revenue += d.order.total;
      }
    }
    return ShopStats(open, revenue, delivered);
  }

  // ---------- Messages à partager ----------

  /// Demande de paiement envoyée au client par WhatsApp.
  String paymentMessage(OrderDetail d, ShopInfo info) {
    final b = StringBuffer(
      'Bonjour ${d.order.customerName}, merci pour votre commande n°${d.order.id} chez ${info.shopName} :\n',
    );
    for (final l in d.lines) {
      final opts = [l.size, l.color].where((s) => s.isNotEmpty).join(', ');
      b.writeln(
        '• ${l.qty} × ${l.name}${opts.isEmpty ? '' : ' ($opts)'} : ${fcfa(l.qty * l.unitPrice)}',
      );
    }
    if (d.order.deliveryFee > 0) {
      b.writeln('• Livraison : ${fcfa(d.order.deliveryFee)}');
    }
    b.writeln('Total à payer : ${fcfa(d.toPay)}');
    switch (d.order.payMethod) {
      case 'orange':
        b.write('Paiement par Orange Money au ${info.orangeNumber}.');
      case 'wave':
        b.write(
          info.waveLink.isNotEmpty
              ? 'Paiement par Wave : ${info.waveLink}'
              : 'Paiement par Wave au ${info.waveNumber}.',
        );
      default:
        b.write('Vous paierez à la livraison.');
    }
    return b.toString();
  }

  /// Catalogue en texte, à partager sur WhatsApp ou dans un statut.
  Future<String> catalogMessage() async {
    final info = await this.info();
    final b = StringBuffer('🛍️ ${info.shopName}\n');
    for (final a in await announcements(onlyActive: true)) {
      b.writeln('📢 ${a.title}${a.body.isEmpty ? '' : ' : ${a.body}'}');
    }
    final byCat = <String, List<CatalogItem>>{};
    for (final c in await catalog(onlyPublished: true)) {
      if (c.stock <= 0) continue;
      byCat.putIfAbsent(c.category?.name ?? 'Autres', () => []).add(c);
    }
    for (final e in byCat.entries) {
      b.writeln('\n*${e.key}*');
      for (final c in e.value) {
        final extra = [
          if (c.brand != null) c.brand!.name,
          if (c.sizes.isNotEmpty) 'tailles ${c.sizes.join('/')}',
          if (c.colors.isNotEmpty) c.colors.join('/'),
        ].join(' · ');
        b.writeln(
          '• ${c.name}${extra.isEmpty ? '' : ' ($extra)'} : '
          '${c.onPromo ? '${fcfa(c.price)} au lieu de ${fcfa(c.basePrice)}' : fcfa(c.price)}',
        );
      }
    }
    final pay = [for (final m in info.methods) onlinePayMethods[m]!];
    if (pay.isNotEmpty) b.writeln('\nPaiement : ${pay.join(', ')}');
    if (info.whatsapp.isNotEmpty) b.writeln('Commandes : ${info.whatsapp}');
    return b.toString().trim();
  }
}
