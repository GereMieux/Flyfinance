import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/accounts_repository.dart';
import '../../data/database.dart';
import '../../data/management_repository.dart';
import '../accounts/common.dart';
import '../services/common.dart' show guarded;
import '../theme.dart';
import '../widgets.dart';

/// Ce qu'il reste à verser aux fournisseurs, par date, comparé à l'argent
/// en caisse.
class PaymentPlanScreen extends StatelessWidget {
  const PaymentPlanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final today = app.repo.now();
    final week = DateTime(today.year, today.month, today.day + 7);
    return Scaffold(
      appBar: AppBar(title: const Text('Plan de versements')),
      body: Loader<(List<PlanRow>, int)>(
        load: (r) async => (await r.paymentPlan(), await r.cashBalance()),
        builder: (context, d) {
          final rows = d.$1;
          final soon = rows
              .where((r) => r.kind != 'attente' && r.date.isBefore(week))
              .fold<int>(0, (s, r) => s + r.amount);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Panel(
                color: soon == 0 || d.$2 >= soon
                    ? Palette.mintSoft
                    : Palette.redSoft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('À verser d’ici 7 jours'),
                    Text(
                      app.money(soon),
                      style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabular,
                      ),
                    ),
                    if (soon > 0)
                      Text(
                        d.$2 >= soon
                            ? 'Votre caisse (${app.money(d.$2)}) couvre ces versements.'
                            : 'Votre caisse (${app.money(d.$2)}) ne couvre pas '
                                  'tout : il manque ${app.money(soon - d.$2)}. '
                                  'Payez d’abord les lignes en retard.',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: d.$2 >= soon ? Palette.mint : Palette.red,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (rows.isEmpty)
                const EmptyState(
                  'Aucun versement à prévoir. Quand vous achetez à crédit, '
                  'indiquez la date limite ou « au fil des ventes » : le plan '
                  'se remplit tout seul.',
                  icon: Icons.event_available_outlined,
                ),
              for (final r in rows) _row(context, app, r, today),
            ],
          );
        },
      ),
    );
  }

  Widget _row(BuildContext context, AppState app, PlanRow r, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final (label, color) = switch (r.kind) {
      'attente' => ('Selon les ventes', Palette.muted),
      'ventes' => ('Dû sur les ventes', Palette.amber),
      _ when r.date.isBefore(today) => ('En retard', Palette.red),
      _ when r.date.isBefore(today.add(const Duration(days: 7))) => (
        'Cette semaine',
        Palette.amber,
      ),
      _ => ('À venir', Palette.mint),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.supplier.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  app.money(r.amount),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    fontFeatures: tabular,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  r.kind == 'ventes' ? 'Maintenant' : 'Le ${dayOnly(r.date)}',
                  style: TextStyle(color: Palette.muted),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'Achat du ${dayOnly(r.purchase.createdAt)} · ${r.info}',
              style: TextStyle(color: Palette.muted, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => editTerms(context, r.purchase),
                  child: const Text('Conditions'),
                ),
                if (r.kind != 'attente')
                  FilledButton(
                    onPressed: () async {
                      final m = await askMoney(
                        context,
                        title: 'Verser à ${r.supplier.name}',
                        action: 'Verser',
                        initial: r.amount,
                      );
                      if (m == null || !context.mounted) return;
                      await guarded(
                        context,
                        () => app.repo.paySupplier(
                          r.supplier.id,
                          m.amount,
                          method: m.method,
                          at: m.at,
                          note: m.note,
                        ),
                      );
                    },
                    child: const Text('Verser'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Conditions de paiement d'un achat à crédit : date limite, ou au fil des
/// ventes.
Future<void> editTerms(BuildContext context, Purchase p) async {
  final repo = context.read<AppState>().repo;
  var terms = p.terms;
  var due = p.dueDate ?? p.createdAt.add(const Duration(days: 30));
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Conditions avec le fournisseur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RadioGroup<String>(
              groupValue: terms,
              onChanged: (v) => set(() => terms = v!),
              child: const Column(
                children: [
                  RadioListTile(
                    contentPadding: EdgeInsets.zero,
                    value: 'date',
                    title: Text('À une date limite'),
                  ),
                  RadioListTile(
                    contentPadding: EdgeInsets.zero,
                    value: 'ventes',
                    title: Text('Au fil des ventes'),
                  ),
                ],
              ),
            ),
            Text(
              terms == 'ventes'
                  ? 'Vous versez la valeur d’achat de ce qui est vendu. '
                        'L’application calcule le montant chaque jour.'
                  : 'Le reste est à payer à cette date.',
              style: TextStyle(color: Palette.muted, fontSize: 13),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_outlined, size: 18),
              label: Text(
                '${terms == 'ventes' ? 'Tout payer au plus tard le' : 'Date limite :'} ${dayOnly(due)}',
              ),
              onPressed: () async {
                final d = await showDatePicker(
                  context: ctx,
                  initialDate: due,
                  firstDate: DateTime(due.year - 1),
                  lastDate: DateTime(due.year + 3),
                );
                if (d != null) set(() => due = d);
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || !context.mounted) return;
  await guarded(
    context,
    () => repo.setPurchaseTerms(p.id, terms: terms, dueDate: due),
  );
  if (context.mounted) toast(context, 'Conditions enregistrées');
}
