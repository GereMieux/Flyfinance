import 'package:drift/drift.dart';

import 'database.dart';
import 'repository.dart';

/// Unités proposées pour une prestation.
const serviceUnits = ['forfait', 'heure', 'jour', 'm²', 'm', 'pièce', 'mois'];

/// TVA en Côte d'Ivoire.
const standardTaxRate = 18;

enum DocKind { devis, facture }

extension DocKindInfo on DocKind {
  String get key => name;
  String get label => this == DocKind.devis ? 'Devis' : 'Facture';
  String get prefix => this == DocKind.devis ? 'DEV' : 'FAC';
}

/// Statut affiché, calculé à partir du statut enregistré, des paiements et
/// des dates.
enum DocStatus {
  brouillon,
  envoye,
  accepte,
  refuse,
  expire,
  facture,
  impayee,
  partielle,
  enRetard,
  payee,
  annulee,
}

extension DocStatusLabel on DocStatus {
  String get label => switch (this) {
    DocStatus.brouillon => 'Brouillon',
    DocStatus.envoye => 'Envoyé',
    DocStatus.accepte => 'Accepté',
    DocStatus.refuse => 'Refusé',
    DocStatus.expire => 'Expiré',
    DocStatus.facture => 'Accepté, facturé',
    DocStatus.impayee => 'Impayée',
    DocStatus.partielle => 'Payée en partie',
    DocStatus.enRetard => 'En retard',
    DocStatus.payee => 'Payée',
    DocStatus.annulee => 'Annulée',
  };
}

/// Ligne en cours de saisie dans un devis ou une facture.
class DocLineInput {
  DocLineInput({
    required this.label,
    required this.qty,
    required this.unitPrice,
    this.unit = 'forfait',
    this.serviceId,
  });
  final String label;
  final double qty;
  final String unit;
  final int unitPrice;
  final int? serviceId;
  int get total => (qty * unitPrice).round();
}

/// Sous-total, remise, TVA et total d'un document.
class DocTotals {
  DocTotals(this.subtotal, this.discount, this.taxRate);
  final int subtotal;
  final int discount;
  final int taxRate;
  int get net => (subtotal - discount).clamp(0, subtotal);
  int get tax => (net * taxRate / 100).round();
  int get total => net + tax;

  static DocTotals of(List<DocLineInput> lines, int discount, int taxRate) =>
      DocTotals(lines.fold(0, (s, l) => s + l.total), discount, taxRate);
}

class DocSummary {
  DocSummary({
    required this.doc,
    required this.contact,
    required this.lines,
    required this.payments,
    required this.invoiced,
    required this.now,
  });
  final ServiceDoc doc;
  final Contact contact;
  final List<ServiceDocLine> lines;
  final List<ServicePayment> payments;

  /// Pour un devis : vrai s'il a déjà été transformé en facture.
  final bool invoiced;
  final DateTime now;

  DocKind get kind => DocKind.values.byName(doc.kind);
  bool get isQuote => kind == DocKind.devis;
  int get paid => payments.fold(0, (s, p) => s + p.amount);
  int get due => isQuote || doc.status == 'annulee'
      ? 0
      : (doc.total - paid).clamp(0, doc.total);

  DocTotals get totals => DocTotals(
    lines.fold(0, (s, l) => s + (l.qty * l.unitPrice).round()),
    doc.discount,
    doc.taxRate,
  );

  bool get _pastDue {
    final d = doc.dueAt;
    if (d == null) return false;
    return now.isAfter(DateTime(d.year, d.month, d.day, 23, 59, 59));
  }

  DocStatus get status {
    if (isQuote) {
      if (invoiced) return DocStatus.facture;
      return switch (doc.status) {
        'accepte' => DocStatus.accepte,
        'refuse' => DocStatus.refuse,
        _ when _pastDue => DocStatus.expire,
        'envoye' => DocStatus.envoye,
        _ => DocStatus.brouillon,
      };
    }
    if (doc.status == 'annulee') return DocStatus.annulee;
    if (paid >= doc.total) return DocStatus.payee;
    if (_pastDue) return DocStatus.enRetard;
    return paid > 0 ? DocStatus.partielle : DocStatus.impayee;
  }

  /// Ce qu'on peut encore attendre de ce devis (ni refusé, ni expiré, ni
  /// déjà facturé).
  bool get pendingQuote =>
      isQuote &&
      const [
        DocStatus.brouillon,
        DocStatus.envoye,
        DocStatus.accepte,
      ].contains(status);
}

class ServicesDashboard {
  ServicesDashboard({
    required this.invoicedMonth,
    required this.cashInMonth,
    required this.cashInToday,
    required this.outstanding,
    required this.overdue,
    required this.pendingQuotes,
    required this.pendingQuotesTotal,
    required this.upcoming,
  });
  final int invoicedMonth;
  final int cashInMonth;
  final int cashInToday;
  final int outstanding;
  final List<DocSummary> overdue;
  final int pendingQuotes;
  final int pendingQuotesTotal;
  final List<AppointmentItem> upcoming;
}

class AppointmentItem {
  AppointmentItem(this.appointment, this.contact);
  final Appointment appointment;
  final Contact? contact;
}

/// Clés de la fiche entreprise imprimée en tête des devis et factures.
const businessFields = {
  'biz.name': 'Nom de l’entreprise',
  'biz.activity': 'Activité (ex. Plomberie, Couture)',
  'biz.phone': 'Téléphone',
  'biz.email': 'E-mail',
  'biz.address': 'Adresse',
  'biz.legal': 'RCCM / N° contribuable',
  'biz.payment': 'Comment vous payer (ex. Wave 07 00 00 00 00)',
  'biz.terms': 'Conditions (ex. Acompte de 50 % à la commande)',
};

/// Règles métier de l'espace prestation. Comme pour les ventes, les écrans
/// passent par ici, jamais directement par la base.
extension Prestations on Repository {
  // ---------- Catalogue ----------

  Future<int> addService({
    required String name,
    required int price,
    String unit = 'forfait',
  }) => db
      .into(db.services)
      .insert(
        ServicesCompanion.insert(
          name: name.trim(),
          price: price,
          unit: Value(unit),
        ),
      );

  Future<void> updateService(
    int id, {
    required String name,
    required int price,
    required String unit,
  }) => (db.update(db.services)..where((s) => s.id.equals(id))).write(
    ServicesCompanion(
      name: Value(name.trim()),
      price: Value(price),
      unit: Value(unit),
    ),
  );

  Future<void> archiveService(int id) =>
      (db.update(db.services)..where((s) => s.id.equals(id))).write(
        const ServicesCompanion(archived: Value(true)),
      );

  Future<List<Service>> services() =>
      (db.select(db.services)
            ..where((s) => s.archived.equals(false))
            ..orderBy([(s) => OrderingTerm.asc(s.name)]))
          .get();

  // ---------- Devis et factures ----------

  Future<String> _nextNumber(DocKind kind) async {
    final prefix = '${kind.prefix}-${now().year}-';
    final rows = await (db.select(
      db.serviceDocs,
    )..where((d) => d.number.like('$prefix%'))).get();
    var max = 0;
    for (final r in rows) {
      final n = int.tryParse(r.number.substring(prefix.length)) ?? 0;
      if (n > max) max = n;
    }
    return '$prefix${(max + 1).toString().padLeft(4, '0')}';
  }

  /// Crée un devis ou une facture. Renvoie son identifiant.
  Future<int> createDoc({
    required DocKind kind,
    required int contactId,
    required List<DocLineInput> lines,
    int discount = 0,
    int taxRate = 0,
    DateTime? dueAt,
    String? note,
    int? sourceId,
  }) {
    _check(lines, discount, taxRate);
    return db.transaction(() async {
      final id = await db
          .into(db.serviceDocs)
          .insert(
            ServiceDocsCompanion.insert(
              kind: kind.key,
              number: await _nextNumber(kind),
              contactId: contactId,
              createdAt: now(),
              dueAt: Value(dueAt),
              discount: Value(discount),
              taxRate: Value(taxRate),
              total: DocTotals.of(lines, discount, taxRate).total,
              status: kind == DocKind.devis ? 'brouillon' : 'emise',
              note: Value(_blank(note)),
              sourceId: Value(sourceId),
            ),
          );
      await _writeLines(id, lines);
      return id;
    });
  }

  /// Modifie un document. Une facture déjà payée en partie ne peut pas
  /// descendre sous ce qui a été encaissé.
  Future<void> updateDoc(
    int id, {
    required int contactId,
    required List<DocLineInput> lines,
    int discount = 0,
    int taxRate = 0,
    DateTime? dueAt,
    String? note,
  }) {
    _check(lines, discount, taxRate);
    return db.transaction(() async {
      final total = DocTotals.of(lines, discount, taxRate).total;
      final s = await doc(id);
      if (s.doc.status == 'annulee') {
        throw StateError('Une facture annulée ne se modifie plus.');
      }
      if (total < s.paid) {
        throw StateError(
          'Le total ne peut pas être inférieur à ce qui est déjà encaissé.',
        );
      }
      await (db.update(db.serviceDocs)..where((d) => d.id.equals(id))).write(
        ServiceDocsCompanion(
          contactId: Value(contactId),
          dueAt: Value(dueAt),
          discount: Value(discount),
          taxRate: Value(taxRate),
          total: Value(total),
          note: Value(_blank(note)),
        ),
      );
      await (db.delete(
        db.serviceDocLines,
      )..where((l) => l.docId.equals(id))).go();
      await _writeLines(id, lines);
    });
  }

  void _check(List<DocLineInput> lines, int discount, int taxRate) {
    if (lines.isEmpty) throw ArgumentError('Ajoutez au moins une ligne.');
    if (lines.any((l) => l.qty <= 0 || l.unitPrice < 0)) {
      throw ArgumentError('Quantité et prix doivent être positifs.');
    }
    if (discount < 0) throw ArgumentError('La remise doit être positive.');
    if (taxRate < 0 || taxRate > 100) {
      throw ArgumentError('Le taux de TVA doit être entre 0 et 100.');
    }
  }

  String? _blank(String? s) =>
      (s == null || s.trim().isEmpty) ? null : s.trim();

  Future<void> _writeLines(int docId, List<DocLineInput> lines) async {
    for (final l in lines) {
      await db
          .into(db.serviceDocLines)
          .insert(
            ServiceDocLinesCompanion.insert(
              docId: docId,
              serviceId: Value(l.serviceId),
              label: l.label.trim(),
              qty: l.qty,
              unit: Value(l.unit),
              unitPrice: l.unitPrice,
            ),
          );
    }
  }

  /// Change le statut d'un devis : 'brouillon', 'envoye', 'accepte', 'refuse'.
  Future<void> setQuoteStatus(int id, String status) async {
    const allowed = ['brouillon', 'envoye', 'accepte', 'refuse'];
    if (!allowed.contains(status)) throw ArgumentError('Statut inconnu.');
    await (db.update(db.serviceDocs)
          ..where((d) => d.id.equals(id) & d.kind.equals('devis')))
        .write(ServiceDocsCompanion(status: Value(status)));
  }

  /// Transforme un devis en facture (le devis passe « Accepté »). Renvoie
  /// l'identifiant de la facture ; si elle existe déjà, la renvoie.
  Future<int> invoiceFromQuote(int quoteId, {DateTime? dueAt}) =>
      db.transaction(() async {
        final existing =
            await (db.select(db.serviceDocs)..where(
                  (d) => d.sourceId.equals(quoteId) & d.kind.equals('facture'),
                ))
                .getSingleOrNull();
        if (existing != null) return existing.id;
        final q = await doc(quoteId);
        if (!q.isQuote) throw ArgumentError('Ce document n’est pas un devis.');
        await setQuoteStatus(quoteId, 'accepte');
        return createDoc(
          kind: DocKind.facture,
          contactId: q.doc.contactId,
          lines: [for (final l in q.lines) _input(l)],
          discount: q.doc.discount,
          taxRate: q.doc.taxRate,
          dueAt: dueAt,
          note: q.doc.note,
          sourceId: quoteId,
        );
      });

  /// Crée une copie du document (même client, mêmes lignes), en brouillon.
  Future<int> duplicateDoc(int id) async {
    final s = await doc(id);
    return createDoc(
      kind: s.kind,
      contactId: s.doc.contactId,
      lines: [for (final l in s.lines) _input(l)],
      discount: s.doc.discount,
      taxRate: s.doc.taxRate,
      note: s.doc.note,
    );
  }

  DocLineInput _input(ServiceDocLine l) => DocLineInput(
    label: l.label,
    qty: l.qty,
    unit: l.unit,
    unitPrice: l.unitPrice,
    serviceId: l.serviceId,
  );

  /// Supprime un devis. Les factures ne se suppriment pas : on les annule,
  /// pour garder la numérotation continue.
  Future<void> deleteQuote(int id) => db.transaction(() async {
    final s = await doc(id);
    if (!s.isQuote) {
      throw StateError('Une facture ne se supprime pas, elle s’annule.');
    }
    await (db.update(db.serviceDocs)..where((d) => d.sourceId.equals(id)))
        .write(const ServiceDocsCompanion(sourceId: Value(null)));
    await (db.delete(
      db.serviceDocLines,
    )..where((l) => l.docId.equals(id))).go();
    await (db.delete(db.serviceDocs)..where((d) => d.id.equals(id))).go();
  });

  Future<void> cancelInvoice(int id) =>
      (db.update(db.serviceDocs)
            ..where((d) => d.id.equals(id) & d.kind.equals('facture')))
          .write(const ServiceDocsCompanion(status: Value('annulee')));

  /// Encaisse un paiement sur une facture. Renvoie le montant imputé (jamais
  /// plus que le reste à payer).
  Future<int> payInvoice(int id, int amount, {String method = 'especes'}) =>
      db.transaction(() async {
        if (amount <= 0) throw ArgumentError('Le montant doit être positif.');
        final s = await doc(id);
        if (s.isQuote) throw ArgumentError('On n’encaisse pas un devis.');
        final part = amount < s.due ? amount : s.due;
        if (part == 0) return 0;
        await db
            .into(db.servicePayments)
            .insert(
              ServicePaymentsCompanion.insert(
                docId: id,
                amount: part,
                method: method,
                createdAt: now(),
              ),
            );
        return part;
      });

  Future<DocSummary> doc(int id) async => (await docs(ids: [id])).single;

  /// Devis ou factures, du plus récent au plus ancien.
  Future<List<DocSummary>> docs({
    DocKind? kind,
    int? contactId,
    List<int>? ids,
  }) async {
    final q = db.select(db.serviceDocs).join([
      innerJoin(
        db.contacts,
        db.contacts.id.equalsExp(db.serviceDocs.contactId),
      ),
    ])..orderBy([OrderingTerm.desc(db.serviceDocs.createdAt)]);
    if (kind != null) q.where(db.serviceDocs.kind.equals(kind.key));
    if (contactId != null) q.where(db.serviceDocs.contactId.equals(contactId));
    if (ids != null) q.where(db.serviceDocs.id.isIn(ids));
    final rows = await q.get();
    final docIds = [for (final r in rows) r.readTable(db.serviceDocs).id];
    final lines = await (db.select(
      db.serviceDocLines,
    )..where((l) => l.docId.isIn(docIds))).get();
    final pays =
        await (db.select(db.servicePayments)
              ..where((p) => p.docId.isIn(docIds))
              ..orderBy([(p) => OrderingTerm.asc(p.createdAt)]))
            .get();
    final invoicedQuotes = {
      for (final d in await (db.select(
        db.serviceDocs,
      )..where((d) => d.sourceId.isNotNull() & d.kind.equals('facture'))).get())
        d.sourceId!,
    };
    final t = now();
    return [
      for (final r in rows)
        DocSummary(
          doc: r.readTable(db.serviceDocs),
          contact: r.readTable(db.contacts),
          lines: lines
              .where((l) => l.docId == r.readTable(db.serviceDocs).id)
              .toList(),
          payments: pays
              .where((p) => p.docId == r.readTable(db.serviceDocs).id)
              .toList(),
          invoiced: invoicedQuotes.contains(r.readTable(db.serviceDocs).id),
          now: t,
        ),
    ];
  }

  // ---------- Agenda ----------

  Future<int> addAppointment({
    required String title,
    required DateTime at,
    int? contactId,
    String? place,
  }) => db
      .into(db.appointments)
      .insert(
        AppointmentsCompanion.insert(
          title: title.trim(),
          at: at,
          contactId: Value(contactId),
          place: Value(_blank(place)),
        ),
      );

  Future<void> setAppointmentDone(int id, bool done) =>
      (db.update(db.appointments)..where((a) => a.id.equals(id))).write(
        AppointmentsCompanion(done: Value(done)),
      );

  Future<void> deleteAppointment(int id) =>
      (db.delete(db.appointments)..where((a) => a.id.equals(id))).go();

  /// Rendez-vous à partir de `from` (tous si nul), du plus proche au plus
  /// lointain.
  Future<List<AppointmentItem>> appointments({DateTime? from}) async {
    final q = db.select(db.appointments).join([
      leftOuterJoin(
        db.contacts,
        db.contacts.id.equalsExp(db.appointments.contactId),
      ),
    ])..orderBy([OrderingTerm.asc(db.appointments.at)]);
    if (from != null) q.where(db.appointments.at.isBiggerOrEqualValue(from));
    return [
      for (final r in await q.get())
        AppointmentItem(
          r.readTable(db.appointments),
          r.readTableOrNull(db.contacts),
        ),
    ];
  }

  // ---------- Fiche entreprise ----------

  Future<Map<String, String>> businessInfo() async => {
    for (final s in await db.select(db.settings).get())
      if (s.key.startsWith('biz.')) s.key: s.value,
  };

  Future<void> saveBusinessInfo(Map<String, String> info) =>
      db.transaction(() async {
        for (final e in info.entries) {
          if (e.value.trim().isEmpty) {
            await (db.delete(
              db.settings,
            )..where((s) => s.key.equals(e.key))).go();
          } else {
            await db
                .into(db.settings)
                .insertOnConflictUpdate(
                  SettingsCompanion.insert(key: e.key, value: e.value.trim()),
                );
          }
        }
      });

  // ---------- Tableau de bord ----------

  Future<ServicesDashboard> servicesDashboard() async {
    final t = now();
    final today = DateTime(t.year, t.month, t.day);
    final month = DateTime(t.year, t.month);
    final all = await docs();
    final invoices = all.where((d) => !d.isQuote && d.doc.status != 'annulee');
    var invoiced = 0, cashMonth = 0, cashToday = 0, outstanding = 0;
    for (final d in invoices) {
      if (!d.doc.createdAt.isBefore(month)) invoiced += d.doc.total;
      outstanding += d.due;
      for (final p in d.payments) {
        if (!p.createdAt.isBefore(month)) cashMonth += p.amount;
        if (!p.createdAt.isBefore(today)) cashToday += p.amount;
      }
    }
    final pending = all.where((d) => d.pendingQuote).toList();
    return ServicesDashboard(
      invoicedMonth: invoiced,
      cashInMonth: cashMonth,
      cashInToday: cashToday,
      outstanding: outstanding,
      overdue: invoices.where((d) => d.status == DocStatus.enRetard).toList(),
      pendingQuotes: pending.length,
      pendingQuotesTotal: pending.fold(0, (s, d) => s + d.doc.total),
      upcoming: (await appointments(from: today))
          .where((a) => !a.appointment.done)
          .take(5)
          .toList(),
    );
  }
}
