import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/database.dart';
import '../data/repository.dart';
import 'theme.dart';
import 'widgets.dart';

class _SaleData {
  _SaleData(this.stock, this.clients);
  final List<ProductStock> stock;
  final List<Contact> clients;
}

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});
  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final _qty = <int, int>{};
  final _search = TextEditingController();
  bool _wholesale = false;
  int? _clientId;
  String? _newClient;
  String _payMode = 'tout';
  int _customPaid = 0;
  String _method = 'especes';
  bool _saving = false;

  int _price(Product p) => _wholesale ? (p.wholesalePrice ?? p.price) : p.price;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Loader<_SaleData>(
      load: (r) async =>
          _SaleData(await r.stock(), await r.contacts(kind: 'client')),
      builder: (context, d) {
        final q = normalize(_search.text);
        final items = d.stock
            .where((s) => normalize(s.product.name).contains(q))
            .toList();
        final total = d.stock.fold<int>(
          0,
          (a, s) => a + (_qty[s.product.id] ?? 0) * _price(s.product),
        );
        final paid = switch (_payMode) {
          'tout' => total,
          'moitie' => total ~/ 2,
          'rien' => 0,
          _ => _customPaid.clamp(0, total),
        };
        return Scaffold(
          appBar: AppBar(
            title: const Text('Vendre'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilterChip(
                  label: const Text('Prix de gros'),
                  selected: _wholesale,
                  onSelected: (v) => setState(() => _wholesale = v),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Chercher un article',
                  ),
                ),
              ),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(
                        'Aucun article. Ajoutez vos articles dans le Stock.',
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final s = items[i];
                          final n = _qty[s.product.id] ?? 0;
                          return Panel(
                            padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.product.name,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        '${fcfa(_price(s.product))} · ${s.qty} en stock',
                                        style: TextStyle(
                                          color: s.low
                                              ? Palette.red
                                              : Palette.muted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton.outlined(
                                  tooltip: 'Retirer un',
                                  onPressed: n == 0
                                      ? null
                                      : () => setState(
                                          () => _qty[s.product.id] = n - 1,
                                        ),
                                  icon: const Icon(Icons.remove),
                                ),
                                SizedBox(
                                  width: 32,
                                  child: Text(
                                    '$n',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                IconButton.filled(
                                  tooltip: 'Ajouter un',
                                  style: IconButton.styleFrom(
                                    backgroundColor: Palette.green,
                                  ),
                                  onPressed: n >= s.qty
                                      ? null
                                      : () => setState(
                                          () => _qty[s.product.id] = n + 1,
                                        ),
                                  icon: const Icon(
                                    Icons.add,
                                    color: Palette.text,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              if (total > 0) _checkout(app, d, total, paid),
            ],
          ),
        );
      },
    );
  }

  Widget _checkout(AppState app, _SaleData d, int total, int paid) {
    final credit = paid < total;
    final needsClient = credit && _clientId == null && _newClient == null;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: const BoxDecoration(
        color: Palette.card,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  'Total',
                  style: TextStyle(color: Palette.muted, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  fcfa(total),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              initialValue: _clientId,
              isExpanded: true,
              dropdownColor: Palette.cardHigh,
              decoration: InputDecoration(
                labelText: _newClient == null
                    ? 'Client'
                    : 'Nouveau client : $_newClient',
                prefixIcon: const Icon(Icons.person_outline),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('Client comptoir'),
                ),
                for (final c in d.clients)
                  DropdownMenuItem(value: c.id, child: Text(c.name)),
                const DropdownMenuItem(
                  value: -1,
                  child: Text('+ Nouveau client'),
                ),
              ],
              onChanged: (v) async {
                if (v == -1) {
                  final name = await _askName();
                  setState(() {
                    _clientId = null;
                    _newClient = (name == null || name.trim().isEmpty)
                        ? null
                        : name.trim();
                  });
                } else {
                  setState(() {
                    _clientId = v;
                    _newClient = null;
                  });
                }
              },
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [
                  ('tout', 'Tout payé'),
                  ('moitie', 'Moitié'),
                  ('rien', 'À crédit'),
                  ('autre', 'Autre montant'),
                ])
                  ChoiceChip(
                    label: Text(m.$2),
                    selected: _payMode == m.$1,
                    onSelected: (_) async {
                      if (m.$1 == 'autre') {
                        final v = await askNumber(
                          context,
                          title: 'Montant payé maintenant',
                        );
                        if (v == null) return;
                        _customPaid = v;
                      }
                      setState(() => _payMode = m.$1);
                    },
                  ),
              ],
            ),
            if (paid > 0) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final e in paymentMethods.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: _method == e.key,
                          onSelected: (_) => setState(() => _method = e.key),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (credit)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  needsClient
                      ? 'Choisissez le client pour une vente à crédit.'
                      : 'Reste à payer : ${fcfa(total - paid)}',
                  style: TextStyle(
                    color: needsClient ? Palette.red : Palette.amber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: needsClient || _saving
                    ? null
                    : () => _save(app, d, paid),
                child: Text(_saving ? 'Enregistrement…' : 'Valider la vente'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askName() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Nom du client'),
        content: TextField(controller: c, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _save(AppState app, _SaleData d, int paid) async {
    setState(() => _saving = true);
    try {
      final contactId =
          _clientId ??
          (_newClient == null ? null : await app.repo.addContact(_newClient!));
      await app.repo.recordSale(
        lines: [
          for (final s in d.stock)
            if ((_qty[s.product.id] ?? 0) > 0)
              CartLine(
                s.product,
                _qty[s.product.id]!,
                unitPrice: _price(s.product),
              ),
        ],
        contactId: contactId,
        paidNow: paid,
        method: _method,
      );
      app.changed();
      if (!mounted) return;
      toast(context, 'Vente enregistrée.');
      Navigator.pop(context);
    } catch (e) {
      if (mounted)
        toast(context, e.toString().replaceFirst(RegExp(r'^\w+Error: '), ''));
      setState(() => _saving = false);
    }
  }
}
