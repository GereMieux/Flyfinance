import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/accounts_repository.dart';
import '../../data/database.dart';
import '../../data/repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'broadcast_screen.dart';
import 'common.dart';

enum _Pay { tout, rien, autre }

/// Nouvel achat chez un fournisseur (un arrivage) : les articles entrent en
/// stock et le compte du fournisseur est mis à jour.
class PurchaseScreen extends StatefulWidget {
  const PurchaseScreen(this.supplier, {super.key});
  final Contact supplier;

  @override
  State<PurchaseScreen> createState() => _PurchaseScreenState();
}

class _PurchaseScreenState extends State<PurchaseScreen> {
  final _lines = <PurchaseLineInput>[];
  final _ref = TextEditingController();
  final _note = TextEditingController();
  final _other = TextEditingController();
  var _pay = _Pay.tout;
  var _method = 'especes';
  DateTime? _at;
  var _saving = false;

  int get _total => _lines.fold(0, (s, l) => s + l.total);
  int get _paid => switch (_pay) {
    _Pay.tout => _total,
    _Pay.rien => 0,
    _Pay.autre =>
      (int.tryParse(_other.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0).clamp(
        0,
        _total,
      ),
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final now = app.repo.now();
    return Scaffold(
      appBar: AppBar(title: Text('Achat · ${widget.supplier.name}')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          TilesPanel(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Column(
              children: [
                if (_lines.isEmpty)
                  const EmptyState(
                    'Ajoutez les articles reçus.\nIls entreront en stock.',
                    icon: Icons.inventory_2_outlined,
                  ),
                for (var i = 0; i < _lines.length; i++)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(
                      _lines[i].product == null
                          ? _lines[i].label
                          : '${_lines[i].qty} × ${_lines[i].label}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: _lines[i].product == null
                        ? Text(
                            'Dépense',
                            style: TextStyle(color: Palette.muted),
                          )
                        : Text(
                            '${fcfa(_lines[i].unitCost)} l’unité',
                            style: TextStyle(color: Palette.muted),
                          ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          fcfa(_lines[i].total),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          tooltip: 'Retirer',
                          onPressed: () => setState(() => _lines.removeAt(i)),
                          icon: const Icon(Icons.close, size: 20),
                        ),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        onPressed: () => _addProduct(app),
                        icon: const Icon(Icons.add),
                        label: const Text('Article'),
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _addExpense,
                        icon: const Icon(Icons.local_shipping_outlined),
                        label: const Text('Frais'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Panel(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Total de l’achat',
                    style: TextStyle(color: Palette.muted),
                  ),
                ),
                Text(
                  fcfa(_total),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          sectionTitle('Paiement'),
          SegmentedButton<_Pay>(
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: Palette.amber,
              selectedForegroundColor: Palette.ink,
              side: BorderSide(color: Palette.line),
            ),
            segments: const [
              ButtonSegment(value: _Pay.tout, label: Text('Tout payé')),
              ButtonSegment(value: _Pay.rien, label: Text('À crédit')),
              ButtonSegment(value: _Pay.autre, label: Text('Une partie')),
            ],
            selected: {_pay},
            onSelectionChanged: (s) => setState(() => _pay = s.first),
          ),
          if (_pay == _Pay.autre) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _other,
              keyboardType: TextInputType.number,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                hintText: 'Montant versé',
                suffixText: 'FCFA',
              ),
            ),
          ],
          if (_pay != _Pay.rien) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in accountMethods.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: _method == e.key,
                    onSelected: (_) => setState(() => _method = e.key),
                  ),
              ],
            ),
          ],
          if (_total > 0 && _paid < _total)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Reste à payer au fournisseur : ${fcfa(_total - _paid)}',
                style: TextStyle(
                  color: Palette.amber,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          sectionTitle('Détails'),
          OutlinedButton.icon(
            icon: const Icon(Icons.event_outlined, size: 18),
            label: Text(
              _at == null ? 'Reçu aujourd’hui' : 'Reçu le ${dayOnly(_at!)}',
            ),
            onPressed: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _at ?? now,
                firstDate: DateTime(now.year - 3),
                lastDate: now,
              );
              if (d == null) return;
              final today =
                  d.year == now.year &&
                  d.month == now.month &&
                  d.day == now.day;
              setState(
                () => _at = today ? null : DateTime(d.year, d.month, d.day, 12),
              );
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ref,
            decoration: const InputDecoration(
              hintText: 'N° de facture ou de bon (facultatif)',
              prefixIcon: Icon(Icons.tag),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _note,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Note (facultatif)',
              prefixIcon: Icon(Icons.notes),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(60),
            ),
            onPressed: _lines.isEmpty || _saving ? null : () => _save(app),
            icon: const Icon(Icons.check),
            label: const Text('Enregistrer l’achat'),
          ),
        ],
      ),
    );
  }

  Future<void> _addProduct(AppState app) async {
    final products = await app.repo.products();
    if (!mounted) return;
    if (products.isEmpty) {
      toast(context, 'Créez d’abord l’article dans le Stock.');
      return;
    }
    final p = await showModalBottomSheet<Product>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.ground,
      builder: (_) => _ProductPicker(products),
    );
    if (p == null || !mounted) return;
    final qty = TextEditingController();
    final cost = TextEditingController(text: p.cost > 0 ? '${p.cost}' : '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: Text(p.name),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qty,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Quantité reçue',
                suffixText: p.unit,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: cost,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Prix d’achat à l’unité',
                suffixText: 'FCFA',
              ),
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
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    final q = int.tryParse(qty.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final c = int.tryParse(cost.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (ok != true || q == null || q <= 0) return;
    setState(
      () => _lines.add(
        PurchaseLineInput(product: p, label: p.name, qty: q, unitCost: c),
      ),
    );
  }

  Future<void> _addExpense() async {
    final label = TextEditingController(text: 'Transport');
    final amount = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Frais ou autre dépense'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: label,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Libellé'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amount,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Montant',
                suffixText: 'FCFA',
              ),
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
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    final v = int.tryParse(amount.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (ok != true || v == null || v <= 0 || label.text.trim().isEmpty) return;
    setState(
      () => _lines.add(
        PurchaseLineInput(label: label.text.trim(), qty: 1, unitCost: v),
      ),
    );
  }

  Future<void> _save(AppState app) async {
    setState(() => _saving = true);
    try {
      await app.repo.recordPurchase(
        supplierId: widget.supplier.id,
        lines: _lines,
        paidNow: _paid,
        method: _method,
        at: _at,
        reference: _ref.text,
        note: _note.text,
      );
    } on ArgumentError catch (e) {
      setState(() => _saving = false);
      if (mounted) toast(context, '${e.message}');
      return;
    }
    app.changed();
    if (!mounted) return;
    final arrivals = _lines.where((l) => l.product != null).toList();
    if (arrivals.isEmpty) {
      Navigator.pop(context);
      toast(context, 'Achat enregistré.');
      return;
    }
    final announce = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Achat enregistré'),
        content: const Text(
          'Les articles sont entrés en stock. Voulez-vous annoncer cet '
          'arrivage à vos clients ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Annoncer'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (announce == true) {
      navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => BroadcastScreen(
            initialText: arrivalMessage([
              for (final l in arrivals) l.product!.name,
            ]),
          ),
        ),
      );
    } else {
      navigator.pop();
    }
  }
}

class _ProductPicker extends StatefulWidget {
  const _ProductPicker(this.all);
  final List<Product> all;
  @override
  State<_ProductPicker> createState() => _ProductPickerState();
}

class _ProductPickerState extends State<_ProductPicker> {
  final _q = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final q = normalize(_q.text);
    final list = widget.all
        .where((p) => normalize(p.name).contains(q))
        .toList();
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Article reçu',
                ),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final p in list)
                    ListTile(
                      leading: const Icon(Icons.inventory_2_outlined),
                      title: Text(p.name),
                      subtitle: Text(
                        p.cost > 0
                            ? 'Dernier prix d’achat ${fcfa(p.cost)}'
                            : p.unit,
                        style: TextStyle(color: Palette.muted),
                      ),
                      onTap: () => Navigator.pop(context, p),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
