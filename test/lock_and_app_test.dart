import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/app_state.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/data/shop_database.dart';
import 'package:flyfinance/data/shop_repository.dart';
import 'package:flyfinance/main.dart';
import 'package:flyfinance/security/lock_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('LockService', () {
    test('le code est stocké haché, jamais en clair', () async {
      final store = MemorySecretStore();
      final lock = LockService(store);
      await lock.setPin('2580');
      expect(await store.read('pin_hash'), isNot(contains('2580')));
      lock.lock();
      expect(await lock.unlockWithPin('1111'), isFalse);
      expect(await lock.unlockWithPin('2580'), isTrue);
    });

    test('5 erreurs bloquent une minute', () async {
      var t = DateTime(2026, 10, 19, 10);
      final lock = LockService(MemorySecretStore(), now: () => t);
      await lock.setPin('2580');
      lock.lock();
      for (var i = 0; i < 5; i++) {
        await lock.unlockWithPin('0000');
      }
      expect(lock.lockoutRemaining, isNotNull);
      expect(await lock.unlockWithPin('2580'), isFalse);
      t = t.add(const Duration(minutes: 1, seconds: 1));
      expect(await lock.unlockWithPin('2580'), isTrue);
    });

    test('verrouillage automatique après 5 minutes en arrière-plan', () async {
      var t = DateTime(2026, 10, 19, 10);
      final lock = LockService(MemorySecretStore(), now: () => t);
      await lock.setPin('2580');
      lock.onPaused();
      t = t.add(const Duration(minutes: 2));
      lock.onResumed();
      expect(lock.unlocked, isTrue);
      lock.onPaused();
      t = t.add(const Duration(minutes: 6));
      lock.onResumed();
      expect(lock.unlocked, isFalse);
    });

    test('la clé de la base est créée une fois puis réutilisée', () async {
      final store = MemorySecretStore();
      final k1 = await databaseKey(store);
      expect(k1.length, greaterThan(40));
      expect(await databaseKey(store), k1);
    });
  });

  test('format FCFA', () {
    expect(fcfa(13303850), '13.303.850 FCFA');
    expect(fcfa(500), '500 FCFA');
    expect(fcfa(45000, hidden: true), '•••••• FCFA');
    expect(spokenFcfa(45000), '45 000 francs');
  });

  testWidgets('premier lancement : choix du code puis accueil', (tester) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    final repo = Repository(db);
    await tester.runAsync(
      () => repo.addProduct(
        name: 'Riz 25 kg',
        unit: 'sacs',
        price: 15000,
        alertMin: 5,
        initialQty: 3,
      ),
    );

    await tester.pumpWidget(
      GereMieuxApp(
        repo: repo,
        shop: ShopRepository(ShopDatabase(NativeDatabase.memory()), repo),
        lock: LockService(MemorySecretStore()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Choisissez un code à 4 chiffres'), findsOneWidget);

    Future<void> typePin() async {
      for (final d in ['1', '2', '3', '4']) {
        await tester.tap(find.text(d));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
      }
    }

    await typePin();
    expect(find.text('Tapez le même code une 2e fois'), findsOneWidget);
    await typePin();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ma boutique'), findsOneWidget);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await tester.pumpAndSettle();
    expect(find.text('1 article bientôt en rupture'), findsOneWidget);

    // Le bouton œil masque les montants.
    expect(find.text('0 FCFA'), findsWidgets);
    await tester.tap(find.byTooltip('Masquer les montants'));
    await tester.pumpAndSettle();
    expect(find.text('0 FCFA'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(db.close);
  });
}
