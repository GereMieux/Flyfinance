import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/app_state.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/notes_repository.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/data/services_repository.dart';
import 'package:flyfinance/ui/agenda/agenda_screen.dart';
import 'package:flyfinance/ui/theme.dart';
import 'package:provider/provider.dart';

import 'old_schema.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('bloc-notes', () {
    late AppDatabase db;
    late Repository repo;
    var clock = DateTime(2026, 10, 19, 10);

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      repo = Repository(db)..now = () => clock;
      clock = DateTime(2026, 10, 19, 10);
    });
    tearDown(() => db.close());

    test('notes : épinglées en haut, puis les plus récentes', () async {
      final a = await repo.addNote(title: 'Fournisseur riz', body: 'Appeler');
      clock = clock.add(const Duration(hours: 1));
      final b = await repo.addNote(body: 'Idée\nVendre du savon');
      var all = await repo.notes(lists: false);
      expect(all.map((e) => e.note.id), [b, a]);
      expect(all.first.heading, 'Idée');

      await repo.setNotePinned(a, true);
      all = await repo.notes(lists: false);
      expect(all.map((e) => e.note.id), [a, b]);

      expect((await repo.notes(query: 'SAVON')).single.note.id, b);
      clock = clock.add(const Duration(hours: 1));
      await repo.saveNote(a, body: 'Appeler lundi');
      expect((await repo.note(a)).note.updatedAt, clock);
      await repo.deleteNote(b);
      expect((await repo.notes()).length, 1);
    });

    test('listes : ajout, cases, retrait des cochés', () async {
      final l = await repo.addNote(title: 'Courses', isList: true);
      final riz = await repo.addNoteItem(l, 'Riz 25 kg');
      await repo.addNoteItem(l, 'Huile');
      await repo.addNoteItem(l, 'Sucre');
      expect(() => repo.addNoteItem(l, '  '), throwsArgumentError);

      await repo.setNoteItemDone(riz, true);
      var e = await repo.note(l);
      expect(e.items.map((i) => i.label), ['Riz 25 kg', 'Huile', 'Sucre']);
      expect(e.doneCount, 1);
      expect((await repo.notes(lists: true, query: 'huile')).length, 1);
      expect(await repo.notes(lists: false), isEmpty);

      expect(await repo.clearDoneItems(l), 1);
      e = await repo.note(l);
      expect(e.items.map((i) => i.label), ['Huile', 'Sucre']);

      await repo.renameNoteItem(e.items.first.id, 'Huile 5 L');
      await repo.deleteNoteItem(e.items.last.id);
      expect((await repo.note(l)).items.single.label, 'Huile 5 L');

      await repo.deleteNote(l);
      expect(await db.select(db.noteItems).get(), isEmpty);
    });

    test('agenda : rendez-vous du mois seulement', () async {
      await repo.addAppointment(title: 'Fin sept', at: DateTime(2026, 9, 30));
      await repo.addAppointment(title: 'Livraison', at: DateTime(2026, 10, 21));
      await repo.addAppointment(
        title: 'Fin oct',
        at: DateTime(2026, 10, 31, 23),
      );
      await repo.addAppointment(title: 'Nov', at: DateTime(2026, 11, 1));
      final oct = await repo.monthAppointments(DateTime(2026, 10, 15));
      expect(oct.map((a) => a.appointment.title), ['Livraison', 'Fin oct']);
    });
  });

  test('une base de la version 2 reçoit le bloc-notes', () async {
    final dir = await Directory.systemTemp.createTemp('flyfinance');
    final file = File('${dir.path}/v2.db');
    final old = AppDatabase(NativeDatabase(file));
    await Repository(
      old,
    ).addAppointment(title: 'Ancien rendez-vous', at: DateTime(2026, 10, 20));
    await downgradeToV3(old);
    await old.customStatement('DROP TABLE note_items');
    await old.customStatement('DROP TABLE notes');
    await old.customStatement('PRAGMA user_version = 2');
    await old.close();

    final db2 = AppDatabase(NativeDatabase(file));
    final r = Repository(db2);
    expect(
      (await r.appointments()).single.appointment.title,
      'Ancien rendez-vous',
    );
    final l = await r.addNote(title: 'Courses', isList: true);
    await r.addNoteItem(l, 'Riz');
    expect((await r.note(l)).items.single.label, 'Riz');
    await db2.close();
    await dir.delete(recursive: true);
  });

  testWidgets('écran agenda et notes', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final repo = Repository(db);
    final state = AppState(repo);
    final t = DateTime.now();
    await tester.runAsync(() async {
      await repo.addAppointment(
        title: 'Livraison ciment',
        at: DateTime(t.year, t.month, t.day, 15),
      );
      final l = await repo.addNote(title: 'Courses', isList: true);
      await repo.addNoteItem(l, 'Riz');
      await repo.addNote(title: 'Mot de passe wifi', body: 'Voir la box');
    });

    Future<void> settle() async {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)),
      );
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: state,
        child: MaterialApp(theme: buildTheme(), home: const AgendaScreen()),
      ),
    );
    await settle();
    // Le jour choisi est aujourd'hui : son rendez-vous est affiché.
    expect(find.text('Livraison ciment'), findsOneWidget);

    await tester.tap(find.text('Notes'));
    await settle();
    expect(find.text('Mot de passe wifi'), findsOneWidget);
    expect(find.text('Courses'), findsNothing);

    // Nouvelle note, enregistrée en quittant l'écran.
    await tester.tap(find.text('Note'));
    await settle();
    await tester.enterText(find.byType(TextField).last, 'Payer le loyer');
    await tester.tap(find.byTooltip('Terminé'));
    await settle();
    expect(find.text('Payer le loyer'), findsOneWidget);

    await tester.tap(find.text('Listes'));
    await settle();
    expect(find.text('0 sur 1 fait'), findsOneWidget);
    await tester.tap(find.text('Courses'));
    await settle();
    await tester.enterText(find.byType(TextField), 'Huile');
    await tester.tap(find.byTooltip('Ajouter'));
    await settle();
    await tester.tap(find.byType(Checkbox).first);
    await settle();
    expect(find.text('1 sur 2 fait'), findsOneWidget);
    await tester.tap(find.text('Retirer les cochés'));
    await settle();
    expect(find.text('Riz'), findsNothing);
    expect(find.text('Huile'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
