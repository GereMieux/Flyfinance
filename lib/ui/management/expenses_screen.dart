import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/database.dart';
import '../../data/management_repository.dart';
import '../accounts/common.dart';
import '../services/common.dart' show guarded, confirm;
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

/// Dépenses de la boutique : loyer, électricité, transport… Elles sont
/// retirées du bénéfice pour donner le bénéfice net.
class ExpensesScreen extends StatelessWidget {
  const ExpensesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = app.repo.now();
    final month = DateTime(t.year, t.month);
    return Scaffold(
      appBar: AppBar(title: const Text('Dépenses')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => editExpense(context),
        icon: const Icon(Icons.add),
        label: const Text('Dépense'),
      ),
      body: Loader<List<Expense>>(
        load: (r) => r.expenses(),
        builder: (context, list) {
          final cats = <String, int>{};
          for (final e in list.where((e) => !e.createdAt.isBefore(month))) {
            cats[e.category] = (cats[e.category] ?? 0) + e.amount;
          }
          final total = cats.values.fold<int>(0, (s, v) => s + v);
          final sorted = cats.entries.toList()
            ..sort((a, b) => b.value.compareTo(a.value));
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              Panel(
                color: Palette.redSoft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dépenses de ${monthLabel(month)}',
                      style: TextStyle(color: Palette.red),
                    ),
                    Text(
                      app.money(total),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabular,
                      ),
                    ),
                    const SizedBox(height: 10),
                    for (final e in sorted)
                      BarRow(
                        label: e.key,
                        value: e.value,
                        max: total,
                        color: Palette.red,
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const EmptyState(
                  'Notez ici le loyer, l’électricité, le transport… pour '
                  'connaître votre vrai bénéfice.',
                  icon: Icons.payments_outlined,
                ),
              if (list.isNotEmpty)
                TilesPanel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final e in list)
                        ListTile(
                          title: Text(
                            e.label,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${dayOnly(e.createdAt)} · ${e.category}',
                          ),
                          trailing: Text(
                            app.money(e.amount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontFeatures: tabular,
                            ),
                          ),
                          onTap: () => editExpense(context, expense: e),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

/// Ajoute ou modifie une dépense.
Future<void> editExpense(BuildContext context, {Expense? expense}) async {
  final repo = context.read<AppState>().repo;
  final label = TextEditingController(text: expense?.label ?? '');
  final amount = TextEditingController(
    text: expense == null ? '' : '${expense.amount}',
  );
  var category = expense?.category ?? expenseCategories.first;
  var at = expense?.createdAt ?? repo.now();
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        backgroundColor: Palette.card,
        title: Text(expense == null ? 'Nouvelle dépense' : 'Modifier'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: label,
                autofocus: expense == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Libellé',
                  hintText: 'ex. Facture d’électricité',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: amount,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Montant',
                  suffixText: 'FCFA',
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in expenseCategories)
                    ChoiceChip(
                      label: Text(c),
                      selected: category == c,
                      onSelected: (_) => set(() => category = c),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_outlined, size: 18),
                label: Text('Le ${dayOnly(at)}'),
                onPressed: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: at,
                    firstDate: DateTime(at.year - 3),
                    lastDate: repo.now(),
                  );
                  if (d != null) {
                    set(() => at = DateTime(d.year, d.month, d.day, 12));
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          if (expense != null)
            TextButton(
              style: TextButton.styleFrom(foregroundColor: Palette.red),
              onPressed: () => Navigator.pop(ctx, 'delete'),
              child: const Text('Supprimer'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
  if (res == null || !context.mounted) return;
  if (res == 'delete') {
    if (!await confirm(context, 'Supprimer ?', 'Supprimer cette dépense ?')) {
      return;
    }
    if (!context.mounted) return;
    await guarded(context, () => repo.deleteExpense(expense!.id));
    if (context.mounted) toast(context, 'Dépense supprimée');
    return;
  }
  final v = parseAmount(amount.text) ?? 0;
  final ok = await guarded(context, () async {
    if (expense == null) {
      await repo.addExpense(
        label: label.text,
        amount: v,
        category: category,
        at: at,
      );
    } else {
      if (label.text.trim().isEmpty || v <= 0) {
        throw ArgumentError('Indiquez un libellé et un montant.');
      }
      await repo.updateExpense(
        expense.id,
        label: label.text,
        amount: v,
        category: category,
        at: at,
      );
    }
    return true;
  });
  if (ok == true && context.mounted) toast(context, 'Dépense enregistrée');
}
