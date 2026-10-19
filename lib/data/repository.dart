import 'package:drift/drift.dart';

import 'database.dart';

enum SaleStatus { soldee, acompte, reliquat, nonPaye, annulee }

extension SaleStatusLabel on SaleStatus {
  String get label => switch (this) {
    SaleStatus.soldee => 'Soldée',
    SaleStatus.acompte => 'Acompte',
    SaleStatus.reliquat => 'Reliquat',
    SaleStatus.nonPaye => 'Non payé',
    SaleStatus.annulee => 'Annulée',
  };
}

const paymentMethods = {
  'especes': 'Espèces',
  'orange': 'Orange Money',
  'mtn': 'MTN MoMo',
  'moov': 'Moov Money',
  'wave': 'Wave',
};

class CartLine {
  CartLine(this.product, this.qty, {int? unitPrice})
    : unitPrice = unitPrice ?? product.price;
  final Product product;
  final int qty;
  final int unitPrice;
  int get total => qty * unitPrice;
}

class ProductStock {
  ProductStock(this.product, this.qty);
  final Product product;
  final int qty;
  bool get low => qty <= product.alertMin;
}

class SaleSummary {
  SaleSummary({
    required this.sale,
    required this.contact,
    required this.paid,
    required this.paidLater,
  });
  final Sale sale;
  final Contact? contact;
  final int paid;
  final int paidLater;

  int get due => sale.cancelled ? 0 : (sale.total - paid).clamp(0, sale.total);

  SaleStatus get status {
    if (sale.cancelled) return SaleStatus.annulee;
    if (paid >= sale.total) return SaleStatus.soldee;
    if (paid == 0) return SaleStatus.nonPaye;
    return paidLater > 0 ? SaleStatus.reliquat : SaleStatus.acompte;
  }
}

class Debtor {
  Debtor(this.contact, this.due, this.oldest);
  final Contact contact;
  final int due;
  final DateTime oldest;
}

class ProductSales {
  ProductSales(this.product, this.qty, this.revenue, this.margin);
  final Product product;
  final int qty;
  final int revenue;
  final int margin;
}

/// Une ligne de vente avec le nom de l'article, pour le détail des ventes.
class SaleLineDetail {
  SaleLineDetail(this.product, this.qty, this.unitPrice);
  final Product product;
  final int qty;
  final int unitPrice;
  int get total => qty * unitPrice;
  int get margin => qty * (unitPrice - product.cost);
}

class SaleDetail {
  SaleDetail(this.summary, this.lines);
  final SaleSummary summary;
  final List<SaleLineDetail> lines;
  int get margin =>
      summary.sale.cancelled ? 0 : lines.fold(0, (s, l) => s + l.margin);
}

class CancelledSale {
  CancelledSale(this.detail, this.cancelledAt);
  final SaleDetail detail;
  final DateTime cancelledAt;
}

class PeriodStats {
  PeriodStats(this.sales, this.profit, this.cashIn, this.count);
  final int sales;
  final int profit;
  final int cashIn;
  final int count;
}

/// Toutes les règles métier : ventes, stock, crédits. Les écrans et
/// l'assistant vocal passent tous par ici, jamais directement par la base.
class Repository {
  Repository(this.db);
  final AppDatabase db;

  DateTime Function() now = DateTime.now;

  // ---------- Articles et stock ----------

  Future<int> addProduct({
    required String name,
    required int price,
    String unit = 'pièce',
    int? wholesalePrice,
    int cost = 0,
    int alertMin = 0,
    int initialQty = 0,
  }) {
    return db.transaction(() async {
      final id = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: name.trim(),
              price: price,
              unit: Value(unit),
              wholesalePrice: Value(wholesalePrice),
              cost: Value(cost),
              alertMin: Value(alertMin),
            ),
          );
      if (initialQty != 0) {
        await _move(id, initialQty, 'inventaire');
      }
      return id;
    });
  }

  Future<List<Product>> products() =>
      (db.select(db.products)
            ..where((p) => p.archived.equals(false))
            ..orderBy([(p) => OrderingTerm.asc(p.name)]))
          .get();

  Future<int> stockOf(int productId) async {
    final sum = db.stockMoves.delta.sum();
    final row =
        await (db.selectOnly(db.stockMoves)
              ..addColumns([sum])
              ..where(db.stockMoves.productId.equals(productId)))
            .getSingle();
    return row.read(sum) ?? 0;
  }

  Future<List<ProductStock>> stock() async {
    final sum = db.stockMoves.delta.sum();
    final rows =
        await (db.selectOnly(db.stockMoves)
              ..addColumns([db.stockMoves.productId, sum])
              ..groupBy([db.stockMoves.productId]))
            .get();
    final qty = {
      for (final r in rows) r.read(db.stockMoves.productId)!: r.read(sum) ?? 0,
    };
    return [for (final p in await products()) ProductStock(p, qty[p.id] ?? 0)];
  }

  Future<List<ProductStock>> lowStock() async =>
      (await stock()).where((s) => s.low).toList();

  /// Entrée en stock (achat fournisseur) ou sortie (perte, casse).
  Future<void> adjustStock(int productId, int delta, String reason) =>
      _move(productId, delta, reason);

  Future<void> _move(int productId, int delta, String reason, {int? saleId}) =>
      db
          .into(db.stockMoves)
          .insert(
            StockMovesCompanion.insert(
              productId: productId,
              delta: delta,
              reason: reason,
              saleId: Value(saleId),
              createdAt: now(),
            ),
          );

  // ---------- Contacts ----------

  Future<int> addContact(
    String name, {
    String? phone,
    String kind = 'client',
  }) => db
      .into(db.contacts)
      .insert(
        ContactsCompanion.insert(
          name: name.trim(),
          phone: Value(phone),
          kind: Value(kind),
        ),
      );

  Future<List<Contact>> contacts({String? kind}) {
    final q = db.select(db.contacts)
      ..orderBy([(c) => OrderingTerm.asc(c.name)]);
    if (kind != null) q.where((c) => c.kind.equals(kind));
    return q.get();
  }

  // ---------- Ventes ----------

  /// Enregistre une vente complète en une seule transaction : lignes,
  /// sortie de stock et acompte éventuel. Refuse une vente qui rendrait le
  /// stock négatif.
  Future<int> recordSale({
    required List<CartLine> lines,
    int? contactId,
    int paidNow = 0,
    String method = 'especes',
  }) async {
    if (lines.isEmpty) throw ArgumentError('La vente est vide.');
    final total = lines.fold<int>(0, (s, l) => s + l.total);
    if (paidNow < 0 || paidNow > total) {
      throw ArgumentError('Le montant payé doit être entre 0 et $total.');
    }
    if (paidNow < total && contactId == null) {
      throw ArgumentError('Une vente à crédit doit avoir un client.');
    }
    return db.transaction(() async {
      for (final l in lines) {
        final available = await stockOf(l.product.id);
        if (l.qty > available) {
          throw StateError(
            'Stock insuffisant pour ${l.product.name} : $available restant(s).',
          );
        }
      }
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              contactId: Value(contactId),
              createdAt: now(),
              total: total,
            ),
          );
      for (final l in lines) {
        await db
            .into(db.saleLines)
            .insert(
              SaleLinesCompanion.insert(
                saleId: saleId,
                productId: l.product.id,
                qty: l.qty,
                unitPrice: l.unitPrice,
              ),
            );
        await _move(l.product.id, -l.qty, 'vente', saleId: saleId);
      }
      if (paidNow > 0) {
        await db
            .into(db.payments)
            .insert(
              PaymentsCompanion.insert(
                saleId: saleId,
                amount: paidNow,
                method: method,
                atSale: true,
                createdAt: now(),
              ),
            );
      }
      return saleId;
    });
  }

  /// Annule une vente : le stock revient, l'argent n'est plus compté.
  Future<void> cancelSale(int saleId) => db.transaction(() async {
    final sale = await (db.select(
      db.sales,
    )..where((s) => s.id.equals(saleId))).getSingle();
    if (sale.cancelled) return;
    await (db.update(db.sales)..where((s) => s.id.equals(saleId))).write(
      const SalesCompanion(cancelled: Value(true)),
    );
    final lines = await (db.select(
      db.saleLines,
    )..where((l) => l.saleId.equals(saleId))).get();
    for (final l in lines) {
      await _move(l.productId, l.qty, 'annulation', saleId: saleId);
    }
  });

  Future<List<SaleSummary>> sales({DateTime? from, DateTime? to}) async {
    final q = db.select(db.sales).join([
      leftOuterJoin(db.contacts, db.contacts.id.equalsExp(db.sales.contactId)),
    ])..orderBy([OrderingTerm.desc(db.sales.createdAt)]);
    if (from != null) q.where(db.sales.createdAt.isBiggerOrEqualValue(from));
    if (to != null) q.where(db.sales.createdAt.isSmallerThanValue(to));
    final rows = await q.get();
    final pays = await db.select(db.payments).get();
    final paid = <int, int>{};
    final later = <int, int>{};
    for (final p in pays) {
      paid[p.saleId] = (paid[p.saleId] ?? 0) + p.amount;
      if (!p.atSale) later[p.saleId] = (later[p.saleId] ?? 0) + p.amount;
    }
    return [
      for (final r in rows)
        SaleSummary(
          sale: r.readTable(db.sales),
          contact: r.readTableOrNull(db.contacts),
          paid: paid[r.readTable(db.sales).id] ?? 0,
          paidLater: later[r.readTable(db.sales).id] ?? 0,
        ),
    ];
  }

  /// Ventes d'une journée avec leurs articles, de la plus récente à la plus
  /// ancienne.
  Future<List<SaleDetail>> dayDetails(DateTime day) async {
    final from = DateTime(day.year, day.month, day.day);
    final to = DateTime(day.year, day.month, day.day + 1);
    return _withLines(await sales(from: from, to: to));
  }

  /// Ventes annulées depuis `from`, de la plus récemment annulée à la plus
  /// ancienne. L'heure d'annulation est celle du retour en stock.
  Future<List<CancelledSale>> cancelledSales({DateTime? from}) async {
    final when = db.stockMoves.createdAt.max();
    final q = db.selectOnly(db.stockMoves)
      ..addColumns([db.stockMoves.saleId, when])
      ..where(db.stockMoves.reason.equals('annulation'))
      ..groupBy([db.stockMoves.saleId]);
    if (from != null) {
      q.where(db.stockMoves.createdAt.isBiggerOrEqualValue(from));
    }
    final at = {
      for (final r in await q.get())
        r.read(db.stockMoves.saleId)!: r.read(when)!,
    };
    if (at.isEmpty) return [];
    final list = (await sales()).where((s) => at.containsKey(s.sale.id));
    return [
      for (final d in await _withLines(list.toList()))
        CancelledSale(d, at[d.summary.sale.id]!),
    ]..sort((a, b) => b.cancelledAt.compareTo(a.cancelledAt));
  }

  Future<List<SaleDetail>> _withLines(List<SaleSummary> list) async {
    final ids = [for (final s in list) s.sale.id];
    final rows = await (db.select(db.saleLines).join([
      innerJoin(db.products, db.products.id.equalsExp(db.saleLines.productId)),
    ])..where(db.saleLines.saleId.isIn(ids))).get();
    final lines = <int, List<SaleLineDetail>>{};
    for (final r in rows) {
      final l = r.readTable(db.saleLines);
      (lines[l.saleId] ??= []).add(
        SaleLineDetail(r.readTable(db.products), l.qty, l.unitPrice),
      );
    }
    return [for (final s in list) SaleDetail(s, lines[s.sale.id] ?? [])];
  }

  // ---------- Crédits ----------

  Future<List<Debtor>> debtors() async {
    final byContact = <int, Debtor>{};
    for (final s in await sales()) {
      if (s.due == 0 || s.contact == null) continue;
      final prev = byContact[s.contact!.id];
      byContact[s.contact!.id] = Debtor(
        s.contact!,
        (prev?.due ?? 0) + s.due,
        prev == null || s.sale.createdAt.isBefore(prev.oldest)
            ? s.sale.createdAt
            : prev.oldest,
      );
    }
    return byContact.values.toList()..sort((a, b) => b.due.compareTo(a.due));
  }

  /// Encaisse un remboursement de client, en soldant ses ventes les plus
  /// anciennes d'abord. Renvoie le montant réellement imputé.
  Future<int> receivePayment(
    int contactId,
    int amount, {
    String method = 'especes',
  }) {
    return db.transaction(() async {
      var left = amount;
      final open =
          (await sales())
              .where((s) => s.contact?.id == contactId && s.due > 0)
              .toList()
            ..sort((a, b) => a.sale.createdAt.compareTo(b.sale.createdAt));
      for (final s in open) {
        if (left == 0) break;
        final part = left < s.due ? left : s.due;
        await db
            .into(db.payments)
            .insert(
              PaymentsCompanion.insert(
                saleId: s.sale.id,
                amount: part,
                method: method,
                atSale: false,
                createdAt: now(),
              ),
            );
        left -= part;
      }
      return amount - left;
    });
  }

  // ---------- Tableau de bord ----------

  /// Chiffres de `from` jusqu'à `to` exclu (sans `to` : jusqu'à maintenant).
  /// Le bénéfice est calculé sur le prix réellement vendu moins le coût
  /// d'achat de l'article.
  Future<PeriodStats> statsSince(DateTime from, {DateTime? to}) async {
    final list = (await sales(
      from: from,
      to: to,
    )).where((s) => !s.sale.cancelled);
    var total = 0, cost = 0;
    for (final s in list) {
      total += s.sale.total;
    }
    final lines =
        await (db.select(db.saleLines).join([
              innerJoin(db.sales, db.sales.id.equalsExp(db.saleLines.saleId)),
              innerJoin(
                db.products,
                db.products.id.equalsExp(db.saleLines.productId),
              ),
            ])..where(
              db.sales.createdAt.isBiggerOrEqualValue(from) &
                  (to == null
                      ? const Constant(true)
                      : db.sales.createdAt.isSmallerThanValue(to)) &
                  db.sales.cancelled.equals(false),
            ))
            .get();
    for (final r in lines) {
      cost += r.readTable(db.saleLines).qty * r.readTable(db.products).cost;
    }
    final pays =
        await (db.select(db.payments)..where(
              (p) =>
                  p.createdAt.isBiggerOrEqualValue(from) &
                  (to == null
                      ? const Constant(true)
                      : p.createdAt.isSmallerThanValue(to)),
            ))
            .get();
    final cashIn = pays.fold<int>(0, (s, p) => s + p.amount);
    return PeriodStats(total, total - cost, cashIn, list.length);
  }

  /// Ventes par jour sur les `days` derniers jours (le dernier = aujourd'hui).
  Future<List<int>> dailySales(int days) async {
    final today = DateTime(now().year, now().month, now().day);
    final from = today.subtract(Duration(days: days - 1));
    final out = List.filled(days, 0);
    for (final s in await sales(from: from)) {
      if (s.sale.cancelled) continue;
      final d = s.sale.createdAt;
      final i = DateTime(d.year, d.month, d.day).difference(from).inDays;
      if (i >= 0 && i < days) out[i] += s.sale.total;
    }
    return out;
  }

  /// Quantité vendue, chiffre d'affaires et marge par article, du plus
  /// vendu au moins vendu.
  Future<List<ProductSales>> productStats() async {
    final rows = await (db.select(db.saleLines).join([
      innerJoin(db.sales, db.sales.id.equalsExp(db.saleLines.saleId)),
    ])..where(db.sales.cancelled.equals(false))).get();
    final qty = <int, int>{}, revenue = <int, int>{};
    for (final r in rows) {
      final l = r.readTable(db.saleLines);
      qty[l.productId] = (qty[l.productId] ?? 0) + l.qty;
      revenue[l.productId] = (revenue[l.productId] ?? 0) + l.qty * l.unitPrice;
    }
    final out = [
      for (final p in await products())
        ProductSales(
          p,
          qty[p.id] ?? 0,
          revenue[p.id] ?? 0,
          (revenue[p.id] ?? 0) - (qty[p.id] ?? 0) * p.cost,
        ),
    ];
    return out..sort((a, b) => b.revenue.compareTo(a.revenue));
  }

  // ---------- Recherche ----------

  Future<List<Product>> findProducts(String query) async {
    final q = _norm(query);
    return (await products()).where((p) => _norm(p.name).contains(q)).toList();
  }

  Future<List<Contact>> findContacts(String query) async {
    final q = _norm(query);
    return (await contacts()).where((c) => _norm(c.name).contains(q)).toList();
  }
}

/// Minuscules et sans accents, pour comparer « Crédit » et « credit ».
String _norm(String s) {
  const from = 'àâäáãéèêëíìîïóòôöõúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i >= 0 ? to[i] : ch);
  }
  return b.toString().trim();
}

String normalize(String s) => _norm(s);
