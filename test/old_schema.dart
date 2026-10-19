import 'package:flyfinance/data/database.dart';

/// Ramène une base neuve au schéma de la version 2 (avant les comptes
/// fournisseurs et clients), pour tester la mise à jour.
Future<void> downgradeToV2(AppDatabase db) async {
  await db.customStatement('PRAGMA foreign_keys = OFF');
  await db.customStatement('PRAGMA legacy_alter_table = ON');
  for (final t in ['account_entries', 'purchase_lines', 'purchases']) {
    await db.customStatement('DROP TABLE $t');
  }
  await db.customStatement('ALTER TABLE contacts RENAME TO contacts_v3');
  await db.customStatement(
    'CREATE TABLE contacts (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    'name TEXT NOT NULL, phone TEXT NULL, '
    "kind TEXT NOT NULL DEFAULT 'client')",
  );
  await db.customStatement(
    'INSERT INTO contacts SELECT id, name, phone, kind FROM contacts_v3',
  );
  await db.customStatement('DROP TABLE contacts_v3');
  await db.customStatement('ALTER TABLE stock_moves RENAME TO stock_moves_v3');
  await db.customStatement(
    'CREATE TABLE stock_moves (id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
    'product_id INTEGER NOT NULL REFERENCES products (id), '
    'delta INTEGER NOT NULL, reason TEXT NOT NULL, '
    'sale_id INTEGER NULL REFERENCES sales (id), created_at INTEGER NOT NULL)',
  );
  await db.customStatement(
    'INSERT INTO stock_moves SELECT id, product_id, delta, reason, sale_id, '
    'created_at FROM stock_moves_v3',
  );
  await db.customStatement('DROP TABLE stock_moves_v3');
  await db.customStatement('PRAGMA user_version = 2');
}
