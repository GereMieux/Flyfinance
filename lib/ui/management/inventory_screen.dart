import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/database.dart';
import '../../data/management_repository.dart';
import '../../data/repository.dart';
import '../accounts/common.dart';
import '../services/common.dart' show guarded;
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

/// Inventaire : on compte les articles en rayon et l'application corrige
/// son stock, en montrant ce qui manque.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _counted = <int, TextEditingController>{};
  String _query = '';

  Map<int, int> get _values => {
    for (final e in _counted.entries)
      if (int.tryParse(e.value.text.trim()) != null)
        e.key: int.parse(e.value.text.trim()),
  };

  @override
  Widget build(BuildContext context) {
    final n = _values.length;
    return Scaffold(
      appBar: AppBar(title: const Text('Inventaire')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: n == 0 ? null : _review,
            child: Text(
              n == 0
                  ? 'Tapez au moins une quantité'
                  : 'Voir les écarts ($n compté${n > 1 ? 's' : ''})',
            ),
          ),
        ),
      ),
      body: Loader<(List<ProductStock>, List<Inventory>)>(
        load: (r) async => (await r.stock(), await r.inventories()),
        builder: (context, d) {
          final q = normalize(_query);
          final list = d.$1
              .where((s) => q.isEmpty || normalize(s.product.name).contains(q))
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(
                'Comptez vos articles et tapez la quantité réelle. Laissez '
                'vide ce que vous ne comptez pas.',
                style: TextStyle(color: Palette.muted),
              ),
              const SizedBox(height: 10),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Chercher un article',
                  prefixIcon: Icon(Icons.search),
                ),
              ),
              const SizedBox(height: 10),
              Panel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                child: Column(
                  children: [
                    for (final s in list)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    s.product.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  Text(
                                    'Dans l’application : ${s.qty} ${s.product.unit}',
                                    style: TextStyle(
                                      color: Palette.muted,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: _counted.putIfAbsent(
                                  s.product.id,
                                  TextEditingController.new,
                                ),
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                onChanged: (_) => setState(() {}),
                                decoration: InputDecoration(
                                  hintText: '${s.qty}',
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (d.$2.isNotEmpty) ...[
                sectionTitle('Derniers inventaires'),
                for (final i in d.$2) _past(i),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _past(Inventory i) {
    final app = context.watch<AppState>();
    final lines = i.lines.isEmpty ? <String>[] : i.lines.split('\n');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    shortDate(i.createdAt),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  i.missingValue > 0
                      ? '−${app.money(i.missingValue)}'
                      : 'Stock juste',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: i.missingValue > 0 ? Palette.red : Palette.mint,
                  ),
                ),
              ],
            ),
            Text(
              '${i.counted} compté${i.counted > 1 ? 's' : ''} · '
              '${lines.length} écart${lines.length > 1 ? 's' : ''}',
              style: TextStyle(color: Palette.muted),
            ),
            for (final l in lines.take(6))
              Builder(
                builder: (_) {
                  final p = l.split('|');
                  return Text(
                    '${p[0]} : ${p[1]} → ${p[2]}',
                    style: const TextStyle(fontSize: 13),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _review() async {
    final app = context.read<AppState>();
    final values = _values;
    final gaps = await app.repo.inventoryGaps(values);
    if (!mounted) return;
    final missing = -gaps
        .where((g) => g.value < 0)
        .fold<int>(0, (s, g) => s + g.value);
    var asExpense = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: Palette.card,
          title: const Text('Écarts d’inventaire'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${values.length} compté${values.length > 1 ? 's' : ''} · '
                  '${gaps.length} écart${gaps.length > 1 ? 's' : ''}',
                ),
                const SizedBox(height: 8),
                if (gaps.isEmpty)
                  Text(
                    '✓ Aucun écart : votre stock est juste.',
                    style: TextStyle(
                      color: Palette.mint,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                for (final g in gaps)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${g.product.name}\n${g.before} → ${g.after}',
                          ),
                        ),
                        Text(
                          '${g.gap > 0 ? '+' : ''}${g.gap}\n${app.money(g.value)}',
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: g.gap < 0 ? Palette.red : Palette.mint,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (missing > 0) ...[
                  const Divider(),
                  AmountLine(
                    'Manquant (prix d’achat)',
                    missing,
                    strong: true,
                    color: Palette.red,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: asExpense,
                    onChanged: (v) => set(() => asExpense = v!),
                    title: const Text(
                      'Compter le manquant dans les dépenses (pertes)',
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Retour au comptage'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (!await askOwnerPin(
      context,
      title: 'Valider l’inventaire',
      text: 'Le stock de l’application prendra les quantités comptées.',
    )) {
      return;
    }
    if (!mounted) return;
    await guarded(
      context,
      () => app.repo.applyInventory(values, lossAsExpense: asExpense),
    );
    if (!mounted) return;
    for (final c in _counted.values) {
      c.clear();
    }
    setState(() {});
    toast(
      context,
      gaps.isEmpty
          ? 'Inventaire validé : stock juste'
          : 'Inventaire validé : ${gaps.length} correction${gaps.length > 1 ? 's' : ''}',
    );
  }
}
