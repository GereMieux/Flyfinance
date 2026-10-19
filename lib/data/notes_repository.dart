import 'package:drift/drift.dart';

import 'database.dart';
import 'repository.dart';
import 'services_repository.dart';

/// Une note ou une liste, avec ses lignes (vide pour une note).
class NoteEntry {
  NoteEntry(this.note, this.items);
  final Note note;
  final List<NoteItem> items;

  int get doneCount => items.where((i) => i.done).length;

  /// Titre affiché : le titre, sinon la première ligne du texte.
  String get heading {
    if (note.title.trim().isNotEmpty) return note.title.trim();
    final first = note.isList
        ? (items.isEmpty ? '' : items.first.label)
        : note.body.trim().split('\n').first;
    return first.isEmpty
        ? (note.isList ? 'Liste sans titre' : 'Note vide')
        : first;
  }
}

extension Carnet on Repository {
  // ---------- Notes et listes ----------

  /// Notes et listes, épinglées d'abord puis les plus récentes. `query`
  /// cherche dans le titre, le texte et les lignes.
  Future<List<NoteEntry>> notes({bool? lists, String query = ''}) async {
    final q = db.select(db.notes)
      ..orderBy([
        (n) => OrderingTerm.desc(n.pinned),
        (n) => OrderingTerm.desc(n.updatedAt),
        (n) => OrderingTerm.desc(n.id),
      ]);
    if (lists != null) q.where((n) => n.isList.equals(lists));
    final rows = await q.get();
    final items = await (db.select(
      db.noteItems,
    )..orderBy([(i) => OrderingTerm.asc(i.position)])).get();
    final entries = [
      for (final n in rows)
        NoteEntry(n, items.where((i) => i.noteId == n.id).toList()),
    ];
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return entries;
    return entries
        .where(
          (e) =>
              e.note.title.toLowerCase().contains(needle) ||
              e.note.body.toLowerCase().contains(needle) ||
              e.items.any((i) => i.label.toLowerCase().contains(needle)),
        )
        .toList();
  }

  Future<NoteEntry> note(int id) async {
    final n = await (db.select(
      db.notes,
    )..where((n) => n.id.equals(id))).getSingle();
    return NoteEntry(n, await _items(id));
  }

  Future<List<NoteItem>> _items(int noteId) =>
      (db.select(db.noteItems)
            ..where((i) => i.noteId.equals(noteId))
            ..orderBy([(i) => OrderingTerm.asc(i.position)]))
          .get();

  Future<int> addNote({
    String title = '',
    String body = '',
    bool isList = false,
  }) {
    final t = now();
    return db
        .into(db.notes)
        .insert(
          NotesCompanion.insert(
            title: Value(title.trim()),
            body: Value(body.trim()),
            isList: Value(isList),
            createdAt: t,
            updatedAt: t,
          ),
        );
  }

  Future<void> saveNote(int id, {String? title, String? body}) =>
      (db.update(db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(
          title: title == null ? const Value.absent() : Value(title.trim()),
          body: body == null ? const Value.absent() : Value(body.trim()),
          updatedAt: Value(now()),
        ),
      );

  Future<void> setNotePinned(int id, bool pinned) =>
      (db.update(db.notes)..where((n) => n.id.equals(id))).write(
        NotesCompanion(pinned: Value(pinned)),
      );

  Future<void> deleteNote(int id) => db.transaction(() async {
    await (db.delete(db.noteItems)..where((i) => i.noteId.equals(id))).go();
    await (db.delete(db.notes)..where((n) => n.id.equals(id))).go();
  });

  /// Ajoute une ligne en bas de la liste.
  Future<int> addNoteItem(int noteId, String label) async {
    final text = label.trim();
    if (text.isEmpty) throw ArgumentError('Écrivez quelque chose.');
    return db.transaction(() async {
      final last = await _items(noteId);
      final id = await db
          .into(db.noteItems)
          .insert(
            NoteItemsCompanion.insert(
              noteId: noteId,
              label: text,
              position: last.isEmpty ? 0 : last.last.position + 1,
            ),
          );
      await _touch(noteId);
      return id;
    });
  }

  Future<void> setNoteItemDone(int itemId, bool done) =>
      _writeItem(itemId, NoteItemsCompanion(done: Value(done)));

  Future<void> renameNoteItem(int itemId, String label) {
    final text = label.trim();
    if (text.isEmpty) throw ArgumentError('Écrivez quelque chose.');
    return _writeItem(itemId, NoteItemsCompanion(label: Value(text)));
  }

  Future<void> deleteNoteItem(int itemId) => db.transaction(() async {
    final item = await (db.select(
      db.noteItems,
    )..where((i) => i.id.equals(itemId))).getSingle();
    await (db.delete(db.noteItems)..where((i) => i.id.equals(itemId))).go();
    await _touch(item.noteId);
  });

  /// Retire les lignes cochées d'une liste.
  Future<int> clearDoneItems(int noteId) => db.transaction(() async {
    final n = await (db.delete(
      db.noteItems,
    )..where((i) => i.noteId.equals(noteId) & i.done.equals(true))).go();
    await _touch(noteId);
    return n;
  });

  Future<void> _writeItem(int itemId, NoteItemsCompanion change) =>
      db.transaction(() async {
        final item = await (db.select(
          db.noteItems,
        )..where((i) => i.id.equals(itemId))).getSingle();
        await (db.update(
          db.noteItems,
        )..where((i) => i.id.equals(itemId))).write(change);
        await _touch(item.noteId);
      });

  Future<void> _touch(int noteId) =>
      (db.update(db.notes)..where((n) => n.id.equals(noteId))).write(
        NotesCompanion(updatedAt: Value(now())),
      );

  // ---------- Agenda ----------

  /// Rendez-vous du mois de `month`, du premier au dernier.
  Future<List<AppointmentItem>> monthAppointments(DateTime month) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(month.year, month.month + 1);
    return (await appointments(from: start))
        .where((a) => a.appointment.at.isBefore(end))
        .toList();
  }
}
