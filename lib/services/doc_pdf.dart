import 'dart:typed_data';

import '../app_state.dart';
import '../data/services_repository.dart';
import 'receipt_pdf.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Quantité lisible : 2 plutôt que 2.0, 1,5 plutôt que 1.5.
String qtyText(double q) => q == q.roundToDouble()
    ? q.toInt().toString()
    : q.toString().replaceAll('.', ',');

/// Construit le PDF d'un devis ou d'une facture, prêt à partager ou
/// imprimer, avec le logo et le modèle choisis dans « Mon entreprise ».
Future<Uint8List> buildDocPdf(
  DocSummary s,
  Map<String, String> biz, {
  BrandSettings brand = const BrandSettings(),
  PaperSize paper = PaperSize.a4,
}) => buildReceiptPdf(ReceiptData.fromDoc(s), biz, brand, paper: paper);

/// Message court pour WhatsApp ou SMS.
String docMessage(DocSummary s, Map<String, String> biz) {
  final from = biz['biz.name'];
  final b = StringBuffer('Bonjour ${s.contact.name},\n');
  if (s.isQuote) {
    b.write(
      'voici le devis ${s.doc.number} d’un montant de ${fcfa(s.doc.total)}',
    );
    if (s.doc.dueAt != null) {
      b.write(', valable jusqu’au ${_date(s.doc.dueAt!)}');
    }
    b.write('.\n');
  } else {
    b.write(
      'voici la facture ${s.doc.number} d’un montant de ${fcfa(s.doc.total)}.\n',
    );
    if (s.paid > 0) b.write('Déjà payé : ${fcfa(s.paid)}. ');
    if (s.due > 0) b.write('Reste à payer : ${fcfa(s.due)}');
    if (s.due > 0 && s.doc.dueAt != null) {
      b.write(' avant le ${_date(s.doc.dueAt!)}');
    }
    if (s.due > 0) b.write('.\n');
  }
  for (final l in s.lines) {
    b.write(
      '• ${l.label} : ${qtyText(l.qty)} ${l.unit} × ${fcfa(l.unitPrice)}\n',
    );
  }
  if (biz['biz.payment'] != null && s.due > 0) {
    b.write('Paiement : ${biz['biz.payment']}\n');
  }
  b.write('Merci${from == null ? '' : ' — $from'} !');
  return b.toString();
}
