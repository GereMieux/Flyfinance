import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/database.dart';
import '../../data/management_repository.dart';
import '../accounts/common.dart';
import '../services/common.dart' show guarded;
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

/// Vendeurs de la boutique : chacun a son code, et ses ventes sont
/// enregistrées à son nom.
class SellersScreen extends StatelessWidget {
  const SellersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Vendeurs')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Vendeur'),
      ),
      body: Loader<List<Seller>>(
        load: (r) => r.sellers(),
        builder: (context, list) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                'Chaque vendeur a son code de 4 à 6 chiffres. Avant de vendre, '
                'on choisit qui vend : ses ventes sont enregistrées à son nom '
                'et apparaissent dans les rapports.',
                style: TextStyle(color: Palette.muted),
              ),
            ),
            Panel(
              color: Palette.mintSoft,
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined, color: Palette.mint),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'À la caisse maintenant : '
                      '${app.seller?.name ?? 'le propriétaire'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => chooseSeller(context),
                    child: const Text('Changer'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const EmptyState(
                'Aucun vendeur pour l’instant.',
                icon: Icons.badge_outlined,
              ),
            if (list.isNotEmpty)
              TilesPanel(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final s in list)
                      ListTile(
                        leading: IconBubble(Icons.person_outline, Palette.blue),
                        title: Text(
                          s.name,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        trailing: TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: Palette.red,
                          ),
                          onPressed: () => _remove(context, s),
                          child: const Text('Retirer'),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _add(BuildContext context) async {
    final repo = context.read<AppState>().repo;
    final name = TextEditingController();
    final a = TextEditingController();
    final b = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Nouveau vendeur'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nom du vendeur'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: a,
              obscureText: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Code (4 à 6 chiffres)',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: b,
              obscureText: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Confirmer le code',
                counterText: '',
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
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (a.text != b.text) {
      toast(context, 'Les deux codes ne correspondent pas.', error: true);
      return;
    }
    final id = await guarded(context, () => repo.addSeller(name.text, a.text));
    if (id != null && context.mounted) {
      toast(context, 'Vendeur ajouté : ${name.text.trim()}');
    }
  }

  Future<void> _remove(BuildContext context, Seller s) async {
    final app = context.read<AppState>();
    if (!await askOwnerPin(
      context,
      title: 'Retirer ${s.name} ?',
      text: 'Ses ventes passées restent enregistrées à son nom.',
      action: 'Retirer',
    )) {
      return;
    }
    if (!context.mounted) return;
    await guarded(context, () => app.repo.removeSeller(s.id));
    if (app.seller?.id == s.id) app.setSeller(null);
  }
}

/// « Qui vend ? » : le vendeur tape son code, le propriétaire le code secret.
Future<void> chooseSeller(BuildContext context) async {
  final app = context.read<AppState>();
  final list = await app.repo.sellers();
  if (!context.mounted) return;
  final pick = await showModalBottomSheet<Object>(
    context: context,
    backgroundColor: Palette.card,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Qui vend ?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
          ),
          ListTile(
            leading: IconBubble(
              Icons.workspace_premium_outlined,
              Palette.amber,
            ),
            title: const Text('Propriétaire'),
            onTap: () => Navigator.pop(ctx, 'owner'),
          ),
          for (final s in list)
            ListTile(
              leading: IconBubble(Icons.person_outline, Palette.blue),
              title: Text(s.name),
              onTap: () => Navigator.pop(ctx, s),
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (pick == null || !context.mounted) return;
  if (pick == 'owner') {
    if (app.seller == null) return;
    if (await askOwnerPin(
      context,
      title: 'Propriétaire',
      text: 'Tapez votre code secret pour reprendre la caisse.',
    )) {
      app.setSeller(null);
    }
    return;
  }
  final s = pick as Seller;
  final pin = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Palette.card,
      title: Text('Code de ${s.name}'),
      content: TextField(
        controller: pin,
        autofocus: true,
        obscureText: true,
        maxLength: 6,
        keyboardType: TextInputType.number,
        onSubmitted: (t) => Navigator.pop(ctx, t),
        decoration: const InputDecoration(counterText: ''),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, pin.text),
          child: const Text('Valider'),
        ),
      ],
    ),
  );
  if (code == null || !context.mounted) return;
  if (await app.repo.checkSellerPin(s, code)) {
    app.setSeller(s);
    if (context.mounted) toast(context, 'Vendeur : ${s.name}');
  } else if (context.mounted) {
    toast(context, 'Code incorrect.', error: true);
  }
}
