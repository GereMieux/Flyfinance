import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../app_state.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../data/services_repository.dart';

/// Les documents qu'on peut tirer d'une vente ou d'une prestation.
enum ReceiptKind { recu, facture, proforma, livraison, devis }

extension ReceiptKindInfo on ReceiptKind {
  String get label => switch (this) {
    ReceiptKind.recu => 'Reçu de paiement',
    ReceiptKind.facture => 'Facture',
    ReceiptKind.proforma => 'Facture proforma',
    ReceiptKind.livraison => 'Bon de livraison',
    ReceiptKind.devis => 'Devis',
  };

  /// Nom court pour les boutons de choix.
  String get short => switch (this) {
    ReceiptKind.recu => 'Reçu',
    ReceiptKind.facture => 'Facture',
    ReceiptKind.proforma => 'Proforma',
    ReceiptKind.livraison => 'Bon de livraison',
    ReceiptKind.devis => 'Devis',
  };

  bool get showsPrices => this != ReceiptKind.livraison;
  bool get showsPayments =>
      this == ReceiptKind.recu || this == ReceiptKind.facture;
}

/// Taille du papier : rouleaux des imprimantes thermiques ou feuilles.
enum PaperSize { ticket58, ticket80, a5, a4 }

extension PaperSizeInfo on PaperSize {
  String get label => switch (this) {
    PaperSize.ticket58 => 'Ticket 58 mm',
    PaperSize.ticket80 => 'Ticket 80 mm',
    PaperSize.a5 => 'A5',
    PaperSize.a4 => 'A4',
  };
  bool get isTicket => this == PaperSize.ticket58 || this == PaperSize.ticket80;
}

/// Habillage des documents.
enum ReceiptStyle { neon, aurore, epure }

extension ReceiptStyleInfo on ReceiptStyle {
  String get label => switch (this) {
    ReceiptStyle.neon => 'Néon',
    ReceiptStyle.aurore => 'Aurore',
    ReceiptStyle.epure => 'Épuré',
  };
}

/// Phrases proposées en bas des tickets pour donner envie de revenir.
const thanksIdeas = [
  'Merci pour votre confiance ! Votre prochaine visite nous fera très plaisir.',
  'Ici, chaque client est un ami. Revenez nous voir très vite !',
  'Des nouveautés arrivent chaque semaine : passez les découvrir !',
  'Votre sourire est notre plus belle récompense. À très bientôt !',
  'Parlez de nous autour de vous, et revenez quand vous voulez !',
];

/// Réglages d'apparence choisis dans « Mon entreprise ».
class BrandSettings {
  const BrandSettings({
    this.logo,
    this.style = ReceiptStyle.neon,
    this.paper = PaperSize.ticket80,
    this.thanks,
  });
  final Uint8List? logo;
  final ReceiptStyle style;

  /// Taille utilisée pour les reçus de caisse.
  final PaperSize paper;

  /// Phrase de fin. Vide : une des [thanksIdeas], qui change d'un ticket
  /// à l'autre.
  final String? thanks;

  String thanksFor(String number) {
    final t = thanks?.trim() ?? '';
    if (t.isNotEmpty) return t;
    final i = number.codeUnits.fold<int>(0, (s, c) => s + c);
    return thanksIdeas[i % thanksIdeas.length];
  }
}

class ReceiptLine {
  const ReceiptLine(this.label, this.qty, this.unit, this.unitPrice);
  final String label;
  final double qty;
  final String unit;
  final int unitPrice;
  int get total => (qty * unitPrice).round();
}

class ReceiptPayment {
  const ReceiptPayment(this.method, this.amount, this.at);
  final String method;
  final int amount;
  final DateTime at;
}

/// Tout ce qu'un reçu ou une facture affiche, quelle que soit sa source
/// (vente en boutique ou prestation).
class ReceiptData {
  const ReceiptData({
    required this.kind,
    required this.number,
    required this.date,
    required this.lines,
    required this.total,
    this.clientName,
    this.clientPhone,
    this.clientAddress,
    this.subtotal,
    this.discount = 0,
    this.taxRate = 0,
    this.tax = 0,
    this.payments = const [],
    this.dueDate,
    this.note,
    this.cancelled = false,
  });
  final ReceiptKind kind;
  final String number;
  final DateTime date;
  final List<ReceiptLine> lines;
  final int total;
  final String? clientName;
  final String? clientPhone;
  final String? clientAddress;
  final int? subtotal;
  final int discount;
  final int taxRate;
  final int tax;
  final List<ReceiptPayment> payments;
  final DateTime? dueDate;
  final String? note;
  final bool cancelled;

  int get paid => payments.fold(0, (s, p) => s + p.amount);
  int get due => cancelled ? 0 : (total - paid).clamp(0, total);

  ReceiptData as(ReceiptKind k) => ReceiptData(
    kind: k,
    number: number,
    date: date,
    lines: lines,
    total: total,
    clientName: clientName,
    clientPhone: clientPhone,
    clientAddress: clientAddress,
    subtotal: subtotal,
    discount: discount,
    taxRate: taxRate,
    tax: tax,
    payments: payments,
    dueDate: dueDate,
    note: note,
    cancelled: cancelled,
  );

  /// Numéro d'une vente en boutique : V-000042.
  static String saleNumber(int id) => 'V-${id.toString().padLeft(6, '0')}';

  factory ReceiptData.fromSale(
    SaleDetail d,
    List<Payment> payments, {
    ReceiptKind kind = ReceiptKind.recu,
  }) {
    final s = d.summary;
    return ReceiptData(
      kind: kind,
      number: saleNumber(s.sale.id),
      date: s.sale.createdAt,
      clientName: s.contact?.name,
      clientPhone: s.contact?.phone,
      lines: [
        for (final l in d.lines)
          ReceiptLine(
            l.product.name,
            l.qty.toDouble(),
            l.product.unit,
            l.unitPrice,
          ),
      ],
      total: s.sale.total,
      payments: [
        for (final p in payments)
          ReceiptPayment(
            paymentMethods[p.method] ?? p.method,
            p.amount,
            p.createdAt,
          ),
      ],
      cancelled: s.sale.cancelled,
    );
  }

  factory ReceiptData.fromDoc(DocSummary s) {
    final t = s.totals;
    return ReceiptData(
      kind: s.isQuote ? ReceiptKind.devis : ReceiptKind.facture,
      number: s.doc.number,
      date: s.doc.createdAt,
      clientName: s.contact.name,
      clientPhone: s.contact.phone,
      clientAddress: s.contact.address,
      lines: [
        for (final l in s.lines)
          ReceiptLine(l.label, l.qty, l.unit, l.unitPrice),
      ],
      subtotal: t.subtotal,
      discount: t.discount,
      taxRate: t.taxRate,
      tax: t.tax,
      total: s.doc.total,
      payments: s.isQuote
          ? const []
          : [
              for (final p in s.payments)
                ReceiptPayment(
                  paymentMethods[p.method] ?? p.method,
                  p.amount,
                  p.createdAt,
                ),
            ],
      dueDate: s.doc.dueAt,
      note: s.doc.note,
      cancelled: s.doc.status == 'annulee',
    );
  }
}

/// Polices embarquées : Inter pour le texte, Rajdhani pour les titres et
/// les montants (allure futuriste).
class ReceiptFonts {
  const ReceiptFonts(this.body, this.medium, this.bold, this.display);
  final pw.Font body;
  final pw.Font medium;
  final pw.Font bold;
  final pw.Font display;

  static ReceiptFonts? _cache;

  /// Charge les polices de l'application ; `null` si elles manquent (tests),
  /// le PDF prend alors les polices de base.
  static Future<ReceiptFonts?> load() async {
    if (_cache != null) return _cache;
    try {
      Future<pw.Font> f(String n) async =>
          pw.Font.ttf(await rootBundle.load('assets/fonts/$n.ttf'));
      _cache = ReceiptFonts(
        await f('Inter-Regular'),
        await f('Inter-SemiBold'),
        await f('Inter-Bold'),
        await f('Rajdhani-Bold'),
      );
    } catch (_) {
      return null;
    }
    return _cache;
  }
}

/// Couleurs d'un habillage.
class _Look {
  const _Look({
    required this.dark,
    required this.dark2,
    required this.accent,
    required this.accent2,
    required this.soft,
    required this.onHeader,
  });
  final PdfColor dark;
  final PdfColor dark2;
  final PdfColor accent;
  final PdfColor accent2;
  final PdfColor soft;
  final PdfColor onHeader;

  static _Look of(ReceiptStyle s) => switch (s) {
    ReceiptStyle.neon => const _Look(
      dark: PdfColor.fromInt(0xFF07120E),
      dark2: PdfColor.fromInt(0xFF15412F),
      accent: PdfColor.fromInt(0xFF13A86B),
      accent2: PdfColor.fromInt(0xFF3BE3A8),
      soft: PdfColor.fromInt(0xFFEEF9F3),
      onHeader: PdfColors.white,
    ),
    ReceiptStyle.aurore => const _Look(
      dark: PdfColor.fromInt(0xFF4A2CC4),
      dark2: PdfColor.fromInt(0xFF12B5D6),
      accent: PdfColor.fromInt(0xFF5B3FE0),
      accent2: PdfColor.fromInt(0xFFB9F3FF),
      soft: PdfColor.fromInt(0xFFF2F0FE),
      onHeader: PdfColors.white,
    ),
    ReceiptStyle.epure => const _Look(
      dark: PdfColor.fromInt(0xFF14201B),
      dark2: PdfColor.fromInt(0xFF14201B),
      accent: PdfColor.fromInt(0xFF1F6B4F),
      accent2: PdfColor.fromInt(0xFF1F6B4F),
      soft: PdfColor.fromInt(0xFFF4F6F5),
      onHeader: PdfColor.fromInt(0xFF14201B),
    ),
  };
}

const _grey = PdfColor.fromInt(0xFF66706B);
const _ink = PdfColor.fromInt(0xFF14201B);
const _paid = PdfColor.fromInt(0xFF13A86B);
const _owed = PdfColor.fromInt(0xFFD98A00);
const _void = PdfColor.fromInt(0xFFC0392B);

String _d(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String _dt(DateTime d) =>
    '${_d(d)} à ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _qty(double q) => q == q.roundToDouble()
    ? q.toInt().toString()
    : q.toString().replaceAll('.', ',');

/// Les polices de base n'ont que le Latin-1 : on remplace le reste.
String _latin1(String s) {
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

/// Construit le reçu, la facture, le bon ou le devis au format demandé.
Future<Uint8List> buildReceiptPdf(
  ReceiptData data,
  Map<String, String> biz,
  BrandSettings brand, {
  PaperSize? paper,
  ReceiptFonts? fonts,
}) async {
  fonts ??= await ReceiptFonts.load();
  final r = _Renderer(data, biz, brand, paper ?? brand.paper, fonts);
  return r.build();
}

class _Renderer {
  _Renderer(this.d, this.biz, this.brand, this.paper, this.fonts)
    : look = _Look.of(brand.style);
  final ReceiptData d;
  final Map<String, String> biz;
  final BrandSettings brand;
  final PaperSize paper;
  final ReceiptFonts? fonts;
  final _Look look;

  String t(String s) => fonts == null ? _latin1(s) : s;
  String money(int v) => t(fcfa(v));
  String? b(String k) {
    final v = biz[k]?.trim();
    return v == null || v.isEmpty ? null : t(v);
  }

  String get name => b('biz.name') ?? 'Mon entreprise';
  String get thanks => t(brand.thanksFor(d.number));

  pw.TextStyle st(
    double size, {
    PdfColor color = _ink,
    bool bold = false,
    bool display = false,
    double spacing = 0,
  }) => pw.TextStyle(
    fontSize: size,
    color: color,
    font: fonts == null
        ? null
        : display
        ? fonts!.display
        : bold
        ? fonts!.bold
        : fonts!.body,
    fontWeight: bold || display ? pw.FontWeight.bold : null,
    letterSpacing: spacing,
  );

  pw.Widget? logo(double w, double h) {
    if (brand.logo == null) return null;
    try {
      return pw.Image(
        pw.MemoryImage(brand.logo!),
        width: w,
        height: h,
        fit: pw.BoxFit.contain,
      );
    } catch (_) {
      // Image illisible : le document sort quand même, sans logo.
      return null;
    }
  }

  pw.Widget qr(double size, PdfColor color) => pw.BarcodeWidget(
    barcode: pw.Barcode.qrCode(),
    data:
        'FLYFINANCE|${d.number}|${d.total} FCFA|${_d(d.date)}|${biz['biz.name'] ?? ''}',
    width: size,
    height: size,
    color: color,
    drawText: false,
  );

  /// État affiché en tampon.
  (String, PdfColor)? get stamp {
    if (d.cancelled) return ('ANNULÉE', _void);
    if (!d.kind.showsPayments) return null;
    if (d.due == 0) {
      return (d.kind == ReceiptKind.recu ? 'PAYÉ' : 'PAYÉE', _paid);
    }
    if (d.paid > 0) return ('ACOMPTE', _owed);
    return ('À PAYER', _owed);
  }

  Future<Uint8List> build() {
    final doc = pw.Document(
      title: '${d.kind.label} ${d.number}',
      author: biz['biz.name'] ?? 'FLYFINANCE',
      creator: 'FLYFINANCE',
      theme: fonts == null
          ? null
          : pw.ThemeData.withFont(base: fonts!.body, bold: fonts!.bold),
    );
    if (paper.isTicket) {
      doc.addPage(_ticket());
    } else {
      doc.addPage(_sheet());
    }
    return doc.save();
  }

  // ---------------------------------------------------------------- Ticket

  pw.Page _ticket() {
    final wide = paper == PaperSize.ticket80;
    final width = (wide ? 80 : 58) * PdfPageFormat.mm;
    final s = wide ? 1.0 : 0.82; // échelle des textes
    final neon = brand.style == ReceiptStyle.neon;
    final aurore = brand.style == ReceiptStyle.aurore;

    pw.Widget dash() => pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 5),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
            color: _ink,
            width: 0.6,
            style: pw.BorderStyle.dashed,
          ),
        ),
      ),
    );

    pw.Widget row(String l, String r, {bool bold = false, double size = 8}) =>
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Text(t(l), style: st(size * s, bold: bold)),
            ),
            pw.Text(r, style: st(size * s, bold: bold)),
          ],
        );

    final logoW = logo(width * 0.45, 16 * PdfPageFormat.mm);
    final st0 = stamp;

    return pw.Page(
      pageFormat: PdfPageFormat(
        width,
        double.infinity,
        marginAll: 3 * PdfPageFormat.mm,
      ),
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          if (logoW != null) ...[
            pw.Center(child: logoW),
            pw.SizedBox(height: 4),
          ],
          // En-tête : bandeau noir (Néon), double cadre (Aurore) ou simple.
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(vertical: 5, horizontal: 4),
            decoration: neon
                ? pw.BoxDecoration(
                    color: _ink,
                    borderRadius: pw.BorderRadius.circular(4),
                  )
                : aurore
                ? pw.BoxDecoration(
                    border: pw.Border.all(color: _ink, width: 1.4),
                    borderRadius: pw.BorderRadius.circular(6),
                  )
                : null,
            child: pw.Text(
              name.toUpperCase(),
              textAlign: pw.TextAlign.center,
              style: st(
                15 * s,
                display: true,
                spacing: 1.2,
                color: neon ? PdfColors.white : _ink,
              ),
            ),
          ),
          pw.SizedBox(height: 3),
          for (final k in ['biz.activity', 'biz.address', 'biz.phone'])
            if (b(k) != null)
              pw.Text(
                b(k)!,
                textAlign: pw.TextAlign.center,
                style: st(7.5 * s),
              ),
          if (b('biz.legal') != null)
            pw.Text(
              b('biz.legal')!,
              textAlign: pw.TextAlign.center,
              style: st(6.5 * s, color: _grey),
            ),
          dash(),
          pw.Text(
            t(d.kind.label.toUpperCase()),
            textAlign: pw.TextAlign.center,
            style: st(11 * s, display: true, spacing: 2),
          ),
          pw.Text(
            'N° ${d.number}',
            textAlign: pw.TextAlign.center,
            style: st(8 * s, bold: true),
          ),
          pw.Text(
            t(_dt(d.date)),
            textAlign: pw.TextAlign.center,
            style: st(7.5 * s),
          ),
          if (d.clientName != null) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              t('Client : ${d.clientName}'),
              textAlign: pw.TextAlign.center,
              style: st(8 * s, bold: true),
            ),
            if (d.clientPhone != null)
              pw.Text(
                t(d.clientPhone!),
                textAlign: pw.TextAlign.center,
                style: st(7.5 * s),
              ),
          ],
          dash(),
          for (final l in d.lines) ...[
            pw.Text(t(l.label), style: st(8.5 * s, bold: true)),
            if (d.kind.showsPrices)
              row(
                '${_qty(l.qty)} ${l.unit} × ${fcfa(l.unitPrice)}',
                money(l.total),
              )
            else
              row('Quantité', t('${_qty(l.qty)} ${l.unit}')),
            pw.SizedBox(height: 3),
          ],
          dash(),
          if (d.kind.showsPrices) ...[
            if (d.discount > 0 || d.taxRate > 0)
              row('Sous-total', money(d.subtotal ?? d.total)),
            if (d.discount > 0) row('Remise', money(-d.discount)),
            if (d.taxRate > 0) row('TVA ${d.taxRate} %', money(d.tax)),
            pw.SizedBox(height: 3),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                vertical: 5,
                horizontal: 6,
              ),
              decoration: neon
                  ? pw.BoxDecoration(
                      color: _ink,
                      borderRadius: pw.BorderRadius.circular(4),
                    )
                  : aurore
                  ? const pw.BoxDecoration(
                      border: pw.Border(
                        top: pw.BorderSide(color: _ink, width: 1.4),
                        bottom: pw.BorderSide(color: _ink, width: 1.4),
                      ),
                    )
                  : null,
              child: pw.Row(
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      d.taxRate > 0 ? 'TOTAL TTC' : 'TOTAL',
                      style: st(
                        12 * s,
                        display: true,
                        spacing: 1.5,
                        color: neon ? PdfColors.white : _ink,
                      ),
                    ),
                  ),
                  pw.Text(
                    money(d.total),
                    style: st(
                      14 * s,
                      display: true,
                      color: neon ? PdfColors.white : _ink,
                    ),
                  ),
                ],
              ),
            ),
            if (d.kind.showsPayments) ...[
              pw.SizedBox(height: 4),
              for (final p in d.payments)
                row('${p.method} · ${_d(p.at)}', money(p.amount)),
              if (d.payments.isNotEmpty && d.due > 0)
                row('Reste à payer', money(d.due), bold: true, size: 9),
            ],
          ],
          if (st0 != null) ...[
            pw.SizedBox(height: 5),
            pw.Center(
              child: pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _ink, width: 1.2),
                  borderRadius: pw.BorderRadius.circular(10),
                ),
                child: pw.Text(
                  t(st0.$1),
                  style: st(9 * s, display: true, spacing: 2),
                ),
              ),
            ),
          ],
          if (d.kind == ReceiptKind.livraison) ...[
            pw.SizedBox(height: 8),
            pw.Text('Reçu par (nom et signature) :', style: st(7.5 * s)),
            pw.SizedBox(height: 26),
          ],
          if (b('biz.payment') != null && d.due > 0) ...[
            pw.SizedBox(height: 4),
            pw.Text(
              t('Paiement : ${b('biz.payment')}'),
              textAlign: pw.TextAlign.center,
              style: st(7.5 * s),
            ),
          ],
          pw.SizedBox(height: 6),
          pw.Center(child: qr((wide ? 22 : 18) * PdfPageFormat.mm, _ink)),
          pw.SizedBox(height: 6),
          // La phrase qui donne envie de revenir.
          pw.Container(
            padding: const pw.EdgeInsets.all(5),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                color: _ink,
                width: 0.8,
                style: neon ? pw.BorderStyle.solid : pw.BorderStyle.dashed,
              ),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Text(
              thanks,
              textAlign: pw.TextAlign.center,
              style: st(8.5 * s, bold: true),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            'Ticket édité avec FLYFINANCE',
            textAlign: pw.TextAlign.center,
            style: st(6 * s, color: _grey),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------- Feuille A4 / A5

  pw.MultiPage _sheet() {
    final a5 = paper == PaperSize.a5;
    final k = a5 ? 0.8 : 1.0;
    final format = a5 ? PdfPageFormat.a5 : PdfPageFormat.a4;
    final epure = brand.style == ReceiptStyle.epure;

    return pw.MultiPage(
      pageFormat: format,
      margin: pw.EdgeInsets.fromLTRB(28 * k, 26 * k, 28 * k, 22 * k),
      header: (ctx) => ctx.pageNumber == 1 ? pw.SizedBox() : pw.SizedBox(),
      footer: (ctx) => _footer(ctx, k),
      build: (_) => [
        _header(k, epure),
        pw.SizedBox(height: 16 * k),
        _infoCards(k),
        pw.SizedBox(height: 16 * k),
        _table(k, epure),
        pw.SizedBox(height: 14 * k),
        _totals(k, epure),
        if (d.note != null) ...[
          pw.SizedBox(height: 14 * k),
          pw.Text(t(d.note!), style: st(9.5 * k)),
        ],
        pw.SizedBox(height: 12 * k),
        if (b('biz.terms') != null)
          pw.Text(b('biz.terms')!, style: st(8.5 * k, color: _grey)),
        if (b('biz.payment') != null && d.kind != ReceiptKind.livraison)
          pw.Text(
            t('Paiement : ${b('biz.payment')}'),
            style: st(8.5 * k, color: _grey),
          ),
        if (d.kind == ReceiptKind.devis ||
            d.kind == ReceiptKind.proforma ||
            d.kind == ReceiptKind.livraison)
          _signature(k),
      ],
    );
  }

  pw.Widget _header(double k, bool epure) {
    final logoW = logo(58 * k, 58 * k);
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();
    final badge = pw.Container(
      width: 62 * k,
      height: 62 * k,
      padding: pw.EdgeInsets.all(4 * k),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(14 * k),
        border: epure ? pw.Border.all(color: look.accent, width: 1.2) : null,
      ),
      alignment: pw.Alignment.center,
      child:
          logoW ??
          pw.Text(
            initials,
            style: st(24 * k, display: true, color: look.accent),
          ),
    );
    final c = look.onHeader;
    final soft = epure ? _grey : const PdfColor(1, 1, 1, 0.78);
    final content = pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        badge,
        pw.SizedBox(width: 14 * k),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(name, style: st(21 * k, display: true, color: c)),
              for (final key in [
                'biz.activity',
                'biz.address',
                'biz.phone',
                'biz.email',
                'biz.legal',
              ])
                if (b(key) != null)
                  pw.Text(b(key)!, style: st(8.5 * k, color: soft)),
            ],
          ),
        ),
        pw.SizedBox(width: 10 * k),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              t(d.kind.label.toUpperCase()),
              style: st(
                12 * k,
                display: true,
                spacing: 2.5,
                color: epure ? look.accent : look.accent2,
              ),
            ),
            pw.SizedBox(height: 2 * k),
            pw.Text(d.number, style: st(17 * k, display: true, color: c)),
            pw.SizedBox(height: 2 * k),
            pw.Text(t(_d(d.date)), style: st(9 * k, color: soft)),
          ],
        ),
      ],
    );
    if (epure) {
      return pw.Container(
        padding: pw.EdgeInsets.only(bottom: 12 * k),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: look.accent, width: 2.4),
          ),
        ),
        child: content,
      );
    }
    // Bandeau dégradé avec cercles lumineux et ligne néon.
    return pw.Column(
      children: [
        pw.ClipRRect(
          horizontalRadius: 16 * k,
          verticalRadius: 16 * k,
          child: pw.Container(
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [look.dark, look.dark2],
                begin: pw.Alignment.topLeft,
                end: pw.Alignment.bottomRight,
              ),
            ),
            child: pw.Stack(
              overflow: pw.Overflow.clip,
              children: [
                pw.Positioned(
                  right: -40 * k,
                  top: -50 * k,
                  child: _ring(150 * k, look.accent2, 0.18),
                ),
                pw.Positioned(
                  right: 70 * k,
                  bottom: -60 * k,
                  child: _ring(110 * k, look.accent2, 0.12),
                ),
                pw.Padding(padding: pw.EdgeInsets.all(18 * k), child: content),
              ],
            ),
          ),
        ),
        pw.SizedBox(height: 4 * k),
        pw.Row(
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Container(height: 2.2 * k, color: look.accent2),
            ),
            pw.SizedBox(width: 4 * k),
            pw.Expanded(
              flex: 2,
              child: pw.Container(height: 2.2 * k, color: look.accent),
            ),
            pw.SizedBox(width: 4 * k),
            pw.Container(width: 14 * k, height: 2.2 * k, color: look.dark),
          ],
        ),
      ],
    );
  }

  pw.Widget _ring(double size, PdfColor color, double opacity) => pw.Opacity(
    opacity: opacity,
    child: pw.Container(
      width: size,
      height: size,
      decoration: pw.BoxDecoration(
        shape: pw.BoxShape.circle,
        border: pw.Border.all(color: color, width: size / 9),
      ),
    ),
  );

  pw.Widget _card(double k, String title, List<pw.Widget> children) =>
      pw.Container(
        padding: pw.EdgeInsets.fromLTRB(12 * k, 9 * k, 12 * k, 10 * k),
        decoration: pw.BoxDecoration(
          color: look.soft,
          borderRadius: pw.BorderRadius.circular(10 * k),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: 22 * k,
              height: 3 * k,
              margin: pw.EdgeInsets.only(bottom: 5 * k),
              decoration: pw.BoxDecoration(
                color: look.accent,
                borderRadius: pw.BorderRadius.circular(2),
              ),
            ),
            pw.Text(
              t(title.toUpperCase()),
              style: st(7.5 * k, bold: true, color: look.accent, spacing: 1.5),
            ),
            pw.SizedBox(height: 3 * k),
            ...children,
          ],
        ),
      );

  pw.Widget _infoCards(double k) {
    final st0 = stamp;
    final due = d.dueDate;
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _card(
            k,
            d.kind == ReceiptKind.livraison ? 'Livré à' : 'Client',
            [
              pw.Text(
                t(d.clientName ?? 'Client de passage'),
                style: st(11 * k, bold: true),
              ),
              if (d.clientPhone != null)
                pw.Text(t(d.clientPhone!), style: st(9 * k)),
              if (d.clientAddress != null)
                pw.Text(t(d.clientAddress!), style: st(9 * k, color: _grey)),
            ],
          ),
        ),
        pw.SizedBox(width: 10 * k),
        pw.Expanded(
          child: _card(k, 'Détails', [
            pw.Text(t('Émis le ${_dt(d.date)}'), style: st(9 * k)),
            if (due != null)
              pw.Text(
                t(
                  d.kind == ReceiptKind.devis
                      ? 'Valable jusqu’au ${_d(due)}'
                      : 'À payer avant le ${_d(due)}',
                ),
                style: st(9 * k),
              ),
            if (d.kind == ReceiptKind.proforma)
              pw.Text(
                t('Valable 15 jours, sous réserve du stock'),
                style: st(9 * k),
              ),
            if (st0 != null) ...[
              pw.SizedBox(height: 4 * k),
              pw.Container(
                padding: pw.EdgeInsets.symmetric(
                  horizontal: 8 * k,
                  vertical: 2 * k,
                ),
                decoration: pw.BoxDecoration(
                  color: st0.$2,
                  borderRadius: pw.BorderRadius.circular(8 * k),
                ),
                child: pw.Text(
                  t(st0.$1),
                  style: st(
                    8 * k,
                    bold: true,
                    color: PdfColors.white,
                    spacing: 1.5,
                  ),
                ),
              ),
            ],
          ]),
        ),
      ],
    );
  }

  pw.Widget _table(double k, bool epure) {
    final prices = d.kind.showsPrices;
    final headers = prices
        ? ['Désignation', 'Qté', 'Prix unitaire', 'Montant']
        : ['Désignation', 'Quantité', 'Contrôle'];
    final flex = prices ? [4.4, 1.5, 2.1, 2.2] : [5.0, 2.0, 1.6];
    pw.Widget cell(
      String s, {
      bool right = false,
      bool head = false,
      bool strong = false,
    }) => pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: 8 * k, vertical: 6 * k),
      child: pw.Text(
        head ? t(s.toUpperCase()) : s,
        textAlign: right ? pw.TextAlign.right : pw.TextAlign.left,
        style: head
            ? st(
                7.5 * k,
                bold: true,
                spacing: 1.2,
                color: epure ? look.accent : look.accent2,
              )
            : st(9.5 * k, bold: strong),
      ),
    );
    return pw.Table(
      columnWidths: {
        for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i]),
      },
      children: [
        pw.TableRow(
          decoration: epure
              ? pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: look.accent, width: 1.2),
                  ),
                )
              : pw.BoxDecoration(
                  gradient: pw.LinearGradient(colors: [look.dark, look.dark2]),
                  borderRadius: pw.BorderRadius.circular(8 * k),
                ),
          children: [
            for (var i = 0; i < headers.length; i++)
              cell(headers[i], head: true, right: i > 0),
          ],
        ),
        for (var i = 0; i < d.lines.length; i++)
          pw.TableRow(
            decoration: pw.BoxDecoration(
              color: i.isOdd ? look.soft : null,
              border: const pw.Border(
                bottom: pw.BorderSide(
                  color: PdfColor.fromInt(0xFFE3E8E5),
                  width: 0.5,
                ),
              ),
            ),
            children: [
              cell(t(d.lines[i].label), strong: true),
              cell(
                t('${_qty(d.lines[i].qty)} ${d.lines[i].unit}'),
                right: true,
              ),
              if (prices) ...[
                cell(money(d.lines[i].unitPrice), right: true),
                cell(money(d.lines[i].total), right: true, strong: true),
              ] else
                pw.Align(
                  alignment: pw.Alignment.centerRight,
                  child: pw.Container(
                    margin: pw.EdgeInsets.all(6 * k),
                    width: 11 * k,
                    height: 11 * k,
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: look.accent, width: 1),
                      borderRadius: pw.BorderRadius.circular(3),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  pw.Widget _totals(double k, bool epure) {
    pw.Widget line(String l, String v, {bool strong = false}) => pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: 2 * k),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(t(l), style: st(9.5 * k, bold: strong)),
          ),
          pw.Text(v, style: st(9.5 * k, bold: strong)),
        ],
      ),
    );

    final qrBlock = pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          padding: pw.EdgeInsets.all(5 * k),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: look.accent, width: 1.2),
            borderRadius: pw.BorderRadius.circular(8 * k),
          ),
          child: qr(64 * k, _ink),
        ),
        pw.SizedBox(height: 3 * k),
        pw.Text(
          t('Code de contrôle ${d.number}'),
          style: st(7 * k, color: _grey),
        ),
      ],
    );

    if (!d.kind.showsPrices) {
      return pw.Row(children: [qrBlock, pw.Spacer()]);
    }

    final totalBox = pw.Container(
      margin: pw.EdgeInsets.symmetric(vertical: 4 * k),
      padding: pw.EdgeInsets.symmetric(horizontal: 12 * k, vertical: 9 * k),
      decoration: epure
          ? pw.BoxDecoration(
              border: pw.Border.all(color: _ink, width: 1.4),
              borderRadius: pw.BorderRadius.circular(10 * k),
            )
          : pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [look.dark, look.dark2],
                begin: pw.Alignment.centerLeft,
                end: pw.Alignment.centerRight,
              ),
              borderRadius: pw.BorderRadius.circular(10 * k),
            ),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              d.taxRate > 0 ? 'TOTAL TTC' : 'TOTAL',
              style: st(
                11 * k,
                display: true,
                spacing: 2,
                color: epure ? _ink : look.accent2,
              ),
            ),
          ),
          pw.Text(
            money(d.total),
            style: st(
              18 * k,
              display: true,
              color: epure ? _ink : PdfColors.white,
            ),
          ),
        ],
      ),
    );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        qrBlock,
        pw.Spacer(),
        pw.SizedBox(
          width: 240 * k,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              if (d.discount > 0 || d.taxRate > 0)
                line('Sous-total', money(d.subtotal ?? d.total)),
              if (d.discount > 0) line('Remise', money(-d.discount)),
              if (d.taxRate > 0) ...[
                line('Total HT', money((d.subtotal ?? d.total) - d.discount)),
                line('TVA ${d.taxRate} %', money(d.tax)),
              ],
              totalBox,
              if (d.kind.showsPayments) ...[
                for (final p in d.payments)
                  line('${p.method} · ${_d(p.at)}', money(p.amount)),
                if (d.payments.isNotEmpty && d.due > 0)
                  line('Reste à payer', money(d.due), strong: true),
              ],
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _signature(double k) {
    final label = switch (d.kind) {
      ReceiptKind.devis => 'Bon pour accord (date et signature du client)',
      ReceiptKind.livraison => 'Reçu par (nom, date et signature)',
      _ => 'Cachet et signature',
    };
    return pw.Padding(
      padding: pw.EdgeInsets.only(top: 18 * k),
      child: pw.Row(
        children: [
          pw.Spacer(),
          pw.Container(
            width: 220 * k,
            height: 70 * k,
            padding: pw.EdgeInsets.all(8 * k),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                color: look.accent,
                width: 0.8,
                style: pw.BorderStyle.dashed,
              ),
              borderRadius: pw.BorderRadius.circular(10 * k),
            ),
            child: pw.Text(t(label), style: st(8 * k, color: _grey)),
          ),
        ],
      ),
    );
  }

  pw.Widget _footer(pw.Context ctx, double k) => pw.Column(
    children: [
      pw.Container(
        height: 1.4 * k,
        decoration: pw.BoxDecoration(
          gradient: pw.LinearGradient(
            colors: [look.accent2, look.accent, look.dark],
          ),
        ),
      ),
      pw.SizedBox(height: 6 * k),
      pw.Text(
        thanks,
        textAlign: pw.TextAlign.center,
        style: st(10.5 * k, display: true, color: look.accent),
      ),
      pw.SizedBox(height: 3 * k),
      pw.Text(
        t(
          '${d.number} · page ${ctx.pageNumber}/${ctx.pagesCount} · édité avec FLYFINANCE',
        ),
        style: st(7 * k, color: _grey),
      ),
    ],
  );
}
