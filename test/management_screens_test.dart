import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/app_state.dart';
import 'package:flyfinance/data/database.dart';
import 'package:flyfinance/data/management_repository.dart';
import 'package:flyfinance/data/repository.dart';
import 'package:flyfinance/ui/management/backup_screen.dart';
import 'package:flyfinance/ui/management/cash_screen.dart';
import 'package:flyfinance/ui/management/expenses_screen.dart';
import 'package:flyfinance/ui/management/inventory_screen.dart';
import 'package:flyfinance/ui/management/payment_plan_screen.dart';
import 'package:flyfinance/ui/management/reports_screen.dart';
import 'package:flyfinance/ui/management/sellers_screen.dart';
import 'package:flyfinance/ui/theme.dart';
import 'package:provider/provider.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final screens = <String, Widget>{
    'caisse': const CashScreen(),
    'clôture': const CloseCashScreen(),
    'dépenses': const ExpensesScreen(),
    'rapports': const ReportsScreen(),
    'plan de versements': const PaymentPlanScreen(),
    'inventaire': const InventoryScreen(),
    'vendeurs': const SellersScreen(),
    'sauvegarde': const BackupScreen(),
  };

  for (final e in screens.entries) {
    testWidgets('écran ${e.key} s’affiche avec des données', (tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final db = AppDatabase(NativeDatabase.memory());
      final repo = Repository(db);
      await tester.runAsync(() async {
        final id = await repo.addProduct(
          name: 'Riz',
          price: 15000,
          cost: 12000,
          initialQty: 10,
        );
        final riz = (await repo.products()).single;
        expect(riz.id, id);
        await repo.recordSale(lines: [CartLine(riz, 2)], paidNow: 30000);
        await repo.addExpense(label: 'Loyer', amount: 5000);
        await repo.addSeller('Awa', '1234');
      });
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: AppState(repo),
          child: MaterialApp(theme: buildTheme(), home: e.value),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(db.close);
    });
  }
}
