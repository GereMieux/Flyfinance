import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// Articles vendus en boutique. Les prix sont en FCFA (entiers, pas de centimes).
class Products extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get unit => text().withDefault(const Constant('pièce'))();
  IntColumn get price => integer()();
  IntColumn get wholesalePrice => integer().nullable()();
  IntColumn get cost => integer().withDefault(const Constant(0))();

  /// Seuil sous lequel l'article est signalé « bientôt en rupture ».
  IntColumn get alertMin => integer().withDefault(const Constant(0))();
  BoolColumn get archived => boolean().withDefault(const Constant(false))();
}

/// Clients et fournisseurs (carnet d'adresses).
class Contacts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 120)();
  TextColumn get phone => text().nullable()();

  /// 'client' ou 'fournisseur'.
  TextColumn get kind => text().withDefault(const Constant('client'))();
}

class Sales extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get contactId => integer().nullable().references(Contacts, #id)();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get total => integer()();
  BoolColumn get cancelled => boolean().withDefault(const Constant(false))();
}

class SaleLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get qty => integer()();
  IntColumn get unitPrice => integer()();
}

/// Encaissements. `atSale` distingue l'acompte versé à la vente des
/// remboursements faits plus tard (reliquat).
class Payments extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get saleId => integer().references(Sales, #id)();
  IntColumn get amount => integer()();

  /// 'especes', 'orange', 'mtn', 'moov' ou 'wave'.
  TextColumn get method => text()();
  BoolColumn get atSale => boolean()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Le stock n'est jamais stocké comme un chiffre : il est la somme des
/// mouvements, pour que deux appareils hors ligne restent justes après
/// synchronisation.
class StockMoves extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().references(Products, #id)();
  IntColumn get delta => integer()();

  /// 'achat', 'vente', 'perte', 'inventaire' ou 'annulation'.
  TextColumn get reason => text()();
  IntColumn get saleId => integer().nullable().references(Sales, #id)();
  DateTimeColumn get createdAt => dateTime()();
}

@DriftDatabase(
  tables: [Products, Contacts, Sales, SaleLines, Payments, StockMoves],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Ouvre la base chiffrée du téléphone avec la clé gardée dans le coffre
  /// sécurisé (voir `KeyStore`).
  factory AppDatabase.encrypted(String key) {
    final escaped = key.replaceAll("'", "''");
    return AppDatabase(
      driftDatabase(
        name: 'flyfinance',
        native: DriftNativeOptions(
          setup: (db) {
            db.execute("PRAGMA key = '$escaped';");
            // Échoue tout de suite si la clé est fausse ou la base illisible.
            db.select('SELECT count(*) FROM sqlite_master;');
          },
        ),
      ),
    );
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
