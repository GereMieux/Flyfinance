import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../data/accounts_repository.dart';
import '../../data/database.dart';
import '../theme.dart';
import '../widgets.dart';

String dayOnly(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Numéro au format WhatsApp : les numéros ivoiriens à 10 chiffres
/// reçoivent l'indicatif 225.
String waPhone(String? phone) {
  final p = (phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  return p.length == 10 ? '225$p' : p;
}

/// Ouvre WhatsApp avec le message déjà écrit. Rien ne part sans que le
/// commerçant appuie lui-même sur Envoyer.
Future<bool> openWhatsApp(
  BuildContext context,
  String? phone,
  String text,
) async {
  final to = waPhone(phone);
  final uri = Uri.parse(
    'https://wa.me/${to.isEmpty ? '' : to}?text=${Uri.encodeComponent(text)}',
  );
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) toast(context, 'WhatsApp n’a pas pu s’ouvrir.');
  return ok;
}

Future<void> callPhone(BuildContext context, String phone) async {
  final ok = await launchUrl(Uri.parse('tel:$phone'));
  if (!ok && context.mounted) toast(context, 'L’appel n’a pas pu partir.');
}

/// Fiche du carnet d'adresses : nom, téléphone, adresse. Renvoie l'identifiant
/// du contact créé ou modifié.
Future<int?> editContact(
  BuildContext context, {
  required String kind,
  Contact? contact,
}) async {
  final repo = context.read<AppState>().repo;
  final name = TextEditingController(text: contact?.name ?? '');
  final phone = TextEditingController(text: contact?.phone ?? '');
  final address = TextEditingController(text: contact?.address ?? '');
  final who = kind == 'fournisseur' ? 'fournisseur' : 'client';
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Palette.card,
      title: Text(contact == null ? 'Nouveau $who' : 'Modifier'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: contact == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Nom',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Téléphone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: address,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Adresse',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
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
          child: const Text('Enregistrer'),
        ),
      ],
    ),
  );
  if (ok != true || name.text.trim().isEmpty) return null;
  final p = phone.text.trim().isEmpty ? null : phone.text.trim();
  final a = address.text.trim().isEmpty ? null : address.text.trim();
  if (contact == null) {
    return repo.addContact(name.text, phone: p, address: a, kind: kind);
  }
  await repo.updateContact(contact.id, name: name.text, phone: p, address: a);
  return contact.id;
}

class MoneyInput {
  MoneyInput(this.amount, this.method, this.at, this.note);
  final int amount;
  final String method;
  final DateTime at;
  final String? note;
}

/// Montant, moyen de paiement, date et note d'un versement.
Future<MoneyInput?> askMoney(
  BuildContext context, {
  required String title,
  required String action,
  int? initial,
  bool withDate = true,
}) {
  final c = TextEditingController(text: initial == null ? '' : '$initial');
  final note = TextEditingController();
  var method = 'especes';
  final now = context.read<AppState>().repo.now();
  var at = now;
  return showDialog<MoneyInput>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        backgroundColor: Palette.card,
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
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
                  for (final e in accountMethods.entries)
                    ChoiceChip(
                      label: Text(e.value),
                      selected: method == e.key,
                      onSelected: (_) => set(() => method = e.key),
                    ),
                ],
              ),
              if (withDate) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    _sameDay(at, now) ? 'Aujourd’hui' : 'Le ${dayOnly(at)}',
                  ),
                  onPressed: () async {
                    final d = await showDatePicker(
                      context: ctx,
                      initialDate: at,
                      firstDate: DateTime(now.year - 3),
                      lastDate: now,
                    );
                    if (d != null) {
                      set(
                        () => at = _sameDay(d, now)
                            ? now
                            : DateTime(d.year, d.month, d.day, 12),
                      );
                    }
                  },
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Note (facultatif)',
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
              final v = int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), ''));
              Navigator.pop(
                ctx,
                v == null || v <= 0
                    ? null
                    : MoneyInput(
                        v,
                        method,
                        at,
                        note.text.trim().isEmpty ? null : note.text.trim(),
                      ),
              );
            },
            child: Text(action),
          ),
        ],
      ),
    ),
  );
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Une ligne de l'historique d'un compte.
class MoveTile extends StatelessWidget {
  const MoveTile(this.m, {super.key, this.onTap});
  final AccountMove m;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final color = m.cancelled
        ? Palette.grey
        : m.debit
        ? Palette.amber
        : Palette.mint;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: color.withValues(alpha: 0.15),
              child: Icon(
                m.debit ? Icons.shopping_bag_outlined : Icons.payments_outlined,
                size: 18,
                color: color,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    m.cancelled ? '${m.title} (annulé)' : m.title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: m.cancelled
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  Text(
                    [
                      shortDate(m.at),
                      if (m.detail.isNotEmpty) m.detail,
                    ].join(' · '),
                    style: TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${m.debit ? '' : '+ '}${app.money(m.amount)}',
              style: TextStyle(fontWeight: FontWeight.w700, color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// En-tête d'un compte : initiale, nom, téléphone et adresse, avec les
/// boutons appeler, WhatsApp et modifier.
class ContactHeader extends StatelessWidget {
  const ContactHeader(this.c, {super.key, required this.onEdit});
  final Contact c;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final supplier = c.kind == 'fournisseur';
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: supplier
                    ? Palette.purple.withValues(alpha: 0.15)
                    : Palette.mintSoft,
                child: Text(
                  c.name.characters.first.toUpperCase(),
                  style: TextStyle(
                    fontSize: 20,
                    color: supplier ? Palette.purple : Palette.mint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  c.name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Modifier',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          if (c.phone != null || c.address != null) const SizedBox(height: 8),
          if (c.phone != null) _info(Icons.phone_outlined, c.phone!),
          if (c.address != null) _info(Icons.place_outlined, c.address!),
          if (c.phone != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => callPhone(context, c.phone!),
                    icon: const Icon(Icons.call_outlined, size: 18),
                    label: const Text('Appeler'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openWhatsApp(context, c.phone, ''),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('WhatsApp'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _info(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 4),
    child: Row(
      children: [
        Icon(icon, size: 16, color: Palette.muted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text, style: TextStyle(color: Palette.muted)),
        ),
      ],
    ),
  );
}

/// Titre de section dans un compte.
Widget sectionTitle(String text) => Padding(
  padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
  child: Text(
    text,
    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
  ),
);

/// Comme [Panel], mais avec un Material : les ListTile y dessinent leur
/// effet au toucher.
class TilesPanel extends StatelessWidget {
  const TilesPanel({super.key, required this.child, required this.padding});
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => Material(
    color: Palette.card,
    borderRadius: BorderRadius.circular(20),
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: padding, child: child),
  );
}
