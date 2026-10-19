import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/database.dart';
import '../../data/services_repository.dart';
import '../../services/doc_pdf.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';
import 'doc_detail_screen.dart';

/// Création ou modification d'un devis ou d'une facture.
class DocEditorScreen extends StatefulWidget {
  const DocEditorScreen({super.key, required this.kind, this.existing});
  final DocKind kind;
  final DocSummary? existing;

  @override
  State<DocEditorScreen> createState() => _DocEditorScreenState();
}

class _DocEditorScreenState extends State<DocEditorScreen> {
  Contact? _client;
  final _lines = <DocLineInput>[];
  int _discount = 0;
  bool _tax = false;
  DateTime? _dueAt;
  final _note = TextEditingController();
  bool _saving = false;

  bool get _quote => widget.kind == DocKind.devis;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _client = e.contact;
      _lines.addAll([
        for (final l in e.lines)
          DocLineInput(
            label: l.label,
            qty: l.qty,
            unit: l.unit,
            unitPrice: l.unitPrice,
            serviceId: l.serviceId,
          ),
      ]);
      _discount = e.doc.discount;
      _tax = e.doc.taxRate > 0;
      _dueAt = e.doc.dueAt;
      _note.text = e.doc.note ?? '';
    } else {
      final now = context.read<AppState>().repo.now();
      // Habitude courante : devis valable 30 jours, facture payable à 15 jours.
      _dueAt = DateTime(now.year, now.month, now.day + (_quote ? 30 : 15));
    }
  }

  DocTotals get _totals =>
      DocTotals.of(_lines, _discount, _tax ? standardTaxRate : 0);

  Future<void> _addFromCatalogue() async {
    final app = context.read<AppState>();
    final list = await app.repo.services();
    if (!mounted) return;
    // Catalogue vide : on va droit à la saisie, sans étape en plus.
    final picked = list.isEmpty
        ? 'libre'
        : await showModalBottomSheet<Object>(
            context: context,
            backgroundColor: Palette.ground,
            isScrollControlled: true,
            builder: (ctx) => SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.6,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  ListTile(
                    leading: Icon(Icons.edit_note, color: Palette.mint),
                    title: Text(
                      'Écrire un autre travail',
                      style: TextStyle(
                        color: Palette.mint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, 'libre'),
                  ),
                  if (list.isEmpty)
                    const EmptyState(
                      'Votre catalogue est vide. Ajoutez vos prestations depuis '
                      '« Mes prestations » pour les retrouver ici.',
                    ),
                  for (final s in list)
                    ListTile(
                      leading: const Icon(Icons.handyman_outlined),
                      title: Text(s.name),
                      subtitle: Text('${fcfa(s.price)} / ${s.unit}'),
                      onTap: () => Navigator.pop(ctx, s),
                    ),
                ],
              ),
            ),
          );
    if (picked == null) return;
    final line = await _editLine(
      picked is Service
          ? DocLineInput(
              label: picked.name,
              qty: 1,
              unit: picked.unit,
              unitPrice: picked.price,
              serviceId: picked.id,
            )
          : null,
    );
    if (line != null) setState(() => _lines.add(line));
  }

  Future<DocLineInput?> _editLine(DocLineInput? l) {
    final label = TextEditingController(text: l?.label ?? '');
    final qty = TextEditingController(text: l == null ? '1' : qtyText(l.qty));
    final price = TextEditingController(
      text: l == null ? '' : '${l.unitPrice}',
    );
    var unit = l?.unit ?? 'forfait';
    return showDialog<DocLineInput>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: Palette.card,
          title: const Text('Travail ou produit'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: label,
                  autofocus: l == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Quoi ? (ex. Main d’œuvre)',
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: qty,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Combien ?'),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final u in {...serviceUnits, unit})
                      ChoiceChip(
                        label: Text(u),
                        selected: unit == u,
                        onSelected: (_) => set(() => unit = u),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Prix pour 1',
                    suffixText: 'FCFA',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () {
                final q = double.tryParse(qty.text.replaceAll(',', '.'));
                final p = int.tryParse(
                  price.text.replaceAll(RegExp(r'[^0-9]'), ''),
                );
                if (label.text.trim().isEmpty ||
                    q == null ||
                    q <= 0 ||
                    p == null) {
                  return;
                }
                Navigator.pop(
                  ctx,
                  DocLineInput(
                    label: label.text.trim(),
                    qty: q,
                    unit: unit,
                    unitPrice: p,
                    serviceId: l?.serviceId,
                  ),
                );
              },
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _dueAt ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 3),
    );
    if (d != null) setState(() => _dueAt = d);
  }

  Future<void> _save() async {
    if (_client == null) {
      toast(context, 'Choisissez d’abord le client.');
      return;
    }
    if (_lines.isEmpty) {
      toast(context, 'Ajoutez au moins une ligne.');
      return;
    }
    setState(() => _saving = true);
    final repo = context.read<AppState>().repo;
    final e = widget.existing;
    final id = await guarded(context, () async {
      if (e == null) {
        return repo.createDoc(
          kind: widget.kind,
          contactId: _client!.id,
          lines: _lines,
          discount: _discount,
          taxRate: _tax ? standardTaxRate : 0,
          dueAt: _dueAt,
          note: _note.text,
        );
      }
      await repo.updateDoc(
        e.doc.id,
        contactId: _client!.id,
        lines: _lines,
        discount: _discount,
        taxRate: _tax ? standardTaxRate : 0,
        dueAt: _dueAt,
        note: _note.text,
      );
      return e.doc.id;
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (id == null) return;
    if (e == null) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => DocDetailScreen(id)));
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _totals;
    final title = widget.existing == null
        ? (_quote ? 'Nouveau devis' : 'Nouvelle facture')
        : 'Modifier ${widget.existing!.doc.number}';
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          const _Label('1. Pour qui ?'),
          Material(
            color: Palette.card,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: const Icon(Icons.person_outline),
              title: Text(
                _client?.name ?? 'Choisir ou ajouter un client',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _client == null ? Palette.mint : Palette.text,
                ),
              ),
              subtitle: _client?.phone == null ? null : Text(_client!.phone!),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final c = await pickClient(context);
                if (c != null) setState(() => _client = c);
              },
            ),
          ),
          const _Label('2. Quels travaux ?'),
          for (var i = 0; i < _lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Panel(
                padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final l = await _editLine(_lines[i]);
                          if (l != null) setState(() => _lines[i] = l);
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _lines[i].label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${qtyText(_lines[i].qty)} ${_lines[i].unit} × '
                              '${fcfa(_lines[i].unitPrice)}',
                              style: TextStyle(color: Palette.muted),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Text(
                      fcfa(_lines[i].total),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    IconButton(
                      tooltip: 'Retirer',
                      onPressed: () => setState(() => _lines.removeAt(i)),
                      icon: Icon(Icons.close, color: Palette.muted),
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: _addFromCatalogue,
            icon: const Icon(Icons.add),
            label: const Text('Ajouter un travail'),
          ),
          const SizedBox(height: 12),
          // Les réglages moins courants restent repliés pour garder l'écran
          // simple ; la date est déjà remplie par défaut.
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(horizontal: 4),
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                'Plus d’options',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: const Text('Date, remise, TVA, note'),
              children: [
                TilePanel(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.event_outlined),
                        title: Text(
                          _quote ? 'Valable jusqu’au' : 'À payer avant le',
                        ),
                        trailing: Text(
                          _dueAt == null ? 'Aucune date' : dayDate(_dueAt!),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: _pickDate,
                      ),
                      ListTile(
                        leading: const Icon(Icons.local_offer_outlined),
                        title: const Text('Remise'),
                        trailing: Text(
                          _discount == 0 ? 'Aucune' : fcfa(_discount),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        onTap: () async {
                          final v = await askNumber(
                            context,
                            title: 'Remise en FCFA',
                            initial: _discount,
                          );
                          if (v != null) setState(() => _discount = v);
                        },
                      ),
                      SwitchListTile(
                        secondary: const Icon(Icons.account_balance_outlined),
                        title: const Text(
                          'Ajouter la TVA ($standardTaxRate %)',
                        ),
                        value: _tax,
                        onChanged: (v) => setState(() => _tax = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _note,
                  maxLines: 3,
                  minLines: 1,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    hintText: 'Note pour le client (facultatif)',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Panel(
            color: Palette.hero,
            child: Column(
              children: [
                if (_discount > 0 || _tax)
                  _TotalRow('Sous-total', fcfa(t.subtotal)),
                if (_discount > 0) _TotalRow('Remise', fcfa(-t.discount)),
                if (_tax) _TotalRow('TVA $standardTaxRate %', fcfa(t.tax)),
                _TotalRow(
                  _tax ? 'Total TTC' : 'Total',
                  fcfa(t.total),
                  big: true,
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              widget.existing == null
                  ? 'Enregistrer · ${fcfa(t.total)}'
                  : 'Enregistrer les changements',
            ),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
    child: Text(
      text,
      style: TextStyle(color: Palette.muted, fontWeight: FontWeight.w700),
    ),
  );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.big = false});
  final String label;
  final String value;
  final bool big;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: big ? Palette.text : Palette.muted,
              fontWeight: big ? FontWeight.w700 : null,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: big ? 22 : 15,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}
