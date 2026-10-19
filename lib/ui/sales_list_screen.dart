import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import 'search_screen.dart';
import 'stock_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class SaleTile extends StatelessWidget {
  const SaleTile(this.s, {super.key, this.dense = false});
  final SaleSummary s;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cancelled = s.status == SaleStatus.annulee;
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: dense ? 0 : 14),
      title: Text(
        s.contact?.name ?? 'Client comptoir',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        shortDate(s.sale.createdAt),
        style: const TextStyle(color: Palette.muted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                app.money(s.sale.total),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cancelled ? Palette.grey : Palette.text,
                  decoration: cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
              Text(
                s.status.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: statusColor(s.status),
                ),
              ),
            ],
          ),
          if (!dense)
            PopupMenuButton<String>(
              tooltip: 'Options de la vente',
              onSelected: (v) => _action(context, v),
              itemBuilder: (_) => [
                if (s.due > 0 && s.contact != null)
                  const PopupMenuItem(
                    value: 'pay',
                    child: Text('Encaisser le reste'),
                  ),
                if (!cancelled)
                  const PopupMenuItem(
                    value: 'cancel',
                    child: Text('Annuler la vente'),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _action(BuildContext context, String v) async {
    final app = context.read<AppState>();
    if (v == 'cancel') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Palette.card,
          title: const Text('Annuler cette vente ?'),
          content: const Text('Le stock sera remis et la dette effacée.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Non'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Oui, annuler'),
            ),
          ],
        ),
      );
      if (ok == true) {
        await app.repo.cancelSale(s.sale.id);
        app.changed();
      }
    } else if (v == 'pay') {
      final amount = await askNumber(
        context,
        title: 'Montant reçu de ${s.contact!.name}',
        initial: s.due,
      );
      if (amount == null || amount <= 0) return;
      final applied = await app.repo.receivePayment(s.contact!.id, amount);
      app.changed();
      if (context.mounted) toast(context, '${fcfa(applied)} encaissés.');
    }
  }
}

class SalesListScreen extends StatefulWidget {
  const SalesListScreen({super.key});
  @override
  State<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends State<SalesListScreen> {
  SaleStatus? _filter;

  Future<void> _pickFilter(List<SaleSummary> all) async {
    final picked = await showModalBottomSheet<(SaleStatus?,)>(
      context: context,
      backgroundColor: Palette.card,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Trier par statut',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
            ),
            for (final st in <SaleStatus?>[null, ...SaleStatus.values])
              ListTile(
                selected: st == _filter,
                selectedTileColor: Palette.cardHigh,
                leading: CircleAvatar(
                  radius: 5,
                  backgroundColor: st == null ? Palette.text : statusColor(st),
                ),
                title: Text(
                  st?.label ?? 'Toutes les ventes',
                  style: const TextStyle(color: Palette.text, fontSize: 17),
                ),
                trailing: Text(
                  '${st == null ? all.length : all.where((s) => s.status == st).length}',
                  style: const TextStyle(color: Palette.muted),
                ),
                onTap: () => Navigator.pop(ctx, (st,)),
              ),
          ],
        ),
      ),
    );
    if (picked != null) setState(() => _filter = picked.$1);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Loader<List<SaleSummary>>(
      load: (r) => r.sales(),
      builder: (context, all) {
        final list = _filter == null
            ? all
            : all.where((s) => s.status == _filter).toList();
        final live = list.where((s) => s.status != SaleStatus.annulee);
        final total = live.fold<int>(0, (a, s) => a + s.sale.total);
        final paid = live.fold<int>(0, (a, s) => a + s.paid);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Toutes les ventes'),
            actions: [
              IconButton(
                tooltip: 'Trier par statut',
                onPressed: () => _pickFilter(all),
                icon: const Icon(Icons.filter_list),
              ),
              IconButton(
                tooltip: 'Rechercher',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const Scaffold(body: SearchScreen()),
                  ),
                ),
                icon: const Icon(Icons.search),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Panel(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: Palette.cardHigh,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.shopping_cart_checkout,
                            color: Palette.mint,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _filter == null
                                    ? 'Toutes les ventes'
                                    : 'Ventes : ${_filter!.label}',
                                style: const TextStyle(color: Palette.muted),
                              ),
                              FittedBox(
                                child: Text(
                                  app.money(total),
                                  style: const TextStyle(
                                    fontSize: 28,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const EyeButton(),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        _chip('Encaissé', app.money(paid), Palette.mint),
                        const SizedBox(width: 8),
                        _chip(
                          'Reste à payer',
                          app.money(total - paid),
                          Palette.amber,
                        ),
                        const SizedBox(width: 8),
                        _chip('Ventes', '${list.length}', Palette.text),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ProductStatsScreen()),
                ),
                icon: const Icon(Icons.bar_chart, color: Palette.amber),
                label: const Text('Statistiques des produits'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty) const EmptyState('Aucune vente ici.'),
              for (final s in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Palette.card,
                    borderRadius: BorderRadius.circular(16),
                    child: SaleTile(s),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _chip(String label, String value, Color color) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Palette.cardHigh,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Palette.muted),
          ),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
          ),
        ],
      ),
    ),
  );
}
