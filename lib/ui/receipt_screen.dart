import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/receipt_repository.dart';
import '../data/services_repository.dart';
import '../services/receipt_pdf.dart';
import 'theme.dart';
import 'widgets.dart';

class _ReceiptLoad {
  _ReceiptLoad(this.data, this.biz, this.brand);
  final ReceiptData data;
  final Map<String, String> biz;
  final BrandSettings brand;
}

/// Aperçu d'un reçu ou d'une facture de vente : choix du document, du
/// modèle et du papier, puis impression ou partage.
class ReceiptScreen extends StatelessWidget {
  const ReceiptScreen({super.key, required this.saleId, this.justSold = false})
    : sample = null,
      sampleBrand = null,
      sampleBiz = null;

  /// Exemple fictif pour essayer un modèle depuis « Mon entreprise ».
  const ReceiptScreen.sample({
    super.key,
    required BrandSettings brand,
    required ReceiptData data,
    required Map<String, String> biz,
  }) : saleId = null,
       justSold = false,
       sample = data,
       sampleBrand = brand,
       sampleBiz = biz;

  final int? saleId;
  final bool justSold;
  final ReceiptData? sample;
  final BrandSettings? sampleBrand;
  final Map<String, String>? sampleBiz;

  @override
  Widget build(BuildContext context) => Loader<_ReceiptLoad>(
    load: (r) async => _ReceiptLoad(
      sample ?? await r.saleReceipt(saleId!),
      sampleBiz ?? await r.businessInfo(),
      sampleBrand ?? await r.brand(),
    ),
    builder: (context, l) => _ReceiptView(l, justSold: justSold),
  );
}

class _ReceiptView extends StatefulWidget {
  const _ReceiptView(this.l, {required this.justSold});
  final _ReceiptLoad l;
  final bool justSold;
  @override
  State<_ReceiptView> createState() => _ReceiptViewState();
}

class _ReceiptViewState extends State<_ReceiptView> {
  late ReceiptKind _kind = widget.l.data.kind;
  late ReceiptStyle _style = widget.l.brand.style;
  late PaperSize _paper = widget.l.brand.paper;

  ReceiptData get _data => widget.l.data.as(_kind);
  BrandSettings get _brand => BrandSettings(
    logo: widget.l.brand.logo,
    style: _style,
    paper: _paper,
    thanks: widget.l.brand.thanks,
  );
  String get _file => '${_kind.short} ${_data.number}.pdf';

  Future<void> _print() => Printing.layoutPdf(
    name: _file,
    format: switch (_paper) {
      PaperSize.ticket58 => PdfPageFormat.roll57,
      PaperSize.ticket80 => PdfPageFormat.roll80,
      PaperSize.a5 => PdfPageFormat.a5,
      PaperSize.a4 => PdfPageFormat.a4,
    },
    onLayout: (_) async =>
        buildReceiptPdf(_data, widget.l.biz, _brand, paper: _paper),
  );

  Future<void> _share() async => Printing.sharePdf(
    bytes: await buildReceiptPdf(_data, widget.l.biz, _brand, paper: _paper),
    filename: _file,
  );

  Widget _chips<T>(
    List<T> values,
    T selected,
    String Function(T) label,
    void Function(T) onPick,
  ) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Row(
      children: [
        for (final v in values)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(label(v)),
              selected: v == selected,
              onSelected: (_) => setState(() => onPick(v)),
            ),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final d = widget.l.data;
    final kinds = d.kind == ReceiptKind.devis || d.kind == ReceiptKind.facture
        ? [d.kind]
        : const [
            ReceiptKind.recu,
            ReceiptKind.facture,
            ReceiptKind.proforma,
            ReceiptKind.livraison,
          ];
    return Scaffold(
      appBar: AppBar(title: Text('${_kind.short} ${d.number}')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.justSold)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Palette.mintSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Palette.mint),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Vente enregistrée · ${app.money(d.total)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          if (kinds.length > 1) ...[
            _chips(kinds, _kind, (k) => k.short, (k) => _kind = k),
            const SizedBox(height: 4),
          ],
          _chips(
            ReceiptStyle.values,
            _style,
            (s) => s.label,
            (s) => _style = s,
          ),
          const SizedBox(height: 4),
          _chips(PaperSize.values, _paper, (p) => p.label, (p) => _paper = p),
          const SizedBox(height: 8),
          Expanded(
            child: PdfPreview(
              key: ValueKey('$_kind$_style$_paper'),
              build: (_) async =>
                  buildReceiptPdf(_data, widget.l.biz, _brand, paper: _paper),
              useActions: false,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              maxPageWidth: _paper.isTicket ? 340 : 700,
              pdfFileName: _file,
              loadingWidget: const Center(child: CircularProgressIndicator()),
              onError: (context, e) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Aperçu indisponible sur cet appareil. Vous pouvez quand '
                    'même imprimer ou partager.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Palette.muted),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _share,
                  icon: const Icon(Icons.share_outlined),
                  label: const Text('Partager'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _print,
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('Imprimer'),
                ),
              ),
              if (widget.justSold) ...[
                const SizedBox(width: 10),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Terminer'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Vente fictive pour essayer un modèle.
ReceiptData sampleReceipt() => ReceiptData(
  kind: ReceiptKind.recu,
  number: ReceiptData.saleNumber(128),
  date: DateTime.now(),
  clientName: 'Awa Traoré',
  clientPhone: '07 00 00 00 00',
  lines: const [
    ReceiptLine('Riz parfumé 25 kg', 2, 'sac', 15000),
    ReceiptLine('Huile 5 L', 1, 'bidon', 6000),
    ReceiptLine('Sucre en morceaux', 3, 'paquet', 1200),
  ],
  total: 39600,
  payments: [ReceiptPayment('Wave', 25000, DateTime.now())],
);
