import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/database.dart';
import '../../data/services_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

/// Catalogue des prestations, réutilisées dans les devis et factures.
class CatalogueScreen extends StatelessWidget {
  const CatalogueScreen({super.key});

  Future<void> _edit(BuildContext context, [Service? s]) async {
    final repo = context.read<AppState>().repo;
    final name = TextEditingController(text: s?.name ?? '');
    final price = TextEditingController(text: s == null ? '' : '${s.price}');
    var unit = s?.unit ?? 'forfait';
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: Palette.card,
          title: Text(s == null ? 'Nouvelle prestation' : 'Modifier'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                autofocus: s == null,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Nom (ex. Installation climatiseur)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Prix',
                  suffixText: 'FCFA',
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final u in serviceUnits)
                    ChoiceChip(
                      label: Text(u),
                      selected: unit == u,
                      onSelected: (_) => set(() => unit = u),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            if (s != null)
              TextButton(
                onPressed: () async {
                  await repo.archiveService(s.id);
                  if (ctx.mounted) Navigator.pop(ctx, true);
                },
                child: const Text(
                  'Retirer',
                  style: TextStyle(color: Palette.red),
                ),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Valider'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final p = int.tryParse(price.text.replaceAll(RegExp(r'[^0-9]'), ''));
    if (name.text.trim().isEmpty || p == null) {
      context.read<AppState>().changed();
      return;
    }
    await guarded(
      context,
      () => s == null
          ? repo.addService(name: name.text, price: p, unit: unit)
          : repo.updateService(s.id, name: name.text, price: p, unit: unit),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Mes prestations')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Palette.green,
        foregroundColor: Palette.text,
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
      body: Loader<List<Service>>(
        load: (r) => r.services(),
        builder: (context, list) => list.isEmpty
            ? const EmptyState(
                'Ajoutez les prestations que vous proposez, avec leur prix. '
                'Vous les choisirez ensuite en un geste dans vos devis et '
                'factures.',
                icon: Icons.handyman_outlined,
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) => Material(
                  color: Palette.card,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: const Icon(Icons.handyman_outlined),
                    title: Text(
                      list[i].name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: Text(
                      '${app.money(list[i].price)} / ${list[i].unit}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onTap: () => _edit(context, list[i]),
                  ),
                ),
              ),
      ),
    );
  }
}
