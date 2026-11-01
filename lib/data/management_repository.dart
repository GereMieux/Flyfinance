import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../app_state.dart';
import 'accounts_repository.dart';
import 'database.dart';
import 'repository.dart';

/// Catégories proposées pour une dépense.
const expenseCategories = [
  'Loyer',
  'Électricité / eau',
  'Transport',
  'Salaires',
  'Téléphone / internet',
  'Taxes',
  'Pertes',
  'Autre',
];

/// Billets et pièces en FCFA, pour compter la caisse.
const cashNotes = [10000, 5000, 2000, 1000, 500, 250, 200, 100, 50, 25, 10, 5];

/// Une ligne du journal de caisse : entrée (+) ou sortie (−) d'argent.
class CashEntry {
  CashEntry(this.at, this.label, this.category, this.amount);
  final DateTime at;
  final String label;
  final String category;
  final int amount;
}

class MonthResult {
  MonthResult({
    required this.revenue,
    required this.cost,
    required this.expenses,
  });
  final int revenue;
  final int cost;
  final int expenses;
  int get margin => revenue - cost;
  int get net => revenue - cost - expenses;
}

/// Où en est la boutique aujourd'hui.
class Situation {
  Situation({
    required this.cash,
    required this.clientsOwe,
    required this.iOwe,
    required this.stockValue,
  });
  final int cash;
  final int clientsOwe;
  final int iOwe;
  final int stockValue;
  int get netValue => cash + clientsOwe - iOwe + stockValue;
}

/// Un nom et un montant, pour les classements des rapports.
class Ranked {
  Ranked(this.name, this.value, {this.detail = ''});
  final String name;
  final int value;
  final String detail;
}

class MonthPoint {
  MonthPoint(this.month, this.revenue, this.net);
  final DateTime month;
  final int revenue;
  final int net;
}

class Report {
  Report({
    required this.revenue,
    required this.margin,
    required this.expenses,
    required this.count,
    required this.topProducts,
    required this.topMargins,
    required this.topClients,
    required this.sleeping,
    required this.methods,
    required this.sellers,
    required this.months,
  });
  final int revenue;
  final int margin;
  final int expenses;
  final int count;
  final List<Ranked> topProducts;
  final List<Ranked> topMargins;
  final List<Ranked> topClients;
  final List<Ranked> sleeping;
  final List<Ranked> methods;
  final List<Ranked> sellers;
  final List<MonthPoint> months;
  int get net => margin - expenses;
  int get basket => count == 0 ? 0 : revenue ~/ count;
}

/// Ventes hors stock du mois, pour l'encadré de l'accueil.
class AdHocSummary {
  AdHocSummary(this.count, this.revenue, this.profit, this.names, this.often);
  final int count;
  final int revenue;
  final int profit;
  final List<String> names;

  /// Articles vendus au moins 3 fois hors stock : à mettre en stock ?
  final List<Product> often;
}

/// Une ligne du plan de versements aux fournisseurs.
class PlanRow {
  PlanRow({
    required this.supplier,
    required this.purchase,
    required this.amount,
    required this.date,
    required this.kind,
    required this.info,
  });
  final Contact supplier;
  final Purchase purchase;
  final int amount;
  final DateTime date;

  /// 'limite' : à payer à la date ; 'ventes' : dû maintenant sur ce qui
  /// s'est vendu ; 'attente' : à verser au fil des ventes.
  final String kind;
  final String info;
}

/// Écart trouvé pendant un inventaire.
class InventoryGap {
  InventoryGap(this.product, this.before, this.after);
  final Product product;
  final int before;
  final int after;
  int get gap => after - before;
  int get value => gap * product.cost;
}

String _hash(String salt, String pin) =>
    sha256.convert(utf8.encode('$salt:$pin')).toString();

/// Dépenses, caisse, rapports, vendeurs, retours, hors stock, plan de
/// versements, inventaire et sauvegarde.
extension Gestion on Repository {
  DateTime get _today {
    final t = now();
    return DateTime(t.year, t.month, t.day);
  }

  // ---------- Réglages ----------

  Future<String?> setting(String key) async => (await (db.select(
    db.settings,
  )..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setSetting(String key, String? value) async {
    if (value == null || value.trim().isEmpty) {
      await (db.delete(db.settings)..where((s) => s.key.equals(key))).go();
      return;
    }
    await db
        .into(db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(key: key, value: value.trim()),
        );
  }

  // ---------- Dépenses ----------

  Future<int> addExpense({
    required String label,
    required int amount,
    String category = 'Autre',
    DateTime? at,
  }) {
    if (label.trim().isEmpty) throw ArgumentError('Indiquez un libellé.');
    if (amount <= 0) throw ArgumentError('Indiquez un montant.');
    return db
        .into(db.expenses)
        .insert(
          ExpensesCompanion.insert(
            label: label.trim(),
            amount: amount,
            category: Value(category),
            createdAt: at ?? now(),
          ),
        );
  }

  Future<void> updateExpense(
    int id, {
    required String label,
    required int amount,
    required String category,
    required DateTime at,
  }) => (db.update(db.expenses)..where((e) => e.id.equals(id))).write(
    ExpensesCompanion(
      label: Value(label.trim()),
      amount: Value(amount),
      category: Value(category),
      createdAt: Value(at),
    ),
  );

  Future<void> deleteExpense(int id) =>
      (db.delete(db.expenses)..where((e) => e.id.equals(id))).go();

  Future<List<Expense>> expenses({DateTime? from, DateTime? to}) {
    final q = db.select(db.expenses)
      ..orderBy([(e) => OrderingTerm.desc(e.createdAt)]);
    if (from != null) q.where((e) => e.createdAt.isBiggerOrEqualValue(from));
    if (to != null) q.where((e) => e.createdAt.isSmallerThanValue(to));
    return q.get();
  }

  Future<int> expensesTotal(DateTime from, {DateTime? to}) async =>
      (await expenses(from: from, to: to)).fold<int>(0, (s, e) => s + e.amount);

  // ---------- Caisse ----------

  /// Argent en caisse au moment où l'on a commencé à utiliser l'application.
  Future<int> openingCash() async =>
      int.tryParse(await setting('cash.opening') ?? '') ?? 0;

  Future<void> setOpeningCash(int amount) =>
      setSetting('cash.opening', '$amount');

  /// Toutes les entrées et sorties d'argent, de la plus ancienne à la plus
  /// récente : ventes, remboursements, versements, dépenses, écarts.
  Future<List<CashEntry>> cashJournal() async {
    final out = <CashEntry>[];
    final sales = {for (final s in await this.sales()) s.sale.id: s};
    for (final p in await db.select(db.payments).get()) {
      final s = sales[p.saleId];
      if (s == null || s.sale.cancelled || p.method == 'provision') continue;
      final who = s.contact == null ? '' : ' — ${s.contact!.name}';
      if (p.amount < 0) {
        out.add(
          CashEntry(
            p.createdAt,
            'Retour d’article, vente n°${s.sale.id}$who',
            'Retour',
            p.amount,
          ),
        );
      } else {
        out.add(
          CashEntry(
            p.createdAt,
            p.atSale ? 'Vente n°${s.sale.id}$who' : 'Remboursement client$who',
            p.atSale ? 'Ventes' : 'Encaissement crédit',
            p.amount,
          ),
        );
      }
    }
    final names = {for (final c in await contacts()) c.id: c.name};
    for (final e in await (db.select(
      db.accountEntries,
    )..where((e) => e.cancelled.equals(false))).get()) {
      final n = names[e.contactId] ?? '';
      switch (e.kind) {
        case 'versement':
          out.add(
            CashEntry(e.createdAt, 'Versement — $n', 'Fournisseur', -e.amount),
          );
        case 'provision':
          out.add(
            CashEntry(e.createdAt, 'Avance de $n', 'Avance client', e.amount),
          );
        case 'rendue':
          out.add(
            CashEntry(
              e.createdAt,
              'Avance rendue à $n',
              'Avance client',
              -e.amount,
            ),
          );
      }
    }
    for (final p in await db.select(db.servicePayments).get()) {
      out.add(CashEntry(p.createdAt, 'Prestation', 'Prestations', p.amount));
    }
    for (final e in await expenses()) {
      out.add(CashEntry(e.createdAt, e.label, e.category, -e.amount));
    }
    for (final c in await (db.select(
      db.cashClosings,
    )..where((c) => c.adjusted.equals(true))).get()) {
      final gap = c.counted - c.expected;
      if (gap == 0) continue;
      out.add(
        CashEntry(
          c.createdAt,
          'Clôture de caisse : ${gap < 0 ? 'manque' : 'surplus'}'
              '${c.note == null ? '' : ' — ${c.note}'}',
          'Écart de caisse',
          gap,
        ),
      );
    }
    return out..sort((a, b) => a.at.compareTo(b.at));
  }

  Future<int> cashBalance() async =>
      await openingCash() +
      (await cashJournal()).fold<int>(0, (s, e) => s + e.amount);

  /// Clôture la caisse : compare l'argent compté à l'argent attendu.
  /// Renvoie l'écart (négatif : il manque de l'argent).
  Future<int> closeCash({
    required int counted,
    String? note,
    bool adjust = true,
    String? seller,
  }) async {
    final expected = await cashBalance();
    await db
        .into(db.cashClosings)
        .insert(
          CashClosingsCompanion.insert(
            createdAt: now(),
            expected: expected,
            counted: counted,
            adjusted: Value(adjust),
            note: Value(note == null || note.trim().isEmpty ? null : note),
            seller: Value(seller),
          ),
        );
    return counted - expected;
  }

  Future<List<CashClosing>> closings() =>
      (db.select(db.cashClosings)
            ..orderBy([(c) => OrderingTerm.desc(c.createdAt)])
            ..limit(30))
          .get();

  Future<bool> closedToday() async =>
      (await closings()).any((c) => !c.createdAt.isBefore(_today));

  /// Encaissé aujourd'hui, par moyen de paiement.
  Future<Map<String, int>> todayByMethod() async {
    final out = <String, int>{};
    for (final p in await (db.select(
      db.payments,
    )..where((p) => p.createdAt.isBiggerOrEqualValue(_today))).get()) {
      if (p.method == 'provision' || p.amount <= 0) continue;
      final k = paymentMethods[p.method] ?? p.method;
      out[k] = (out[k] ?? 0) + p.amount;
    }
    return out;
  }

  // ---------- Comptabilité ----------

  Future<MonthResult> result(DateTime from, DateTime to) async {
    final details = await salesWithLines(
      (await sales(
        from: from,
        to: to,
      )).where((s) => !s.sale.cancelled).toList(),
    );
    var revenue = 0, cost = 0;
    for (final d in details) {
      revenue += d.summary.sale.total;
      for (final l in d.lines) {
        cost += l.qty * l.unitCost;
      }
    }
    return MonthResult(
      revenue: revenue,
      cost: cost,
      expenses: await expensesTotal(from, to: to),
    );
  }

  Future<Situation> situation() async {
    var owed = 0;
    for (final s in await sales()) {
      owed += s.due;
    }
    var stockValue = 0;
    for (final s in await stock()) {
      if (s.qty > 0) stockValue += s.qty * s.product.cost;
    }
    return Situation(
      cash: await cashBalance(),
      clientsOwe: owed,
      iOwe: await supplierDebt(),
      stockValue: stockValue,
    );
  }

  // ---------- Rapports ----------

  Future<Report> report(DateTime from, {DateTime? to}) async {
    final list = (await sales(
      from: from,
      to: to,
    )).where((s) => !s.sale.cancelled).toList();
    final details = await salesWithLines(list);
    final sellerNames = {
      for (final s in await sellers(all: true)) s.id: s.name,
    };
    final qty = <int, int>{}, rev = <int, int>{}, mar = <int, int>{};
    final products = <int, Product>{};
    final clients = <String, (int, int)>{};
    final bySeller = <String, (int, int)>{};
    var revenue = 0, margin = 0;
    for (final d in details) {
      final s = d.summary;
      revenue += s.sale.total;
      if (s.contact != null) {
        final c = clients[s.contact!.name] ?? (0, 0);
        clients[s.contact!.name] = (c.$1 + s.sale.total, c.$2 + 1);
      }
      final seller = s.sale.sellerId == null
          ? 'Propriétaire'
          : sellerNames[s.sale.sellerId] ?? 'Vendeur retiré';
      final v = bySeller[seller] ?? (0, 0);
      bySeller[seller] = (v.$1 + s.sale.total, v.$2 + 1);
      for (final l in d.lines) {
        final id = l.product.id;
        products[id] = l.product;
        qty[id] = (qty[id] ?? 0) + l.qty;
        rev[id] = (rev[id] ?? 0) + l.total;
        mar[id] = (mar[id] ?? 0) + l.margin;
        margin += l.margin;
      }
    }
    String unitOf(Product p) => p.adHoc ? 'hors stock' : p.unit;
    final top = [
      for (final id in rev.keys)
        Ranked(
          products[id]!.name,
          rev[id]!,
          detail:
              '${qty[id]} ${unitOf(products[id]!)} · marge '
              '${fcfa(mar[id]!)}',
        ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    final topMargins = [
      for (final id in mar.keys) Ranked(products[id]!.name, mar[id]!),
    ]..sort((a, b) => b.value.compareTo(a.value));
    final sleeping = [
      for (final s in await stock())
        if (s.qty > 0 && !rev.containsKey(s.product.id))
          Ranked(
            s.product.name,
            s.qty * s.product.cost,
            detail: '${s.qty} ${s.product.unit} en stock',
          ),
    ]..sort((a, b) => b.value.compareTo(a.value));
    final methods = <String, int>{};
    for (final p
        in await (db.select(db.payments)..where(
              (p) =>
                  p.createdAt.isBiggerOrEqualValue(from) &
                  (to == null
                      ? const Constant(true)
                      : p.createdAt.isSmallerThanValue(to)),
            ))
            .get()) {
      if (p.amount <= 0) continue;
      final k = p.method == 'provision'
          ? 'Provision'
          : paymentMethods[p.method] ?? p.method;
      methods[k] = (methods[k] ?? 0) + p.amount;
    }
    final t = now();
    final months = <MonthPoint>[];
    for (var i = 5; i >= 0; i--) {
      final m = DateTime(t.year, t.month - i);
      final r = await result(m, DateTime(m.year, m.month + 1));
      months.add(MonthPoint(m, r.revenue, r.net));
    }
    return Report(
      revenue: revenue,
      margin: margin,
      expenses: await expensesTotal(from, to: to),
      count: list.length,
      topProducts: top.take(8).toList(),
      topMargins: topMargins.take(5).toList(),
      topClients: [
        for (final e in clients.entries)
          Ranked(
            e.key,
            e.value.$1,
            detail: '${e.value.$2} achat${e.value.$2 > 1 ? 's' : ''}',
          ),
      ]..sort((a, b) => b.value.compareTo(a.value)),
      sleeping: sleeping.take(8).toList(),
      methods: [for (final e in methods.entries) Ranked(e.key, e.value)]
        ..sort((a, b) => b.value.compareTo(a.value)),
      sellers: bySeller.length < 2 && bySeller.containsKey('Propriétaire')
          ? []
          : ([
              for (final e in bySeller.entries)
                Ranked(
                  e.key,
                  e.value.$1,
                  detail: '${e.value.$2} vente${e.value.$2 > 1 ? 's' : ''}',
                ),
            ]..sort((a, b) => b.value.compareTo(a.value))),
      months: months,
    );
  }

  /// Rapport de la journée, prêt à envoyer sur WhatsApp.
  Future<String> dailyReport({String shop = 'Ma boutique'}) async {
    final from = _today, to = from.add(const Duration(days: 1));
    final list = (await sales(
      from: from,
      to: to,
    )).where((s) => !s.sale.cancelled).toList();
    final details = await salesWithLines(list);
    final r = await result(from, to);
    String m(int x) => '${fcfa(x, unit: false).replaceAll('.', ' ')} F';
    final paid = list.fold<int>(0, (s, x) => s + x.paid);
    final credit = list.fold<int>(0, (s, x) => s + x.due);
    final byMethod = await todayByMethod();
    const days = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi'];
    const more = ['samedi', 'dimanche'];
    const months = [
      'janvier',
      'février',
      'mars',
      'avril',
      'mai',
      'juin',
      'juillet',
      'août',
      'septembre',
      'octobre',
      'novembre',
      'décembre',
    ];
    final day = [...days, ...more][from.weekday - 1];
    final l = <String>[
      '📊 *$shop* — rapport du $day ${from.day} ${months[from.month - 1]}',
      '',
      '🛒 Ventes : ${list.length} · ${m(r.revenue)}',
      '💵 Encaissé : ${m(paid)}${byMethod.isEmpty ? '' : ' (${byMethod.entries.map((e) => '${e.key} ${m(e.value)}').join(', ')})'}',
      if (credit > 0) '📝 Vendu à crédit : ${m(credit)}',
      if (r.expenses > 0) '💸 Dépenses : ${m(r.expenses)}',
      '✅ *Bénéfice du jour : ${m(r.net)}*',
      '🏦 Argent en caisse : ${m(await cashBalance())}',
    ];
    final closing = (await closings()).where(
      (c) => !c.createdAt.isBefore(from),
    );
    if (closing.isNotEmpty) {
      final gap = closing.first.counted - closing.first.expected;
      l.add(
        gap == 0
            ? '🔒 Clôture : caisse juste'
            : '🔒 Clôture : ${gap < 0 ? 'manque' : 'surplus'} de ${m(gap.abs())}',
      );
    }
    final top = <String, int>{};
    for (final d in details) {
      for (final x in d.lines) {
        top[x.product.name] = (top[x.product.name] ?? 0) + x.total;
      }
    }
    final best = top.entries.toList()..sort((a, b) => b.value - a.value);
    if (best.isNotEmpty) {
      l.addAll(['', '🏆 Meilleures ventes :']);
      for (var i = 0; i < best.length && i < 3; i++) {
        l.add('${i + 1}. ${best[i].key} — ${m(best[i].value)}');
      }
    }
    final low = await lowStock();
    if (low.isNotEmpty) {
      l.addAll(['', '⚠️ Stock à racheter :']);
      for (final s in low.take(6)) {
        l.add('• ${s.product.name} (${s.qty} ${s.product.unit})');
      }
    }
    return l.join('\n');
  }

  // ---------- Vendeurs ----------

  Future<List<Seller>> sellers({bool all = false}) {
    final q = db.select(db.sellers)..orderBy([(s) => OrderingTerm.asc(s.name)]);
    if (!all) q.where((s) => s.active.equals(true));
    return q.get();
  }

  Future<int> addSeller(String name, String pin) async {
    if (name.trim().isEmpty) throw ArgumentError('Donnez un nom.');
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      throw ArgumentError('Le code doit faire de 4 à 6 chiffres.');
    }
    final same = (await sellers()).any(
      (s) => normalize(s.name) == normalize(name),
    );
    if (same) throw ArgumentError('Ce vendeur existe déjà.');
    return db
        .into(db.sellers)
        .insert(
          SellersCompanion.insert(
            name: name.trim(),
            pinHash: _hash('vendeur', pin),
          ),
        );
  }

  /// Retire un vendeur : ses ventes passées restent à son nom.
  Future<void> removeSeller(int id) =>
      (db.update(db.sellers)..where((s) => s.id.equals(id))).write(
        const SellersCompanion(active: Value(false)),
      );

  Future<bool> checkSellerPin(Seller s, String pin) async =>
      s.pinHash == _hash('vendeur', pin);

  // ---------- Hors stock ----------

  /// Article acheté ailleurs, vendu sans passer par le stock. Le même nom
  /// réutilise la même fiche (prix mis à jour).
  Future<Product> adHocProduct({
    required String name,
    required int price,
    int cost = 0,
  }) async {
    final n = normalize(name);
    final existing =
        (await (db.select(
          db.products,
        )..where((p) => p.adHoc.equals(true))).get()).where(
          (p) => normalize(p.name) == n,
        );
    int id;
    if (existing.isNotEmpty) {
      id = existing.first.id;
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(price: Value(price), cost: Value(cost)),
      );
    } else {
      id = await db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: name.trim(),
              price: price,
              cost: Value(cost),
              adHoc: const Value(true),
            ),
          );
    }
    return (db.select(db.products)..where((p) => p.id.equals(id))).getSingle();
  }

  Future<List<String>> adHocNames() async => [
    for (final p
        in await (db.select(db.products)
              ..where((p) => p.adHoc.equals(true))
              ..orderBy([(p) => OrderingTerm.asc(p.name)]))
            .get())
      p.name,
  ];

  /// L'article hors stock devient un article du stock.
  Future<void> moveToStock(int productId) =>
      (db.update(db.products)..where((p) => p.id.equals(productId))).write(
        const ProductsCompanion(adHoc: Value(false)),
      );

  Future<AdHocSummary?> adHocThisMonth() async {
    final t = now();
    final list = (await sales(from: DateTime(t.year, t.month)))
        .where((s) => !s.sale.cancelled)
        .toList();
    var count = 0, revenue = 0, profit = 0;
    final names = <String>[];
    final times = <int, int>{};
    final byId = <int, Product>{};
    for (final d in await salesWithLines(list)) {
      for (final l in d.lines.where((l) => l.product.adHoc)) {
        count++;
        revenue += l.total;
        profit += l.margin;
        if (!names.contains(l.product.name)) names.add(l.product.name);
        times[l.product.id] = (times[l.product.id] ?? 0) + 1;
        byId[l.product.id] = l.product;
      }
    }
    if (count == 0) return null;
    return AdHocSummary(count, revenue, profit, names.take(4).toList(), [
      for (final e in times.entries)
        if (e.value >= 3) byId[e.key]!,
    ]);
  }

  // ---------- Retour d'article ----------

  /// Le client rapporte une partie d'une vente : les articles reviennent en
  /// stock, le total baisse et, s'il avait trop payé, on lui rend la
  /// différence. `qty` : quantité rendue par ligne de vente (id de la ligne).
  /// Renvoie l'argent à rendre au client.
  Future<int> returnItems(int saleId, Map<int, int> qty) => db.transaction(
    () async {
      final sale = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(saleId))).getSingle();
      if (sale.cancelled) throw StateError('Cette vente est annulée.');
      final lines = await (db.select(
        db.saleLines,
      )..where((l) => l.saleId.equals(saleId))).get();
      final back = {
        for (final e in qty.entries)
          if (e.value > 0) e.key: e.value,
      };
      if (back.isEmpty) {
        throw ArgumentError('Indiquez au moins une quantité rendue.');
      }
      final allBack = lines.every((l) => back[l.id] == l.qty);
      if (allBack) {
        throw ArgumentError('Le client rend tout : annulez plutôt la vente.');
      }
      final adHoc = {
        for (final p in await (db.select(
          db.products,
        )..where((p) => p.adHoc.equals(true))).get())
          p.id,
      };
      var amount = 0;
      for (final l in lines) {
        final q = back[l.id] ?? 0;
        if (q == 0) continue;
        if (q > l.qty) {
          throw ArgumentError(
            'On ne peut pas rendre plus que la quantité vendue.',
          );
        }
        amount += q * l.unitPrice;
        if (q == l.qty) {
          await (db.delete(db.saleLines)..where((x) => x.id.equals(l.id))).go();
        } else {
          await (db.update(db.saleLines)..where((x) => x.id.equals(l.id)))
              .write(SaleLinesCompanion(qty: Value(l.qty - q)));
        }
        if (!adHoc.contains(l.productId)) {
          await db
              .into(db.stockMoves)
              .insert(
                StockMovesCompanion.insert(
                  productId: l.productId,
                  delta: q,
                  reason: 'retour',
                  saleId: Value(saleId),
                  createdAt: now(),
                ),
              );
        }
      }
      final newTotal = sale.total - amount;
      await (db.update(db.sales)..where((s) => s.id.equals(saleId))).write(
        SalesCompanion(total: Value(newTotal)),
      );
      final paid =
          (await (db.select(
            db.payments,
          )..where((p) => p.saleId.equals(saleId))).get()).fold<int>(
            0,
            (s, p) => s + p.amount,
          );
      final refund = paid > newTotal ? paid - newTotal : 0;
      if (refund > 0) {
        await db
            .into(db.payments)
            .insert(
              PaymentsCompanion.insert(
                saleId: saleId,
                amount: -refund,
                method: 'especes',
                atSale: false,
                createdAt: now(),
              ),
            );
      }
      return refund;
    },
  );

  /// Lignes d'une vente avec leur identifiant, pour choisir quoi reprendre.
  Future<List<(SaleLine, Product)>> saleLinesOf(int saleId) async => [
    for (final r in await (db.select(db.saleLines).join([
      innerJoin(db.products, db.products.id.equalsExp(db.saleLines.productId)),
    ])..where(db.saleLines.saleId.equals(saleId))).get())
      (r.readTable(db.saleLines), r.readTable(db.products)),
  ];

  // ---------- Plan de versements ----------

  Future<void> setPurchaseTerms(
    int purchaseId, {
    required String terms,
    DateTime? dueDate,
  }) => (db.update(db.purchases)..where((p) => p.id.equals(purchaseId))).write(
    PurchasesCompanion(terms: Value(terms), dueDate: Value(dueDate)),
  );

  /// Ce qu'il reste à verser aux fournisseurs, par date. Un achat sans date
  /// limite est dû 30 jours après l'achat.
  Future<List<PlanRow>> paymentPlan() async {
    final today = _today;
    final rows = <PlanRow>[];
    // Ventes de chaque article, pour les achats payés « au fil des ventes ».
    final saleMoves = await (db.select(
      db.stockMoves,
    )..where((m) => m.reason.isIn(['vente', 'annulation', 'retour']))).get();
    for (final acc in await supplierAccounts()) {
      for (final s in acc.purchases.reversed) {
        if (s.due <= 0) continue;
        final p = s.purchase;
        final limit = p.dueDate ?? p.createdAt.add(const Duration(days: 30));
        final limitDay = DateTime(limit.year, limit.month, limit.day);
        if (p.terms != 'ventes') {
          rows.add(
            PlanRow(
              supplier: acc.contact,
              purchase: p,
              amount: s.due,
              date: limitDay,
              kind: 'limite',
              info: 'Échéance convenue',
            ),
          );
          continue;
        }
        // Valeur d'achat de ce qui s'est vendu depuis l'achat.
        var soldValue = 0, bought = 0, sold = 0;
        for (final l in s.lines.where((l) => l.productId != null)) {
          final out = -saleMoves
              .where(
                (m) =>
                    m.productId == l.productId &&
                    !m.createdAt.isBefore(p.createdAt),
              )
              .fold<int>(0, (t, m) => t + m.delta);
          final q = out.clamp(0, l.qty);
          soldValue += q * l.unitCost;
          bought += l.qty;
          sold += q;
        }
        if (!limitDay.isAfter(today)) {
          rows.add(
            PlanRow(
              supplier: acc.contact,
              purchase: p,
              amount: s.due,
              date: limitDay,
              kind: 'limite',
              info: 'Date limite dépassée, tout le reste est dû',
            ),
          );
          continue;
        }
        final now = (soldValue - s.paid).clamp(0, s.due);
        if (now > 0) {
          rows.add(
            PlanRow(
              supplier: acc.contact,
              purchase: p,
              amount: now,
              date: today,
              kind: 'ventes',
              info: '$sold vendus sur $bought achetés',
            ),
          );
        }
        if (s.due - now > 0) {
          rows.add(
            PlanRow(
              supplier: acc.contact,
              purchase: p,
              amount: s.due - now,
              date: limitDay,
              kind: 'attente',
              info: 'À verser au fil des ventes, au plus tard à la date',
            ),
          );
        }
      }
    }
    return rows..sort((a, b) {
      final c = a.date.compareTo(b.date);
      return c != 0 ? c : b.amount.compareTo(a.amount);
    });
  }

  // ---------- Inventaire ----------

  /// Compare les quantités comptées au stock de l'application.
  Future<List<InventoryGap>> inventoryGaps(Map<int, int> counted) async => [
    for (final s in await stock())
      if (counted.containsKey(s.product.id) && counted[s.product.id] != s.qty)
        InventoryGap(s.product, s.qty, counted[s.product.id]!),
  ];

  /// Valide l'inventaire : le stock prend les quantités comptées.
  Future<void> applyInventory(
    Map<int, int> counted, {
    bool lossAsExpense = false,
  }) async {
    final gaps = await inventoryGaps(counted);
    await db.transaction(() async {
      for (final g in gaps) {
        await adjustStock(g.product.id, g.gap, 'inventaire');
      }
      final missing = -gaps
          .where((g) => g.value < 0)
          .fold<int>(0, (s, g) => s + g.value);
      final surplus = gaps
          .where((g) => g.value > 0)
          .fold<int>(0, (s, g) => s + g.value);
      await db
          .into(db.inventories)
          .insert(
            InventoriesCompanion.insert(
              createdAt: now(),
              counted: counted.length,
              missingValue: missing,
              surplusValue: surplus,
              lines: [
                for (final g in gaps)
                  '${g.product.name.replaceAll('|', ' ')}|${g.before}|${g.after}|${g.value}',
              ].join('\n'),
            ),
          );
      if (lossAsExpense && missing > 0) {
        await addExpense(
          label: 'Pertes d’inventaire',
          amount: missing,
          category: 'Pertes',
        );
      }
    });
  }

  Future<List<Inventory>> inventories() =>
      (db.select(db.inventories)
            ..orderBy([(i) => OrderingTerm.desc(i.createdAt)])
            ..limit(10))
          .get();

  // ---------- Export et sauvegarde ----------

  /// Tableau CSV (séparateur « ; » pour Excel en français).
  Future<String> exportCsv(String what) async {
    String d(DateTime x) =>
        '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
    String cell(Object? v) {
      final s = '${v ?? ''}';
      return s.contains(RegExp(r'[;"\n]')) ? '"${s.replaceAll('"', '""')}"' : s;
    }

    final rows = <List<Object?>>[];
    switch (what) {
      case 'ventes':
        rows.add(['Date', 'Heure', 'Client', 'Articles', 'Total', 'Payé']);
        final list = (await sales()).where((s) => !s.sale.cancelled).toList();
        for (final x in await salesWithLines(list)) {
          final t = x.summary.sale.createdAt;
          rows.add([
            d(t),
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
            x.summary.contact?.name ?? 'Passage',
            x.lines.map((l) => '${l.qty}x ${l.product.name}').join(' / '),
            x.summary.sale.total,
            x.summary.paid,
          ]);
        }
      case 'stock':
        rows.add([
          'Article',
          'Unité',
          'Prix d’achat',
          'Prix de vente',
          'Quantité',
        ]);
        for (final s in await stock()) {
          rows.add([
            s.product.name,
            s.product.unit,
            s.product.cost,
            s.product.price,
            s.qty,
          ]);
        }
      case 'depenses':
        rows.add(['Date', 'Libellé', 'Catégorie', 'Montant']);
        for (final e in await expenses()) {
          rows.add([d(e.createdAt), e.label, e.category, e.amount]);
        }
      default:
        rows.add(['Date', 'Opération', 'Catégorie', 'Entrée', 'Sortie']);
        for (final e in await cashJournal()) {
          rows.add([
            d(e.at),
            e.label,
            e.category,
            if (e.amount > 0) e.amount else '',
            if (e.amount < 0) -e.amount else '',
          ]);
        }
    }
    return '﻿${rows.map((r) => r.map(cell).join(';')).join('\r\n')}';
  }

  /// Copie de toutes les données de la boutique, en JSON.
  Future<String> backupJson() async {
    final tables = <String, List<Map<String, Object?>>>{};
    for (final t in db.allTables) {
      final rows = await db
          .customSelect('SELECT * FROM "${t.actualTableName}"')
          .get();
      tables[t.actualTableName] = [for (final r in rows) r.data];
    }
    return jsonEncode({
      'app': 'flyfinance',
      'version': db.schemaVersion,
      'date': now().toIso8601String(),
      'tables': tables,
    });
  }

  /// Remplace toutes les données par celles d'une sauvegarde. Renvoie la
  /// date de la sauvegarde.
  Future<DateTime> restoreJson(String json) async {
    final Object? data;
    try {
      data = jsonDecode(json);
    } on FormatException {
      throw ArgumentError('Ce fichier n’est pas une sauvegarde FLYFINANCE.');
    }
    if (data is! Map || data['app'] != 'flyfinance' || data['tables'] is! Map) {
      throw ArgumentError('Ce fichier n’est pas une sauvegarde FLYFINANCE.');
    }
    if ((data['version'] as int? ?? 0) > db.schemaVersion) {
      throw ArgumentError(
        'Cette sauvegarde vient d’une version plus récente de l’application.',
      );
    }
    final tables = (data['tables'] as Map).cast<String, Object?>();
    await db.transaction(() async {
      await db.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final t in db.allTables) {
        await db.customStatement('DELETE FROM "${t.actualTableName}"');
      }
      for (final t in db.allTables) {
        final rows = tables[t.actualTableName];
        if (rows is! List) continue;
        final known = {for (final c in t.$columns) c.name};
        for (final r in rows.cast<Map>()) {
          final cols = [
            for (final k in r.keys.cast<String>())
              if (known.contains(k)) k,
          ];
          if (cols.isEmpty) continue;
          await db.customInsert(
            'INSERT INTO "${t.actualTableName}" '
            '(${cols.map((c) => '"$c"').join(', ')}) '
            'VALUES (${List.filled(cols.length, '?').join(', ')})',
            variables: [for (final c in cols) Variable(r[c])],
          );
        }
      }
    });
    return DateTime.tryParse('${data['date']}') ?? now();
  }
}
