import 'package:drift/drift.dart';

/// Tables de la gestion quotidienne : dépenses, caisse, vendeurs et
/// inventaires. Les montants sont en FCFA entiers.

/// Dépense de la boutique (loyer, électricité, transport…). Elle entre dans
/// le bénéfice net et sort de la caisse.
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get label => text()();
  TextColumn get category => text().withDefault(const Constant('Autre'))();
  IntColumn get amount => integer()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Clôture de caisse du soir : l'argent compté comparé à l'argent attendu.
class CashClosings extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get expected => integer()();
  IntColumn get counted => integer()();

  /// Vrai si la caisse de l'application a été corrigée au montant compté :
  /// l'écart compte alors dans le journal de caisse.
  BoolColumn get adjusted => boolean().withDefault(const Constant(true))();
  TextColumn get note => text().nullable()();
  TextColumn get seller => text().nullable()();
}

/// Vendeur de la boutique, avec son code à lui.
class Sellers extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();

  /// Empreinte du code, jamais le code en clair.
  TextColumn get pinHash => text()();
  BoolColumn get active => boolean().withDefault(const Constant(true))();
}

/// Inventaire validé : résumé et détail des écarts (une ligne par article,
/// « nom|avant|après|valeur »).
class Inventories extends Table {
  IntColumn get id => integer().autoIncrement()();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get counted => integer()();
  IntColumn get missingValue => integer()();
  IntColumn get surplusValue => integer()();
  TextColumn get lines => text()();
}
