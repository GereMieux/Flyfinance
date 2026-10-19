import 'package:drift/drift.dart';

/// Bloc-notes : notes libres et listes à cocher. Les rendez-vous de l'agenda
/// sont dans `Appointments` (voir services_tables.dart), partagés avec
/// l'espace prestation.

/// Une note ou une liste. `isList` distingue les deux ; une liste a ses
/// lignes dans `NoteItems`, une note garde son texte dans `body`.
class Notes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant(''))();
  TextColumn get body => text().withDefault(const Constant(''))();
  BoolColumn get isList => boolean().withDefault(const Constant(false))();

  /// Épinglée : toujours en haut.
  BoolColumn get pinned => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

/// Lignes d'une liste (courses, choses à faire, articles à commander…).
class NoteItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get noteId => integer().references(Notes, #id)();
  TextColumn get label => text().withLength(min: 1, max: 300)();
  BoolColumn get done => boolean().withDefault(const Constant(false))();
  IntColumn get position => integer()();
}
