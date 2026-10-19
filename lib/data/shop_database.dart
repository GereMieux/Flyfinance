import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'shop_database.g.dart';

/// Base de la vente en ligne, séparée de la base de la boutique : le
/// catalogue présente des articles du stock (par `productId`) sans toucher
/// aux tables des ventes. Les prix sont en FCFA.
@DataClassName('ShopCategory')
class Categories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
}

@DataClassName('ShopBrand')
class Brands extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text().withLength(min: 1, max: 60)();
}

/// Un article du stock mis en ligne, avec sa présentation.
class ShopItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get productId => integer().unique()();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  IntColumn get brandId => integer().nullable().references(Brands, #id)();
  TextColumn get description => text().withDefault(const Constant(''))();

  /// Tailles et couleurs proposées, séparées par des virgules.
  TextColumn get sizes => text().withDefault(const Constant(''))();
  TextColumn get colors => text().withDefault(const Constant(''))();

  /// Prix affiché en ligne, s'il diffère du prix boutique.
  IntColumn get onlinePrice => integer().nullable()();
  BoolColumn get published => boolean().withDefault(const Constant(true))();
}

/// Promotion ou soldes. Sans article ni catégorie, elle vaut pour toute la
/// boutique. Soit un pourcentage, soit un prix promotionnel fixe.
class Promotions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 80)();
  TextColumn get details => text().withDefault(const Constant(''))();
  IntColumn get percent => integer().nullable()();
  IntColumn get promoPrice => integer().nullable()();
  IntColumn get itemId => integer().nullable().references(ShopItems, #id)();
  IntColumn get categoryId =>
      integer().nullable().references(Categories, #id)();
  BoolColumn get isSale => boolean().withDefault(const Constant(false))();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime()();
}

class Announcements extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withLength(min: 1, max: 80)();
  TextColumn get body => text().withDefault(const Constant(''))();
  DateTimeColumn get startsAt => dateTime()();
  DateTimeColumn get endsAt => dateTime().nullable()();
}

/// Réglages de la boutique en ligne (numéros Orange Money et Wave, frais de
/// livraison…), en clé / valeur.
class ShopSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

class Orders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get customerName => text().withLength(min: 1, max: 120)();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get address => text().withDefault(const Constant(''))();
  TextColumn get note => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime()();

  /// 'nouvelle', 'confirmee', 'livraison', 'livree' ou 'annulee'.
  TextColumn get status => text().withDefault(const Constant('nouvelle'))();

  /// 'orange', 'wave' ou 'livraison' (paiement à la livraison).
  TextColumn get payMethod => text()();
  BoolColumn get paid => boolean().withDefault(const Constant(false))();
  IntColumn get deliveryFee => integer().withDefault(const Constant(0))();

  /// Total des articles, sans les frais de livraison.
  IntColumn get total => integer()();

  /// Vente enregistrée dans la boutique quand la commande est livrée.
  IntColumn get saleId => integer().nullable()();
}

class OrderLines extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get orderId => integer().references(Orders, #id)();
  IntColumn get productId => integer()();
  TextColumn get name => text()();
  TextColumn get size => text().withDefault(const Constant(''))();
  TextColumn get color => text().withDefault(const Constant(''))();
  IntColumn get qty => integer()();
  IntColumn get unitPrice => integer()();
}

@DriftDatabase(
  tables: [
    Categories,
    Brands,
    ShopItems,
    Promotions,
    Announcements,
    ShopSettings,
    Orders,
    OrderLines,
  ],
)
class ShopDatabase extends _$ShopDatabase {
  ShopDatabase(super.e);

  /// Même clé de chiffrement que la base de la boutique, fichier à part.
  factory ShopDatabase.encrypted(String key) {
    final escaped = key.replaceAll("'", "''");
    return ShopDatabase(
      driftDatabase(
        name: 'flyfinance_en_ligne',
        native: DriftNativeOptions(
          setup: (db) {
            db.execute("PRAGMA key = '$escaped';");
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
