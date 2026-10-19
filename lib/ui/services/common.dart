import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/database.dart';
import '../../data/repository.dart';
import '../../data/services_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'doc_detail_screen.dart';

String dayDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

Color docStatusColor(DocStatus s) => switch (s) {
  DocStatus.payee || DocStatus.accepte || DocStatus.facture => Palette.mint,
  DocStatus.partielle || DocStatus.envoye => Palette.amber,
  DocStatus.impayee || DocStatus.brouillon => Palette.blue,
  DocStatus.enRetard || DocStatus.refuse => Palette.red,
  DocStatus.expire || DocStatus.annulee => Palette.grey,
};

class StatusPill extends StatelessWidget {
  const StatusPill(this.status, {super.key});
  final DocStatus status;
  @override
  Widget build(BuildContext context) {
    final c = docStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.label,
        style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: 12),
      ),
    );
  }
}

/// Comme [Panel], mais pour des ListTile : ils ont besoin d'un Material
/// pour dessiner leur effet au toucher.
class TilePanel extends StatelessWidget {
  const TilePanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Material(
    color: Palette.card,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: child,
    ),
  );
}

/// Une ligne de liste pour un devis ou une facture.
class DocTile extends StatelessWidget {
  const DocTile(this.s, {super.key});
  final DocSummary s;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Palette.card,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => DocDetailScreen(s.doc.id))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFF1F3A2F),
                  child: Icon(
                    s.isQuote
                        ? Icons.request_quote_outlined
                        : Icons.receipt_long_outlined,
                    color: Palette.mint,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.contact.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        '${s.doc.number} · ${dayDate(s.doc.createdAt)}',
                        style: const TextStyle(
                          color: Palette.muted,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      app.money(s.due > 0 ? s.due : s.doc.total),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    StatusPill(s.status),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Choix du client : liste existante avec recherche, ou nouveau client
/// (nom et téléphone) créé sur place.
Future<Contact?> pickClient(BuildContext context) {
  final repo = context.read<AppState>().repo;
  return showModalBottomSheet<Contact>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Palette.ground,
    builder: (ctx) => _ClientPicker(repo),
  );
}

class _ClientPicker extends StatefulWidget {
  const _ClientPicker(this.repo);
  final Repository repo;
  @override
  State<_ClientPicker> createState() => _ClientPickerState();
}

class _ClientPickerState extends State<_ClientPicker> {
  final _q = TextEditingController();
  List<Contact> _all = [];

  @override
  void initState() {
    super.initState();
    widget.repo.contacts(kind: 'client').then((l) {
      if (mounted) setState(() => _all = l);
    });
  }

  Future<void> _create() async {
    final name = TextEditingController(text: _q.text.trim());
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Nouveau client'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(hintText: 'Nom du client'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: 'Téléphone (facultatif)',
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
            child: const Text('Créer'),
          ),
        ],
      ),
    );
    if (ok != true || name.text.trim().isEmpty) return;
    final id = await widget.repo.addContact(
      name.text,
      phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
    );
    final c = (await widget.repo.contacts()).firstWhere((c) => c.id == id);
    if (mounted) Navigator.pop(context, c);
  }

  @override
  Widget build(BuildContext context) {
    final q = normalize(_q.text);
    final list = _all.where((c) => normalize(c.name).contains(q)).toList();
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
                  hintText: 'Nom du client',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.person_add_alt_1, color: Palette.mint),
              title: Text(
                _q.text.trim().isEmpty
                    ? 'Nouveau client'
                    : 'Nouveau client « ${_q.text.trim()} »',
                style: const TextStyle(
                  color: Palette.mint,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onTap: _create,
            ),
            Expanded(
              child: ListView(
                children: [
                  for (final c in list)
                    ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(c.name),
                      subtitle: c.phone == null ? null : Text(c.phone!),
                      onTap: () => Navigator.pop(context, c),
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

/// Montant et moyen de paiement pour encaisser une facture.
Future<(int, String)?> askPayment(
  BuildContext context, {
  required String title,
  required int initial,
}) {
  final c = TextEditingController(text: '$initial');
  var method = 'especes';
  return showDialog<(int, String)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        backgroundColor: Palette.card,
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(suffixText: 'FCFA'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in paymentMethods.entries)
                  ChoiceChip(
                    label: Text(e.value),
                    selected: method == e.key,
                    onSelected: (_) => set(() => method = e.key),
                  ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), ''));
              Navigator.pop(ctx, v == null || v <= 0 ? null : (v, method));
            },
            child: const Text('Encaisser'),
          ),
        ],
      ),
    ),
  );
}

Future<bool> confirm(
  BuildContext context,
  String title,
  String text, {
  String ok = 'Oui',
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ok),
          ),
        ],
      ),
    ) ??
    false;

/// Lance une écriture, rafraîchit les écrans, et affiche l'erreur s'il y en a.
Future<T?> guarded<T>(BuildContext context, Future<T> Function() write) async {
  final app = context.read<AppState>();
  try {
    final r = await write();
    app.changed();
    return r;
  } on Object catch (e) {
    if (context.mounted) {
      toast(
        context,
        e is ArgumentError
            ? '${e.message}'
            : e.toString().replaceFirst('Bad state: ', ''),
      );
    }
    return null;
  }
}
