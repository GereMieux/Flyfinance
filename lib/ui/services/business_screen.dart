import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/receipt_repository.dart';
import '../../data/services_repository.dart';
import '../../services/receipt_pdf.dart';
import '../receipt_screen.dart';
import '../theme.dart';
import '../widgets.dart';

/// Fiche de l'entreprise, imprimée en tête des reçus, devis et factures,
/// avec le logo, le modèle préféré et la phrase de fin des tickets.
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});
  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  final _c = {for (final k in businessFields.keys) k: TextEditingController()};
  final _thanks = TextEditingController();
  Uint8List? _logo;
  ReceiptStyle _style = ReceiptStyle.neon;
  PaperSize _paper = PaperSize.ticket80;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final repo = context.read<AppState>().repo;
    Future.wait([repo.businessInfo(), repo.brand()]).then((r) {
      if (!mounted) return;
      final info = r[0] as Map<String, String>;
      final brand = r[1] as BrandSettings;
      for (final e in info.entries) {
        _c[e.key]?.text = e.value;
      }
      _thanks.text = brand.thanks ?? '';
      setState(() {
        _logo = brand.logo;
        _style = brand.style;
        _paper = brand.paper;
        _loaded = true;
      });
    });
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    _thanks.dispose();
    super.dispose();
  }

  BrandSettings get _brand => BrandSettings(
    logo: _logo,
    style: _style,
    paper: _paper,
    thanks: _thanks.text,
  );

  Future<void> _pickLogo() async {
    // Image réduite : le logo reste léger dans la base et sur les tickets.
    final f = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 600,
      maxHeight: 600,
      imageQuality: 90,
    );
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (mounted) setState(() => _logo = bytes);
  }

  void _preview() {
    final biz = {for (final e in _c.entries) e.key: e.value.text};
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReceiptScreen.sample(
          brand: _brand,
          data: sampleReceipt(),
          biz: biz,
        ),
      ),
    );
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    await app.repo.saveBusinessInfo({
      for (final e in _c.entries) e.key: e.value.text,
    });
    await app.repo.saveBrand(
      logo: _logo,
      style: _style,
      paper: _paper,
      thanks: _thanks.text,
    );
    app.changed();
    if (mounted) {
      toast(context, 'Fiche enregistrée.');
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Mon entreprise')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                _brandPanel(),
                const SizedBox(height: 18),
                const SectionTitle('Coordonnées'),
                const SizedBox(height: 6),
                const Text(
                  'Ces informations apparaissent en haut de vos reçus, devis '
                  'et factures.',
                ),
                const SizedBox(height: 12),
                for (final e in businessFields.entries)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: _c[e.key],
                      maxLines: e.key == 'biz.terms' ? 3 : 1,
                      minLines: 1,
                      keyboardType: switch (e.key) {
                        'biz.phone' => TextInputType.phone,
                        'biz.email' => TextInputType.emailAddress,
                        _ => TextInputType.text,
                      },
                      textCapitalization: e.key == 'biz.email'
                          ? TextCapitalization.none
                          : TextCapitalization.sentences,
                      decoration: InputDecoration(labelText: e.value),
                    ),
                  ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton(
            onPressed: _loaded ? _save : null,
            child: const Text('Enregistrer'),
          ),
        ),
      ),
    );
  }

  Widget _choice<T>(
    List<T> values,
    T selected,
    String Function(T) label,
    void Function(T) pick,
  ) => Wrap(
    spacing: 8,
    runSpacing: 6,
    children: [
      for (final v in values)
        ChoiceChip(
          label: Text(label(v)),
          selected: v == selected,
          onSelected: (_) => setState(() => pick(v)),
        ),
    ],
  );

  Widget _brandPanel() => Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            InkWell(
              onTap: _pickLogo,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                width: 76,
                height: 76,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Palette.mint, width: 1.5),
                ),
                child: _logo == null
                    ? Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 32,
                        color: Palette.green,
                      )
                    : Image.memory(_logo!, fit: BoxFit.contain),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Logo de l’entreprise',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Imprimé en haut des reçus et factures.',
                    style: TextStyle(color: Palette.muted),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: _pickLogo,
                        child: Text(_logo == null ? 'Choisir' : 'Changer'),
                      ),
                      if (_logo != null)
                        TextButton(
                          onPressed: () => setState(() => _logo = null),
                          child: const Text('Retirer'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Modèle', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        _choice(ReceiptStyle.values, _style, (s) => s.label, (s) => _style = s),
        const SizedBox(height: 12),
        const Text(
          'Papier du reçu de caisse',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        _choice(PaperSize.values, _paper, (p) => p.label, (p) => _paper = p),
        const SizedBox(height: 14),
        TextField(
          controller: _thanks,
          maxLines: 2,
          minLines: 1,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Phrase en bas du ticket',
            helperText: 'Vide : une phrase différente à chaque ticket.',
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final t in thanksIdeas)
              ActionChip(
                label: Text(t.length > 34 ? '${t.substring(0, 32)}…' : t),
                onPressed: () => setState(() => _thanks.text = t),
              ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: _preview,
          icon: const Icon(Icons.visibility_outlined),
          label: const Text('Voir un exemple'),
        ),
      ],
    ),
  );
}
