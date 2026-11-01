import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/management_repository.dart';
import '../data/repository.dart';
import 'management/common.dart';
import 'search_screen.dart';
import 'stock_screen.dart';
import 'trash_screen.dart';
import 'receipt_screen.dart';
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
    final name = s.contact?.name;
    return ListTile(
      contentPadding: EdgeInsets.symmetric(horizontal: dense ? 0 : 14),
      // Pastille avec l'initiale du client, couleur du statut de paiement.
      leading: CircleAvatar(
        radius: 21,
        backgroundColor: statusColor(s.status)
            .withValues(alpha: Palette.isDark ? 0.18 : 0.14),
        child: name == null
            ? Icon(
                Icons.person_outline_rounded,
                color: statusColor(s.status),
                size: 22,
              )
            : Text(
                name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: statusColor(s.status),
                ),
              ),
      ),
      title: Text(
        s.contact?.name ?? 'Client de passage',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        shortDate(s.sale.createdAt),
        style: TextStyle(color: Palette.muted),
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
                const PopupMenuItem(
                  value: 'receipt',
                  child: Text('Reçu ou facture'),
                ),
                if (s.due > 0 && s.contact != null)
                  const PopupMenuItem(
                    value: 'pay',
                    child: Text('Encaisser le reste'),
                  ),
                if (!cancelled)
                  const PopupMenuItem(
                    value: 'return',
                    child: Text('Retour d’article'),
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
    if (v == 'receipt') {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ReceiptScreen(saleId: s.sale.id)),
      );
    } else if (v == 'cancel') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Palette.card,
          title: const Text('Annuler cette vente ?'),
          content: const Text(
            'Le stock sera remis et la dette effacée. La vente restera visible dans la corbeille.',
          ),
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
    } else if (v == 'return') {
      await _return(context, app);
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

  /// Le client rapporte une partie de ses articles : ils reviennent en stock
  /// et on lui rend l'argent payé en trop.
  Future<void> _return(BuildContext context, AppState app) async {
    final lines = await app.repo.saleLinesOf(s.sale.id);
    if (!context.mounted) return;
    final back = {for (final l in lines) l.$1.id: TextEditingController()};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) {
          var amount = 0;
          for (final l in lines) {
            final q = int.tryParse(back[l.$1.id]!.text.trim()) ?? 0;
            amount += q * l.$1.unitPrice;
          }
          final newTotal = s.sale.total - amount;
          final refund = s.paid > newTotal ? s.paid - newTotal : 0;
          return AlertDialog(
            backgroundColor: Palette.card,
            title: const Text('Retour d’article'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Indiquez ce que le client rapporte : l’article revient '
                    'en stock.',
                    style: TextStyle(color: Palette.muted),
                  ),
                  const SizedBox(height: 8),
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${l.$2.name}\nvendu : ${l.$1.qty} × '
                              '${app.money(l.$1.unitPrice)}',
                            ),
                          ),
                          SizedBox(
                            width: 70,
                            child: TextField(
                              controller: back[l.$1.id],
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              onChanged: (_) => set(() {}),
                              decoration: const InputDecoration(
                                hintText: '0',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  AmountLine('Montant du retour', amount, strong: true),
                  if (refund > 0)
                    Text(
                      'Argent à rendre au client : ${app.money(refund)}',
                      style: TextStyle(
                        color: Palette.amber,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Fermer'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Valider le retour'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !context.mounted) return;
    if (!await askOwnerPin(
      context,
      title: 'Confirmer le retour',
      text: 'Tapez votre code secret pour valider le retour.',
    )) {
      return;
    }
    try {
      final refund = await app.repo.returnItems(s.sale.id, {
        for (final e in back.entries)
          e.key: int.tryParse(e.value.text.trim()) ?? 0,
      });
      app.changed();
      if (context.mounted) {
        toast(
          context,
          refund > 0
              ? 'Retour enregistré : rendez ${fcfa(refund)} au client'
              : 'Retour enregistré, article remis en stock',
        );
      }
    } on ArgumentError catch (e) {
      if (context.mounted) toast(context, '${e.message}', error: true);
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
                  style: TextStyle(color: Palette.text, fontSize: 17),
                ),
                trailing: Text(
                  '${st == null ? all.length : all.where((s) => s.status == st).length}',
                  style: TextStyle(color: Palette.muted),
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
                tooltip: 'Ventes annulées',
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TrashScreen()),
                ),
                icon: const Icon(Icons.delete_outline),
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
                          child: Icon(
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
                                style: TextStyle(color: Palette.muted),
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
                        statChip('Argent reçu', app.money(paid), Palette.mint),
                        const SizedBox(width: 8),
                        statChip(
                          'Reste à payer',
                          app.money(total - paid),
                          Palette.amber,
                        ),
                        const SizedBox(width: 8),
                        statChip('Ventes', '${list.length}', Palette.text),
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
                icon: Icon(Icons.bar_chart, color: Palette.amber),
                label: const Text('Statistiques des produits'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(56),
                ),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const EmptyState(
                  'Aucune vente ici.',
                  icon: Icons.receipt_long_outlined,
                ),
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
}
