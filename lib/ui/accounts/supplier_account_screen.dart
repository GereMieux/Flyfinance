import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/accounts_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';
import 'purchase_screen.dart';

/// Compte d'un fournisseur : achats, versements, moyens de paiement et dates,
/// et ce que l'on doit encore.
class SupplierAccountScreen extends StatelessWidget {
  const SupplierAccountScreen(this.supplierId, {super.key});
  final int supplierId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compte fournisseur'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: EyeButton()),
        ],
      ),
      body: Loader<SupplierAccount>(
        load: (r) => r.supplierAccount(supplierId),
        builder: (context, a) {
          final owe = a.balance > 0;
          final ahead = a.balance < 0;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              ContactHeader(
                a.contact,
                onEdit: () async {
                  if (await editContact(
                        context,
                        kind: 'fournisseur',
                        contact: a.contact,
                      ) !=
                      null) {
                    app.changed();
                  }
                },
              ),
              const SizedBox(height: 12),
              Panel(
                color: owe ? Palette.redSoft : Palette.hero,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      owe
                          ? 'Je lui dois'
                          : ahead
                          ? 'Avance chez lui'
                          : 'Compte à jour',
                      style: TextStyle(color: owe ? Palette.red : Palette.mint),
                    ),
                    FittedBox(
                      child: Text(
                        app.money(a.balance.abs()),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        statChip('Acheté', app.money(a.bought), Palette.text),
                        const SizedBox(width: 8),
                        statChip('Versé', app.money(a.paid), Palette.mint),
                        const SizedBox(width: 8),
                        statChip(
                          'Achats',
                          '${a.purchases.where((p) => !p.purchase.cancelled).length}',
                          Palette.text,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PurchaseScreen(a.contact),
                        ),
                      ),
                      icon: const Icon(Icons.add_shopping_cart),
                      label: const Text('Nouvel achat'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(48, 54),
                      ),
                      onPressed: () => _pay(context, app, a),
                      icon: const Icon(Icons.payments_outlined),
                      label: const Text('Versement'),
                    ),
                  ),
                ],
              ),
              sectionTitle('Mouvements (${a.moves.length})'),
              Panel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                child: a.moves.isEmpty
                    ? const EmptyState(
                        'Aucun achat ni versement.\nTouchez « Nouvel achat » à chaque arrivage.',
                      )
                    : Column(
                        children: [
                          for (final m in a.moves)
                            MoveTile(
                              m,
                              onTap: m.purchase != null
                                  ? () => _purchase(context, app, m.purchase!)
                                  : m.cancelled
                                  ? null
                                  : () => _cancelEntry(context, app, m),
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

  Future<void> _pay(
    BuildContext context,
    AppState app,
    SupplierAccount a,
  ) async {
    final v = await askMoney(
      context,
      title: 'Versement à ${a.contact.name}',
      action: 'Enregistrer',
      initial: a.balance > 0 ? a.balance : null,
    );
    if (v == null) return;
    await app.repo.paySupplier(
      supplierId,
      v.amount,
      method: v.method,
      at: v.at,
      note: v.note,
    );
    app.changed();
    if (context.mounted) toast(context, '${fcfa(v.amount)} versés.');
  }

  Future<void> _purchase(
    BuildContext context,
    AppState app,
    PurchaseSummary s,
  ) async {
    final p = s.purchase;
    final cancel = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Palette.card,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Achat du ${shortDate(p.createdAt)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                [
                  if (p.reference != null) 'N° ${p.reference}',
                  s.status.label,
                  if (s.due > 0) 'reste ${app.money(s.due)}',
                ].join(' · '),
                style: TextStyle(color: Palette.muted),
              ),
              if (p.note != null) ...[const SizedBox(height: 6), Text(p.note!)],
              const SizedBox(height: 12),
              for (final l in s.lines)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l.productId == null
                              ? l.label
                              : '${l.qty} × ${l.label}',
                        ),
                      ),
                      Text(
                        app.money(l.qty * l.unitCost),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              Divider(color: Palette.line),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Total',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    app.money(p.total),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              if (!p.cancelled) ...[
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Palette.red,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  icon: const Icon(Icons.block, size: 18),
                  label: const Text('Annuler cet achat'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
    if (cancel != true || !context.mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Annuler cet achat ?'),
        content: const Text(
          'Les articles ressortent du stock. Les versements restent comptés '
          'comme avance chez le fournisseur.',
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
    if (ok != true) return;
    try {
      await app.repo.cancelPurchase(p.id);
      app.changed();
    } on StateError catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  Future<void> _cancelEntry(
    BuildContext context,
    AppState app,
    AccountMove m,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Annuler ce versement ?'),
        content: Text(
          '${fcfa(m.amount)} du ${shortDate(m.at)} (${m.detail}). '
          'Il reste visible, barré.',
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
    if (ok != true) return;
    await app.repo.cancelEntry(m.entry!.id);
    app.changed();
  }
}
