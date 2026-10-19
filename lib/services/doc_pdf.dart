import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_state.dart';
import '../data/services_repository.dart';

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Quantité lisible : 2 plutôt que 2.0, 1,5 plutôt que 1.5.
String qtyText(double q) => q == q.roundToDouble()
    ? q.toInt().toString()
    : q.toString().replaceAll('.', ',');

/// Le PDF n'a que les polices de base (Latin-1) : on remplace les
/// caractères qu'elles n'ont pas.
String _safe(String s) {
  const swap = {
    '−': '-',
    '–': '-',
    '—': '-',
    '’': "'",
    '‘': "'",
    '“': '"',
    '”': '"',
    '…': '...',
    '•': '*',
    '€': 'EUR',
  };
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    b.write(swap[ch] ?? (r <= 0xFF ? ch : '?'));
  }
  return b.toString();
}

/// Construit le PDF d'un devis ou d'une facture, prêt à partager ou imprimer.
Future<Uint8List> buildDocPdf(DocSummary s, Map<String, String> biz) async {
  const green = PdfColor.fromInt(0xFF1F6B4F);
  const grey = PdfColor.fromInt(0xFF666666);
  final t = s.totals;
  final title = s.kind.label.toUpperCase();
  String? b(String k) => biz[k] == null ? null : _safe(biz[k]!);

  pw.Widget amountRow(String label, int value, {bool bold = false}) => pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.end,
    children: [
      pw.SizedBox(
        width: 130,
        child: pw.Text(
          label,
          style: pw.TextStyle(fontWeight: bold ? pw.FontWeight.bold : null),
        ),
      ),
      pw.SizedBox(
        width: 110,
        child: pw.Text(
          _safe(fcfa(value)),
          textAlign: pw.TextAlign.right,
          style: pw.TextStyle(
            fontWeight: bold ? pw.FontWeight.bold : null,
            fontSize: bold ? 13 : null,
          ),
        ),
      ),
    ],
  );

  final pdf = pw.Document(title: '${s.kind.label} ${s.doc.number}');
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(36),
      build: (_) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    b('biz.name') ?? 'Mon entreprise',
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                      color: green,
                    ),
                  ),
                  for (final k in [
                    'biz.activity',
                    'biz.address',
                    'biz.phone',
                    'biz.email',
                    'biz.legal',
                  ])
                    if (b(k) != null)
                      pw.Text(b(k)!, style: const pw.TextStyle(color: grey)),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 22,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.Text('N° ${s.doc.number}'),
                pw.Text('Date : ${_date(s.doc.createdAt)}'),
                if (s.doc.dueAt != null)
                  pw.Text(
                    s.isQuote
                        ? 'Valable jusqu\'au ${_date(s.doc.dueAt!)}'
                        : 'A payer avant le ${_date(s.doc.dueAt!)}',
                  ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 24),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Client', style: const pw.TextStyle(color: grey)),
              pw.Text(
                _safe(s.contact.name),
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
              if (s.contact.phone != null) pw.Text(_safe(s.contact.phone!)),
            ],
          ),
        ),
        pw.SizedBox(height: 18),
        pw.TableHelper.fromTextArray(
          headerDecoration: const pw.BoxDecoration(color: green),
          headerStyle: pw.TextStyle(
            color: PdfColors.white,
            fontWeight: pw.FontWeight.bold,
          ),
          cellAlignments: {
            1: pw.Alignment.centerRight,
            2: pw.Alignment.centerRight,
            3: pw.Alignment.centerRight,
          },
          columnWidths: {
            0: const pw.FlexColumnWidth(4),
            1: const pw.FlexColumnWidth(1.6),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(2),
          },
          headers: ['Désignation', 'Qté', 'Prix unitaire', 'Montant'],
          data: [
            for (final l in s.lines)
              [
                _safe(l.label),
                _safe('${qtyText(l.qty)} ${l.unit}'),
                _safe(fcfa(l.unitPrice)),
                _safe(fcfa((l.qty * l.unitPrice).round())),
              ],
          ],
        ),
        pw.SizedBox(height: 12),
        if (t.discount > 0 || t.taxRate > 0)
          amountRow('Sous-total', t.subtotal),
        if (t.discount > 0) amountRow('Remise', -t.discount),
        if (t.taxRate > 0) ...[
          amountRow('Total HT', t.net),
          amountRow('TVA ${t.taxRate} %', t.tax),
        ],
        amountRow(
          t.taxRate > 0 ? 'Total TTC' : 'Total',
          s.doc.total,
          bold: true,
        ),
        if (!s.isQuote && s.paid > 0) ...[
          amountRow('Déjà payé', s.paid),
          amountRow('Reste à payer', s.due, bold: true),
        ],
        pw.SizedBox(height: 24),
        if (s.doc.note != null) ...[
          pw.Text(_safe(s.doc.note!)),
          pw.SizedBox(height: 10),
        ],
        if (b('biz.terms') != null)
          pw.Text(b('biz.terms')!, style: const pw.TextStyle(color: grey)),
        if (b('biz.payment') != null)
          pw.Text(
            'Paiement : ${b('biz.payment')}',
            style: const pw.TextStyle(color: grey),
          ),
        if (s.isQuote) ...[
          pw.SizedBox(height: 30),
          pw.Text('Bon pour accord (date et signature du client) :'),
          pw.SizedBox(height: 50),
        ],
      ],
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${s.doc.number} - page ${ctx.pageNumber}/${ctx.pagesCount}',
          style: const pw.TextStyle(color: grey, fontSize: 9),
        ),
      ),
    ),
  );
  return pdf.save();
}

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
