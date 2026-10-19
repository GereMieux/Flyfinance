import 'package:drift/drift.dart';

import 'database.dart';

/// Tables de l'espace prestation : catalogue, devis, factures, paiements,
/// rendez-vous et fiche de l'entreprise. Les montants sont en FCFA entiers.

/// Prestations proposées (ex. « Pose de carrelage », 5 000 FCFA le m²).
class Services extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();

  /// 'forfait', 'heure', 'jour', 'm²', 'pièce'…
  TextColumn get unit => text().withDefault(const Constant('forfait'))();
  IntColumn get price => integer()();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// Devis et factures partagent la même forme ; `kind` les distingue.
class ServiceDocs extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// 'devis' ou 'facture'.
  TextColumn get kind => text()();

  /// DEV-2026-0001 ou FAC-2026-0001, unique.
  TextColumn get number => text().unique()();
  IntColumn get contactId => integer().references(Contacts, #id)();
  DateTimeColumn get createdAt => dateTime()();

  /// Fin de validité d'un devis, ou date limite de paiement d'une facture.
  DateTimeColumn get dueAt => dateTime().nullable()();

  /// Remise en FCFA, déduite avant la TVA.
  IntColumn get discount => integer().withDefault(const Constant(0))();

  /// TVA en pourcentage (0 ou 18 en Côte d'Ivoire).
  IntColumn get taxRate => integer().withDefault(const Constant(0))();

  /// Total à payer, TVA comprise, recalculé à chaque enregistrement.
  IntColumn get total => integer()();

  /// Devis : 'brouillon', 'envoye', 'accepte', 'refuse'.
  /// Facture : 'emise' ou 'annulee'.
  TextColumn get status => text()();
  TextColumn get note => text().nullable()();

  /// Pour une facture tirée d'un devis : le devis d'origine.
  IntColumn get sourceId => integer().nullable()();
}

class ServiceDocLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get docId => integer().references(ServiceDocs, #id)();
  IntColumn get serviceId => integer().nullable().references(Services, #id)();
  TextColumn get label => text()();
  RealColumn get qty => real()();
  TextColumn get unit => text().withDefault(const Constant('forfait'))();
  IntColumn get unitPrice => integer()();
}

/// Encaissements sur une facture (acompte, tranches, solde).
class ServicePayments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get docId => integer().references(ServiceDocs, #id)();
  IntColumn get amount => integer()();
  TextColumn get method => text()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Agenda : interventions, chantiers, rendez-vous clients.
class Appointments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().nullable().references(Contacts, #id)();
  TextColumn get title => text().withLength(min: 1, max: 160)();
  DateTimeColumn get at => dateTime()();
  TextColumn get place => text().nullable()();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
}

/// Réglages simples clé / valeur (fiche de l'entreprise sur les documents).
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
