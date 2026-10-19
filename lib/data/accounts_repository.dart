import 'package:drift/drift.dart';

import 'database.dart';
import 'repository.dart';
import 'services_repository.dart';

/// Moyens de paiement d'un compte : ceux de la boutique, plus le virement et
/// le chèque souvent utilisés avec les fournisseurs.
const accountMethods = {
  ...paymentMethods,
  'virement': 'Virement',
  'cheque': 'Chèque',
};

/// Libellé d'un moyen de paiement, y compris « Provision ».
String methodLabel(String method) =>
    method == 'provision' ? 'Provision' : accountMethods[method] ?? method;

/// Une ligne d'achat en cours de saisie.
class PurchaseLineInput {
  PurchaseLineInput({
    required this.label,
    required this.qty,
    required this.unitCost,
    this.product,
  });
  final Product? product;
  final String label;
  final int qty;
  final int unitCost;
  int get total => qty * unitCost;
}

enum PurchaseStatus { paye, partiel, aPayer, annule }

extension PurchaseStatusLabel on PurchaseStatus {
  String get label => switch (this) {
    PurchaseStatus.paye => 'Payé',
    PurchaseStatus.partiel => 'Payé en partie',
    PurchaseStatus.aPayer => 'À payer',
    PurchaseStatus.annule => 'Annulé',
  };
}

class PurchaseSummary {
  PurchaseSummary(this.purchase, this.lines, this.paid);
  final Purchase purchase;
  final List<PurchaseLine> lines;

  /// Part déjà réglée : versements liés à l'achat, puis versements libres
  /// imputés aux achats les plus anciens d'abord.
  final int paid;

  int get due =>
      purchase.cancelled ? 0 : (purchase.total - paid).clamp(0, purchase.total);

  PurchaseStatus get status {
    if (purchase.cancelled) return PurchaseStatus.annule;
    if (due == 0) return PurchaseStatus.paye;
    return paid > 0 ? PurchaseStatus.partiel : PurchaseStatus.aPayer;
  }
}

/// Un mouvement du compte, pour l'historique.
class AccountMove {
  AccountMove({
    required this.at,
    required this.title,
    required this.amount,
    this.detail = '',
    this.cancelled = false,
    this.entry,
    this.purchase,
    this.sale,
    this.debit = false,
  });
  final DateTime at;
  final String title;
  final String detail;
  final int amount;
  final bool cancelled;

  /// Vrai pour ce qui augmente ce que l'on doit (achat, vente à payer).
  final bool debit;
  final AccountEntry? entry;
  final PurchaseSummary? purchase;
  final SaleSummary? sale;
}

class SupplierAccount {
  SupplierAccount({
    required this.contact,
    required this.bought,
    required this.paid,
    required this.purchases,
    required this.moves,
  });
  final Contact contact;
  final int bought;
  final int paid;
  final List<PurchaseSummary> purchases;

  /// Du plus récent au plus ancien.
  final List<AccountMove> moves;

  /// Ce que je dois encore au fournisseur (négatif : avance chez lui).
  int get balance => bought - paid;
  DateTime? get last => moves.isEmpty ? null : moves.first.at;
}

class ClientAccount {
  ClientAccount({
    required this.contact,
    required this.bought,
    required this.paid,
    required this.due,
    required this.provision,
    required this.moves,
  });
  final Contact contact;

  /// Ventes et factures, hors annulations.
  final int bought;

  /// Versements reçus, provision utilisée comprise.
  final int paid;

  /// Reste à payer.
  final int due;

  /// Provision encore disponible.
  final int provision;

  /// Du plus récent au plus ancien.
  final List<AccountMove> moves;
  DateTime? get last => moves.isEmpty ? null : moves.first.at;
}

/// Client à relancer : il doit de l'argent depuis assez longtemps et n'a pas
/// été relancé récemment.
class ReminderDue {
  ReminderDue(this.debtor, this.lastReminder);
  final Debtor debtor;
  final DateTime? lastReminder;
}

class ReminderSettings {
  const ReminderSettings({
    this.enabled = true,
    this.afterDays = 7,
    this.everyDays = 7,
    this.hour = 9,
    this.minute = 0,
    this.message = defaultReminderMessage,
  });

  /// Les relances sont proposées.
  final bool enabled;

  /// Relancer un client quand sa plus vieille dette a ce nombre de jours.
  final int afterDays;

  /// Puis relancer de nouveau tous les … jours.
  final int everyDays;

  /// Heure à partir de laquelle les relances du jour sont proposées.
  final int hour;
  final int minute;

  /// {nom} et {montant} sont remplacés pour chaque client.
  final String message;

  static const defaultReminderMessage =
      'Bonjour {nom}, petit rappel : il reste {montant} à régler à la '
      'boutique. Passez quand vous voulez pour solder votre compte. Merci !';

  String messageFor(String name, String amount) =>
      message.replaceAll('{nom}', name).replaceAll('{montant}', amount);
}

/// Comptes fournisseurs et clients, carnet d'adresses et relances.
extension Comptes on Repository {
  // ---------- Carnet d'adresses ----------

  Future<void> updateContact(
    int id, {
    required String name,
    String? phone,
    String? address,
  }) => (db.update(db.contacts)..where((c) => c.id.equals(id))).write(
    ContactsCompanion(
      name: Value(name.trim()),
      phone: Value(_blank(phone)),
      address: Value(_blank(address)),
    ),
  );

  Future<Contact> contact(int id) =>
      (db.select(db.contacts)..where((c) => c.id.equals(id))).getSingle();

  // ---------- Fournisseurs ----------

  /// Enregistre un achat : les articles entrent en stock, le prix d'achat
  /// des articles est mis à jour, et le montant payé tout de suite devient
  /// un versement lié à l'achat.
  Future<int> recordPurchase({
    required int supplierId,
    required List<PurchaseLineInput> lines,
    int paidNow = 0,
    String method = 'especes',
    DateTime? at,
    String? reference,
    String? note,
  }) {
    if (lines.isEmpty) throw ArgumentError('L’achat est vide.');
    if (lines.any((l) => l.qty <= 0 || l.unitCost < 0)) {
      throw ArgumentError('Quantité ou prix invalide.');
    }
    final total = lines.fold<int>(0, (s, l) => s + l.total);
    if (paidNow < 0 || paidNow > total) {
      throw ArgumentError('Le montant payé doit être entre 0 et $total.');
    }
    final when = at ?? now();
    return db.transaction(() async {
      final id = await db
          .into(db.purchases)
          .insert(
            PurchasesCompanion.insert(
              supplierId: supplierId,
              createdAt: when,
              total: total,
              reference: Value(_blank(reference)),
              note: Value(_blank(note)),
            ),
          );
      for (final l in lines) {
        await db
            .into(db.purchaseLines)
            .insert(
              PurchaseLinesCompanion.insert(
                purchaseId: id,
                productId: Value(l.product?.id),
                label: l.label.trim(),
                qty: l.qty,
                unitCost: l.unitCost,
              ),
            );
        final p = l.product;
        if (p == null) continue;
        await db
            .into(db.stockMoves)
            .insert(
              StockMovesCompanion.insert(
                productId: p.id,
                delta: l.qty,
                reason: 'achat',
                purchaseId: Value(id),
                createdAt: when,
              ),
            );
        if (l.unitCost > 0 && l.unitCost != p.cost) {
          await (db.update(db.products)..where((x) => x.id.equals(p.id))).write(
            ProductsCompanion(cost: Value(l.unitCost)),
          );
        }
      }
      if (paidNow > 0) {
        await db
            .into(db.accountEntries)
            .insert(
              AccountEntriesCompanion.insert(
                contactId: supplierId,
                kind: 'versement',
                amount: paidNow,
                method: Value(method),
                createdAt: when,
                purchaseId: Value(id),
              ),
            );
      }
      return id;
    });
  }

  /// Annule un achat : les articles ressortent du stock. Refusé si le stock
  /// a déjà été vendu. Les versements restent comptés (avance chez le
  /// fournisseur) ; ils s'annulent à part s'ils étaient une erreur.
  Future<void> cancelPurchase(int purchaseId) => db.transaction(() async {
    final p = await (db.select(
      db.purchases,
    )..where((x) => x.id.equals(purchaseId))).getSingle();
    if (p.cancelled) return;
    final lines = await (db.select(
      db.purchaseLines,
    )..where((l) => l.purchaseId.equals(purchaseId))).get();
    for (final l in lines.where((l) => l.productId != null)) {
      final left = await stockOf(l.productId!);
      if (left < l.qty) {
        throw StateError(
          'Impossible d’annuler : il ne reste que $left ${l.label} en stock.',
        );
      }
    }
    for (final l in lines.where((l) => l.productId != null)) {
      await db
          .into(db.stockMoves)
          .insert(
            StockMovesCompanion.insert(
              productId: l.productId!,
              delta: -l.qty,
              reason: 'annulation_achat',
              purchaseId: Value(purchaseId),
              createdAt: now(),
            ),
          );
    }
    await (db.update(db.purchases)..where((x) => x.id.equals(purchaseId)))
        .write(const PurchasesCompanion(cancelled: Value(true)));
  });

  /// Versement à un fournisseur (règlement d'un ou plusieurs achats, ou
  /// avance).
  Future<int> paySupplier(
    int supplierId,
    int amount, {
    String method = 'especes',
    DateTime? at,
    String? note,
  }) {
    if (amount <= 0) throw ArgumentError('Le montant doit être positif.');
    return _entry(supplierId, 'versement', amount, method, at, note);
  }

  /// Annule un versement fournisseur, une provision ou un rendu de
  /// provision. Une provision déjà utilisée ne s'annule pas.
  Future<void> cancelEntry(int entryId) => db.transaction(() async {
    final e = await (db.select(
      db.accountEntries,
    )..where((x) => x.id.equals(entryId))).getSingle();
    if (e.cancelled) return;
    if (e.kind == 'utilisee') {
      throw StateError('Une provision utilisée ne s’annule pas.');
    }
    if (e.kind == 'provision' && await provisionOf(e.contactId) < e.amount) {
      throw StateError('Cette provision a déjà été utilisée.');
    }
    await (db.update(db.accountEntries)..where((x) => x.id.equals(entryId)))
        .write(const AccountEntriesCompanion(cancelled: Value(true)));
  });

  Future<List<SupplierAccount>> supplierAccounts() async {
    final suppliers = await contacts(kind: 'fournisseur');
    return [for (final c in suppliers) await supplierAccount(c.id)]
      ..sort((a, b) => b.balance.compareTo(a.balance));
  }

  Future<SupplierAccount> supplierAccount(int supplierId) async {
    final c = await contact(supplierId);
    final purchases =
        await (db.select(db.purchases)
              ..where((p) => p.supplierId.equals(supplierId))
              ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
            .get();
    final ids = [for (final p in purchases) p.id];
    final lines = await (db.select(
      db.purchaseLines,
    )..where((l) => l.purchaseId.isIn(ids))).get();
    final entries = await _entries(supplierId);
    final live = entries.where((e) => !e.cancelled && e.kind == 'versement');
    final paidTotal = live.fold<int>(0, (s, e) => s + e.amount);

    // Imputation : d'abord les versements liés à chaque achat, puis le reste
    // sur les achats les plus anciens.
    final paid = <int, int>{};
    var free = 0;
    for (final e in live) {
      final pid = e.purchaseId;
      final p = pid == null ? null : purchases.where((x) => x.id == pid);
      if (p == null || p.isEmpty || p.first.cancelled) {
        free += e.amount;
        continue;
      }
      final room = p.first.total - (paid[pid] ?? 0);
      final part = e.amount < room ? e.amount : room;
      paid[pid!] = (paid[pid] ?? 0) + part;
      free += e.amount - part;
    }
    for (final p in purchases.where((p) => !p.cancelled)) {
      final room = p.total - (paid[p.id] ?? 0);
      final part = free < room ? free : room;
      paid[p.id] = (paid[p.id] ?? 0) + part;
      free -= part;
    }
    final summaries = [
      for (final p in purchases.reversed)
        PurchaseSummary(
          p,
          lines.where((l) => l.purchaseId == p.id).toList(),
          paid[p.id] ?? 0,
        ),
    ];
    final moves = <AccountMove>[
      for (final s in summaries)
        AccountMove(
          at: s.purchase.createdAt,
          title: 'Achat',
          detail: [
            if (s.purchase.reference != null) 'N° ${s.purchase.reference}',
            '${s.lines.length} ligne${s.lines.length > 1 ? 's' : ''}',
            s.status.label,
          ].join(' · '),
          amount: s.purchase.total,
          cancelled: s.purchase.cancelled,
          debit: true,
          purchase: s,
        ),
      for (final e in entries)
        AccountMove(
          at: e.createdAt,
          title: 'Versement',
          detail: [
            methodLabel(e.method),
            if (e.note != null) e.note!,
          ].join(' · '),
          amount: e.amount,
          cancelled: e.cancelled,
          entry: e,
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    return SupplierAccount(
      contact: c,
      bought: purchases
          .where((p) => !p.cancelled)
          .fold(0, (s, p) => s + p.total),
      paid: paidTotal,
      purchases: summaries,
      moves: moves,
    );
  }

  /// Total dû à tous les fournisseurs.
  Future<int> supplierDebt() async => (await supplierAccounts()).fold<int>(
    0,
    (s, a) => s + (a.balance > 0 ? a.balance : 0),
  );

  // ---------- Clients ----------

  /// Provision déposée d'avance par un client.
  Future<int> addProvision(
    int clientId,
    int amount, {
    String method = 'especes',
    DateTime? at,
    String? note,
  }) {
    if (amount <= 0) throw ArgumentError('Le montant doit être positif.');
    return _entry(clientId, 'provision', amount, method, at, note);
  }

  /// Rend tout ou partie de la provision au client.
  Future<int> returnProvision(
    int clientId,
    int amount, {
    String method = 'especes',
  }) => db.transaction(() async {
    if (amount <= 0) throw ArgumentError('Le montant doit être positif.');
    final left = await provisionOf(clientId);
    if (amount > left) {
      throw StateError('La provision disponible est de $left FCFA.');
    }
    return _entry(clientId, 'rendue', amount, method, null, null);
  });

  Future<int> provisionOf(int clientId) async {
    var left = 0;
    for (final e in await _entries(clientId)) {
      if (e.cancelled) continue;
      left += e.kind == 'provision'
          ? e.amount
          : (e.kind == 'utilisee' || e.kind == 'rendue')
          ? -e.amount
          : 0;
    }
    return left;
  }

  /// Règle les ventes puis les factures du client, des plus anciennes aux
  /// plus récentes, avec sa provision. Renvoie le montant utilisé.
  Future<int> useProvision(int clientId, {int? amount}) =>
      db.transaction(() async {
        final available = await provisionOf(clientId);
        var left = amount == null || amount > available ? available : amount;
        if (left <= 0) return 0;
        final start = left;
        left -= await receivePayment(clientId, left, method: 'provision');
        final invoices =
            (await docs(
                kind: DocKind.facture,
                contactId: clientId,
              )).where((d) => d.due > 0).toList()
              ..sort((a, b) => a.doc.createdAt.compareTo(b.doc.createdAt));
        for (final d in invoices) {
          if (left == 0) break;
          left -= await payInvoice(d.doc.id, left, method: 'provision');
        }
        final used = start - left;
        if (used > 0) {
          await _entry(clientId, 'utilisee', used, 'provision', null, null);
        }
        return used;
      });

  Future<ClientAccount> clientAccount(int clientId) async {
    final c = await contact(clientId);
    final sales = (await this.sales()).where((s) => s.contact?.id == clientId);
    final saleIds = [for (final s in sales) s.sale.id];
    final pays = await (db.select(
      db.payments,
    )..where((p) => p.saleId.isIn(saleIds))).get();
    final invoices = await docs(kind: DocKind.facture, contactId: clientId);
    final entries = await _entries(clientId);
    final cancelledSales = {
      for (final s in sales)
        if (s.sale.cancelled) s.sale.id,
    };

    var bought = 0, paid = 0, due = 0;
    for (final s in sales.where((s) => !s.sale.cancelled)) {
      bought += s.sale.total;
      paid += s.paid;
      due += s.due;
    }
    for (final d in invoices.where((d) => d.doc.status != 'annulee')) {
      bought += d.doc.total;
      paid += d.paid;
      due += d.due;
    }

    final moves = <AccountMove>[
      for (final s in sales)
        AccountMove(
          at: s.sale.createdAt,
          title: 'Achat en boutique',
          detail: s.status.label,
          amount: s.sale.total,
          cancelled: s.sale.cancelled,
          debit: true,
          sale: s,
        ),
      for (final p in pays)
        if (p.method != 'provision')
          AccountMove(
            at: p.createdAt,
            title: p.atSale ? 'Payé à l’achat' : 'Versement',
            detail: methodLabel(p.method),
            amount: p.amount,
            cancelled: cancelledSales.contains(p.saleId),
          ),
      for (final d in invoices)
        AccountMove(
          at: d.doc.createdAt,
          title: 'Facture ${d.doc.number}',
          detail: d.status.label,
          amount: d.doc.total,
          cancelled: d.doc.status == 'annulee',
          debit: true,
        ),
      for (final d in invoices)
        for (final p in d.payments)
          if (p.method != 'provision')
            AccountMove(
              at: p.createdAt,
              title: 'Versement · ${d.doc.number}',
              detail: methodLabel(p.method),
              amount: p.amount,
              cancelled: d.doc.status == 'annulee',
            ),
      for (final e in entries)
        AccountMove(
          at: e.createdAt,
          title: switch (e.kind) {
            'provision' => 'Provision déposée',
            'utilisee' => 'Provision utilisée',
            'rendue' => 'Provision rendue',
            _ => 'Versement',
          },
          detail: [
            if (e.kind != 'utilisee') methodLabel(e.method),
            if (e.note != null) e.note!,
          ].join(' · '),
          amount: e.amount,
          cancelled: e.cancelled,
          debit: e.kind == 'rendue',
          entry: e,
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));

    return ClientAccount(
      contact: c,
      bought: bought,
      paid: paid,
      due: due,
      provision: await provisionOf(clientId),
      moves: moves,
    );
  }

  /// Comptes de tous les clients, ceux qui doivent le plus en premier.
  Future<List<ClientAccount>> clientAccounts() async {
    final list = [
      for (final c in await contacts(kind: 'client')) await clientAccount(c.id),
    ];
    return list..sort((a, b) {
      final d = b.due.compareTo(a.due);
      return d != 0 ? d : a.contact.name.compareTo(b.contact.name);
    });
  }

  // ---------- Relances ----------

  Future<ReminderSettings> reminderSettings() async {
    final rows = await (db.select(
      db.settings,
    )..where((s) => s.key.like('relance.%'))).get();
    final m = {for (final r in rows) r.key: r.value};
    int n(String k, int d) => int.tryParse(m['relance.$k'] ?? '') ?? d;
    return ReminderSettings(
      enabled: m['relance.active'] != 'non',
      afterDays: n('apres', 7),
      everyDays: n('tous', 7),
      hour: n('heure', 9),
      minute: n('minute', 0),
      message: m['relance.message'] ?? ReminderSettings.defaultReminderMessage,
    );
  }

  Future<void> saveReminderSettings(ReminderSettings s) =>
      db.transaction(() async {
        final values = {
          'relance.active': s.enabled ? 'oui' : 'non',
          'relance.apres': '${s.afterDays}',
          'relance.tous': '${s.everyDays}',
          'relance.heure': '${s.hour}',
          'relance.minute': '${s.minute}',
          'relance.message': s.message.trim().isEmpty
              ? ReminderSettings.defaultReminderMessage
              : s.message.trim(),
        };
        for (final e in values.entries) {
          await db
              .into(db.settings)
              .insertOnConflictUpdate(
                SettingsCompanion.insert(key: e.key, value: e.value),
              );
        }
      });

  /// Note qu'un client vient d'être relancé.
  Future<void> markReminded(int clientId) => db
      .into(db.settings)
      .insertOnConflictUpdate(
        SettingsCompanion.insert(
          key: 'relance.client.$clientId',
          value: now().toIso8601String(),
        ),
      );

  /// Clients à relancer maintenant, selon le délai et l'heure choisis.
  Future<List<ReminderDue>> remindersDue() async {
    final s = await reminderSettings();
    final t = now();
    if (!s.enabled) return [];
    if (t.isBefore(DateTime(t.year, t.month, t.day, s.hour, s.minute))) {
      return [];
    }
    final last = await lastReminders();
    final out = <ReminderDue>[];
    for (final d in await debtors()) {
      if (_days(d.oldest, t) < s.afterDays) continue;
      final l = last[d.contact.id];
      if (l != null && _days(l, t) < s.everyDays) continue;
      out.add(ReminderDue(d, l));
    }
    return out;
  }

  /// Dernière relance de chaque client.
  Future<Map<int, DateTime>> lastReminders() async {
    final rows = await (db.select(
      db.settings,
    )..where((x) => x.key.like('relance.client.%'))).get();
    return {
      for (final r in rows)
        int.parse(r.key.substring('relance.client.'.length)): DateTime.parse(
          r.value,
        ),
    };
  }

  // ---------- Commun ----------

  Future<List<AccountEntry>> _entries(int contactId) =>
      (db.select(db.accountEntries)
            ..where((e) => e.contactId.equals(contactId))
            ..orderBy([(e) => OrderingTerm.asc(e.createdAt)]))
          .get();

  Future<int> _entry(
    int contactId,
    String kind,
    int amount,
    String method,
    DateTime? at,
    String? note,
  ) => db
      .into(db.accountEntries)
      .insert(
        AccountEntriesCompanion.insert(
          contactId: contactId,
          kind: kind,
          amount: amount,
          method: Value(method),
          createdAt: at ?? now(),
          note: Value(_blank(note)),
        ),
      );
}

/// Jours de calendrier entre deux dates (hier 23 h → aujourd'hui 8 h = 1).
int _days(DateTime a, DateTime b) => DateTime(
  b.year,
  b.month,
  b.day,
).difference(DateTime(a.year, a.month, a.day)).inDays;

String? _blank(String? s) {
  final t = s?.trim();
  return t == null || t.isEmpty ? null : t;
}
