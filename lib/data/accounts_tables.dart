import 'package:drift/drift.dart';

import 'database.dart';

/// Tables des comptes fournisseurs et clients. Les montants sont en FCFA
/// entiers. Rien ne se supprime : un achat ou un mouvement s'annule, pour
/// garder la trace de tout ce qui s'est passé.

/// Achat chez un fournisseur (un arrivage). Les articles entrent en stock.
class Purchases extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get supplierId => integer().references(Contacts, #id)();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get total => integer()();

  /// Numéro de la facture ou du bon de livraison du fournisseur.
  TextColumn get reference => text().nullable()();
  TextColumn get note => text().nullable()();
  BoolColumn get cancelled => boolean().withDefault(const Constant(false))();
}

class PurchaseLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get purchaseId => integer().references(Purchases, #id)();

  /// Article du stock, ou rien pour une dépense libre (transport, frais).
  IntColumn get productId => integer().nullable().references(Products, #id)();
  TextColumn get label => text()();
  IntColumn get qty => integer()();
  IntColumn get unitCost => integer()();
}

/// Mouvements d'argent d'un compte qui ne sont pas des paiements de vente.
class AccountEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().references(Contacts, #id)();

  /// 'versement' : argent versé à un fournisseur.
  /// 'provision' : argent déposé d'avance par un client.
  /// 'utilisee' : provision du client utilisée pour régler ses achats.
  /// 'rendue' : provision rendue au client.
  TextColumn get kind => text()();
  IntColumn get amount => integer()();

  /// 'especes', 'orange', 'mtn', 'moov', 'wave', 'virement' ou 'cheque'.
  TextColumn get method => text().withDefault(const Constant('especes'))();
  DateTimeColumn get createdAt => dateTime()();
  TextColumn get note => text().nullable()();

  /// Versement fait au moment d'un achat.
  IntColumn get purchaseId => integer().nullable().references(Purchases, #id)();
  BoolColumn get cancelled => boolean().withDefault(const Constant(false))();
}
