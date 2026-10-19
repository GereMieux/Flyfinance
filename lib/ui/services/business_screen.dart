import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/services_repository.dart';
import '../widgets.dart';

/// Fiche de l'entreprise, imprimée en tête des devis et factures.
class BusinessScreen extends StatefulWidget {
  const BusinessScreen({super.key});
  @override
  State<BusinessScreen> createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> {
  final _c = {for (final k in businessFields.keys) k: TextEditingController()};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    context.read<AppState>().repo.businessInfo().then((info) {
      if (!mounted) return;
      for (final e in info.entries) {
        _c[e.key]?.text = e.value;
      }
      setState(() => _loaded = true);
    });
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    await app.repo.saveBusinessInfo({
      for (final e in _c.entries) e.key: e.value.text,
    });
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
                const Text(
                  'Ces informations apparaissent en haut de vos devis et '
                  'factures.',
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
}
