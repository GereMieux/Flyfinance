import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_state.dart';
import '../../data/repository.dart';
import '../../data/services_repository.dart';
import '../../services/doc_pdf.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';
import 'doc_editor_screen.dart';

class _Detail {
  _Detail(this.s, this.biz);
  final DocSummary s;
  final Map<String, String> biz;
}

/// Un devis ou une facture : contenu, paiements et toutes les actions.
class DocDetailScreen extends StatelessWidget {
  const DocDetailScreen(this.id, {super.key});
  final int id;

  @override
  Widget build(BuildContext context) {
    return Loader<_Detail>(
      load: (r) async => _Detail(await r.doc(id), await r.businessInfo()),
      builder: (context, d) => _DetailView(d),
    );
  }
}

class _DetailView extends StatelessWidget {
  const _DetailView(this.d);
  final _Detail d;

  DocSummary get s => d.s;

  void _open(BuildContext context, Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  String get _fileName => '${s.doc.number}.pdf';

  Future<void> _sharePdf(BuildContext context) async {
    final bytes = await buildDocPdf(s, d.biz);
    await Printing.sharePdf(bytes: bytes, filename: _fileName);
    if (s.isQuote && s.doc.status == 'brouillon' && context.mounted) {
      await guarded(
        context,
        () => context.read<AppState>().repo.setQuoteStatus(s.doc.id, 'envoye'),
      );
    }
  }

  Future<void> _print() => Printing.layoutPdf(
    name: _fileName,
    onLayout: (_) => buildDocPdf(s, d.biz),
  );

  /// Ouvre WhatsApp avec le résumé déjà écrit ; rien ne part sans que
  /// l'utilisateur appuie sur Envoyer.
  Future<void> _whatsapp(BuildContext context) async {
    final text = Uri.encodeComponent(docMessage(s, d.biz));
    final phone = (s.contact.phone ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    final uri = Uri.parse(
      phone.isEmpty
          ? 'https://wa.me/?text=$text'
          : 'https://wa.me/${phone.length == 10 ? '225$phone' : phone}?text=$text',
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted) return;
    if (!ok) {
      toast(context, 'WhatsApp n’a pas pu s’ouvrir.');
    } else if (s.isQuote && s.doc.status == 'brouillon') {
      await guarded(
        context,
        () => context.read<AppState>().repo.setQuoteStatus(s.doc.id, 'envoye'),
      );
    }
  }

  Future<void> _pay(BuildContext context) async {
    final repo = context.read<AppState>().repo;
    final r = await askPayment(
      context,
      title: 'Paiement de ${s.contact.name}',
      initial: s.due,
    );
    if (r == null || !context.mounted) return;
    final applied = await guarded(
      context,
      () => repo.payInvoice(s.doc.id, r.$1, method: r.$2),
    );
    if (applied != null && context.mounted) {
      toast(context, '${fcfa(applied)} encaissés.');
    }
  }

  Future<void> _toInvoice(BuildContext context) async {
    final repo = context.read<AppState>().repo;
    final now = repo.now();
    final id = await guarded(
      context,
      () => repo.invoiceFromQuote(
        s.doc.id,
        dueAt: DateTime(now.year, now.month, now.day + 15),
      ),
    );
    if (id != null && context.mounted) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => DocDetailScreen(id)));
    }
  }

  Future<void> _menu(BuildContext context, String action) async {
    final repo = context.read<AppState>().repo;
    switch (action) {
      case 'edit':
        _open(context, DocEditorScreen(kind: s.kind, existing: s));
      case 'copy':
        final id = await guarded(context, () => repo.duplicateDoc(s.doc.id));
        if (id != null && context.mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => DocDetailScreen(id)),
          );
        }
      case 'print':
        await _print();
      case 'envoye' || 'accepte' || 'refuse' || 'brouillon':
        await guarded(context, () => repo.setQuoteStatus(s.doc.id, action));
      case 'delete':
        if (await confirm(
              context,
              'Supprimer ${s.doc.number} ?',
              'Le devis sera effacé définitivement.',
              ok: 'Supprimer',
            ) &&
            context.mounted) {
          // On quitte l'écran avant d'effacer, pour ne pas recharger un
          // devis qui n'existe plus.
          final app = context.read<AppState>();
          Navigator.of(context).pop();
          await repo.deleteQuote(s.doc.id);
          app.changed();
        }
      case 'cancel':
        if (await confirm(
              context,
              'Annuler ${s.doc.number} ?',
              'La facture restera dans la liste, marquée « Annulée », et '
                  'ne sera plus comptée.',
              ok: 'Annuler la facture',
            ) &&
            context.mounted) {
          await guarded(context, () => repo.cancelInvoice(s.doc.id));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final t = s.totals;
    final status = s.status;
    final cancelled = status == DocStatus.annulee;
    final canEdit = !cancelled && status != DocStatus.facture;
    return Scaffold(
      appBar: AppBar(
        title: Text(s.doc.number),
        actions: [
          const EyeButton(),
          PopupMenuButton<String>(
            color: Palette.card,
            onSelected: (a) => _menu(context, a),
            itemBuilder: (_) => [
              if (canEdit)
                const PopupMenuItem(value: 'edit', child: Text('Modifier')),
              const PopupMenuItem(value: 'copy', child: Text('Dupliquer')),
              const PopupMenuItem(value: 'print', child: Text('Imprimer')),
              if (s.isQuote && status != DocStatus.facture) ...[
                const PopupMenuDivider(),
                for (final e in const {
                  'envoye': 'Marquer « Envoyé »',
                  'accepte': 'Marquer « Accepté »',
                  'refuse': 'Marquer « Refusé »',
                  'brouillon': 'Remettre en brouillon',
                }.entries)
                  if (s.doc.status != e.key)
                    PopupMenuItem(value: e.key, child: Text(e.value)),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text(
                    'Supprimer',
                    style: TextStyle(color: Palette.red),
                  ),
                ),
              ],
              if (!s.isQuote && !cancelled)
                const PopupMenuItem(
                  value: 'cancel',
                  child: Text(
                    'Annuler la facture',
                    style: TextStyle(color: Palette.red),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Panel(
            color: const Color(0xFF18302A),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        s.kind.label,
                        style: const TextStyle(color: Palette.muted),
                      ),
                    ),
                    StatusPill(status),
                  ],
                ),
                FittedBox(
                  child: Text(
                    app.money(s.doc.total),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (!s.isQuote && !cancelled && s.paid > 0)
                  Text(
                    'Payé ${app.money(s.paid)} · reste ${app.money(s.due)}',
                    style: const TextStyle(
                      color: Palette.amber,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 10),
                Text(
                  s.contact.name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'Le ${dayDate(s.doc.createdAt)}'
                  '${s.doc.dueAt == null
                      ? ''
                      : s.isQuote
                      ? ' · valable jusqu’au ${dayDate(s.doc.dueAt!)}'
                      : ' · à payer avant le ${dayDate(s.doc.dueAt!)}'}',
                  style: TextStyle(
                    color: status == DocStatus.enRetard
                        ? Palette.red
                        : Palette.muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () => _whatsapp(context),
            icon: const Icon(Icons.chat_outlined),
            label: const Text('Envoyer au client par WhatsApp'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => _sharePdf(context),
            icon: const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('Partager ou imprimer en PDF'),
          ),
          const SizedBox(height: 12),
          Panel(
            child: Column(
              children: [
                for (final l in s.lines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${qtyText(l.qty)} ${l.unit} × ${app.money(l.unitPrice)}',
                                style: const TextStyle(color: Palette.muted),
                              ),
                            ],
                          ),
                        ),
                        Text(app.money((l.qty * l.unitPrice).round())),
                      ],
                    ),
                  ),
                const Divider(color: Palette.line),
                if (t.discount > 0 || t.taxRate > 0)
                  _row('Sous-total', app.money(t.subtotal)),
                if (t.discount > 0) _row('Remise', app.money(-t.discount)),
                if (t.taxRate > 0) ...[
                  _row('Total HT', app.money(t.net)),
                  _row('TVA ${t.taxRate} %', app.money(t.tax)),
                ],
                _row(
                  t.taxRate > 0 ? 'Total TTC' : 'Total',
                  app.money(s.doc.total),
                  bold: true,
                ),
              ],
            ),
          ),
          if (s.doc.note != null) ...[
            const SizedBox(height: 12),
            Panel(child: Text(s.doc.note!)),
          ],
          if (s.payments.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text(
              'Paiements reçus',
              style: TextStyle(
                color: Palette.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            TilePanel(
              child: Column(
                children: [
                  for (final p in s.payments)
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.payments_outlined,
                        color: Palette.mint,
                      ),
                      title: Text(app.money(p.amount)),
                      subtitle: Text(
                        '${paymentMethods[p.method] ?? p.method} · ${shortDate(p.createdAt)}',
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: switch (status) {
            DocStatus.brouillon ||
            DocStatus.envoye ||
            DocStatus.accepte ||
            DocStatus.expire => FilledButton.icon(
              onPressed: () => _toInvoice(context),
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Le client accepte : faire la facture'),
            ),
            DocStatus.impayee ||
            DocStatus.partielle ||
            DocStatus.enRetard => FilledButton.icon(
              onPressed: () => _pay(context),
              icon: const Icon(Icons.payments_outlined),
              label: Text('Encaisser ${app.money(s.due)}'),
            ),
            _ => const SizedBox.shrink(),
          },
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: bold ? Palette.text : Palette.muted,
              fontWeight: bold ? FontWeight.w700 : null,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: bold ? 18 : 14,
          ),
        ),
      ],
    ),
  );
}
