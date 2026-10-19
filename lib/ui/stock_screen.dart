import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import 'theme.dart';
import 'widgets.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({
    super.key,
    this.onlyLow = false,
    this.purchaseMode = false,
    this.embedded = false,
  });
  final bool onlyLow;

  /// Ouvert depuis « Acheter » : toucher un article enregistre une entrée.
  final bool purchaseMode;

  /// Affiché comme onglet (sans bouton retour).
  final bool embedded;

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  late bool _onlyLow = widget.onlyLow;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(
          widget.purchaseMode ? 'Acheter (entrée en stock)' : 'Stock',
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(minimumSize: const Size(48, 44)),
              onPressed: () => _addProduct(app),
              icon: const Icon(Icons.add),
              label: const Text('Article'),
            ),
          ),
        ],
      ),
      body: Loader<List<ProductStock>>(
        load: (r) => r.stock(),
        builder: (context, all) {
          final low = all.where((s) => s.low).length;
          final list = _onlyLow ? all.where((s) => s.low).toList() : all;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              if (widget.purchaseMode)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Touchez l’article reçu du fournisseur.',
                    style: TextStyle(color: Palette.muted),
                  ),
                ),
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text('Tous (${all.length})'),
                    selected: !_onlyLow,
                    onSelected: (_) => setState(() => _onlyLow = false),
                  ),
                  ChoiceChip(
                    label: Text('À commander ($low)'),
                    selected: _onlyLow,
                    onSelected: (_) => setState(() => _onlyLow = true),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                EmptyState(
                  _onlyLow
                      ? 'Rien à commander pour l’instant.'
                      : 'Aucun article. Touchez « + Article » pour commencer.',
                  icon: Icons.inventory_2_outlined,
                ),
              for (final s in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Material(
                    color: Palette.card,
                    borderRadius: BorderRadius.circular(16),
                    child: ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      onTap: () =>
                          widget.purchaseMode ? _entry(app, s) : _moves(app, s),
                      title: Text(
                        s.product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        '${fcfa(s.product.price)} · alerte sous ${s.product.alertMin + 1} ${s.product.unit}',
                        style: TextStyle(color: Palette.muted),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${s.qty} ${s.product.unit}',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            s.low ? 'Bientôt en rupture' : 'Suffisant',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: s.low ? Palette.red : Palette.mint,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _entry(AppState app, ProductStock s) async {
    final n = await askNumber(
      context,
      title: 'Combien de ${s.product.unit} reçus ?',
      hint: s.product.name,
    );
    if (n == null || n <= 0) return;
    await app.repo.adjustStock(s.product.id, n, 'achat');
    app.changed();
    if (mounted) toast(context, '$n ${s.product.unit} ajoutés.');
  }

  Future<void> _moves(AppState app, ProductStock s) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Palette.card,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                s.product.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: Text('${s.qty} ${s.product.unit} en stock'),
            ),
            ListTile(
              leading: Icon(Icons.add_box_outlined, color: Palette.mint),
              title: const Text('Entrée en stock (achat)'),
              onTap: () => Navigator.pop(ctx, 'achat'),
            ),
            ListTile(
              leading: Icon(
                Icons.indeterminate_check_box_outlined,
                color: Palette.red,
              ),
              title: const Text('Sortie (perte, casse, usage)'),
              onTap: () => Navigator.pop(ctx, 'perte'),
            ),
            ListTile(
              leading: Icon(Icons.fact_check_outlined, color: Palette.amber),
              title: const Text('Inventaire : corriger la quantité comptée'),
              onTap: () => Navigator.pop(ctx, 'inventaire'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (choice == 'achat') return _entry(app, s);
    final n = await askNumber(
      context,
      title: choice == 'perte'
          ? 'Combien sortent du stock ?'
          : 'Quantité comptée',
      initial: choice == 'inventaire' ? s.qty : null,
    );
    if (n == null) return;
    final delta = choice == 'perte' ? -n.clamp(0, s.qty) : n - s.qty;
    if (delta == 0) return;
    await app.repo.adjustStock(s.product.id, delta, choice);
    app.changed();
  }

  Future<void> _addProduct(AppState app) async {
    final name = TextEditingController();
    final price = TextEditingController();
    final wholesale = TextEditingController();
    final cost = TextEditingController();
    final unit = TextEditingController(text: 'pièces');
    final qty = TextEditingController();
    final alert = TextEditingController(text: '5');
    int? n(TextEditingController c) =>
        int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), ''));
    Widget field(TextEditingController c, String label, {bool number = true}) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextField(
            controller: c,
            keyboardType: number ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(labelText: label),
          ),
        );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Nouvel article'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field(name, 'Nom (ex. Riz 25 kg)', number: false),
              field(price, 'Prix de vente (FCFA)'),
              field(wholesale, 'Prix de gros (facultatif)'),
              field(cost, "Prix d'achat (pour le bénéfice)"),
              field(unit, 'Unité (sacs, bidons, pièces…)', number: false),
              field(qty, 'Quantité en stock aujourd’hui'),
              field(alert, 'Alerter quand il en reste'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty || n(price) == null) return;
    await app.repo.addProduct(
      name: name.text,
      price: n(price)!,
      wholesalePrice: n(wholesale),
      cost: n(cost) ?? 0,
      unit: unit.text.trim().isEmpty ? 'pièces' : unit.text.trim(),
      initialQty: n(qty) ?? 0,
      alertMin: n(alert) ?? 0,
    );
    app.changed();
  }
}

class ProductStatsScreen extends StatelessWidget {
  const ProductStatsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiques des produits'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: EyeButton()),
        ],
      ),
      body: Loader<List<ProductSales>>(
        load: (r) => r.productStats(),
        builder: (context, list) {
          final max = list.fold<int>(
            1,
            (m, s) => s.revenue > m ? s.revenue : m,
          );
          if (list.every((s) => s.qty == 0)) {
            return const EmptyState(
              'Les statistiques apparaîtront après vos premières ventes.',
              icon: Icons.bar_chart_rounded,
            );
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final s in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              s.product.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            app.money(s.revenue),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: s.revenue / max,
                          minHeight: 10,
                          color: Palette.amber,
                          backgroundColor: Palette.cardHigh,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${s.qty} ${s.product.unit} vendus · marge ${app.money(s.margin)}',
                        style: TextStyle(color: Palette.muted, fontSize: 13),
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
