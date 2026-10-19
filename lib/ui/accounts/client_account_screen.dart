import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/accounts_repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

/// Compte d'un client : ses achats, ses versements, sa provision et ce qu'il
/// doit encore.
class ClientAccountScreen extends StatelessWidget {
  const ClientAccountScreen(this.clientId, {super.key});
  final int clientId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Compte client'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: EyeButton()),
        ],
      ),
      body: Loader<ClientAccount>(
        load: (r) => r.clientAccount(clientId),
        builder: (context, a) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            ContactHeader(
              a.contact,
              onEdit: () async {
                if (await editContact(
                      context,
                      kind: 'client',
                      contact: a.contact,
                    ) !=
                    null) {
                  app.changed();
                }
              },
            ),
            const SizedBox(height: 12),
            Panel(
              color: a.due > 0
                  ? const Color(0xFF2A2414)
                  : const Color(0xFF18302A),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    a.due > 0 ? 'Il reste à payer' : 'Compte à jour',
                    style: TextStyle(
                      color: a.due > 0 ? Palette.amber : Palette.mint,
                    ),
                  ),
                  FittedBox(
                    child: Text(
                      app.money(a.due),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      statChip('Achats', app.money(a.bought), Palette.text),
                      const SizedBox(width: 8),
                      statChip('Versé', app.money(a.paid), Palette.mint),
                      const SizedBox(width: 8),
                      statChip(
                        'Provision',
                        app.money(a.provision),
                        Palette.blue,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (a.provision > 0 && a.due > 0) ...[
              const SizedBox(height: 12),
              Material(
                color: const Color(0xFF1B2A3A),
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: const Icon(
                    Icons.savings_outlined,
                    color: Palette.blue,
                  ),
                  title: Text(
                    'Régler ${app.money(a.provision < a.due ? a.provision : a.due)} avec sa provision',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Palette.blue,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Palette.blue,
                  ),
                  onTap: () => _useProvision(context, app),
                ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: a.due > 0 ? () => _pay(context, app, a) : null,
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('Versement'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(48, 54),
                    ),
                    onPressed: () => _provision(context, app),
                    icon: const Icon(Icons.savings_outlined),
                    label: const Text('Provision'),
                  ),
                ),
              ],
            ),
            if (a.due > 0) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _remind(context, app, a),
                icon: const Icon(Icons.notifications_active_outlined, size: 18),
                label: const Text('Envoyer un rappel'),
              ),
            ],
            if (a.provision > 0 && a.due == 0) ...[
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () => _giveBack(context, app, a),
                child: const Text('Rendre la provision'),
              ),
            ],
            sectionTitle('Mouvements (${a.moves.length})'),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: a.moves.isEmpty
                  ? const EmptyState('Aucun mouvement pour l’instant.')
                  : Column(
                      children: [
                        for (final m in a.moves)
                          MoveTile(
                            m,
                            onTap:
                                m.entry != null &&
                                    !m.cancelled &&
                                    m.entry!.kind != 'utilisee'
                                ? () => _cancel(context, app, m)
                                : null,
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pay(BuildContext context, AppState app, ClientAccount a) async {
    final v = await askMoney(
      context,
      title: 'Versement de ${a.contact.name}',
      action: 'Encaisser',
      initial: a.due,
      withDate: false,
    );
    if (v == null) return;
    final applied = await app.repo.receivePayment(
      clientId,
      v.amount,
      method: v.method,
    );
    final extra = v.amount - applied;
    // Ce qui dépasse la dette devient une provision, rien ne se perd.
    if (extra > 0) {
      await app.repo.addProvision(
        clientId,
        extra,
        method: v.method,
        note: 'Reste d’un versement',
      );
    }
    app.changed();
    if (context.mounted) {
      toast(
        context,
        extra > 0
            ? '${fcfa(applied)} encaissés, ${fcfa(extra)} mis en provision.'
            : '${fcfa(applied)} encaissés.',
      );
    }
  }

  Future<void> _provision(BuildContext context, AppState app) async {
    final v = await askMoney(
      context,
      title: 'Provision déposée',
      action: 'Enregistrer',
    );
    if (v == null) return;
    await app.repo.addProvision(
      clientId,
      v.amount,
      method: v.method,
      at: v.at,
      note: v.note,
    );
    app.changed();
    if (context.mounted) toast(context, '${fcfa(v.amount)} en provision.');
  }

  Future<void> _useProvision(BuildContext context, AppState app) async {
    final used = await app.repo.useProvision(clientId);
    app.changed();
    if (context.mounted) {
      toast(context, '${fcfa(used)} réglés avec la provision.');
    }
  }

  Future<void> _giveBack(
    BuildContext context,
    AppState app,
    ClientAccount a,
  ) async {
    final n = await askNumber(
      context,
      title: 'Montant rendu à ${a.contact.name}',
      initial: a.provision,
    );
    if (n == null || n <= 0) return;
    try {
      await app.repo.returnProvision(clientId, n);
      app.changed();
    } on StateError catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }

  Future<void> _remind(
    BuildContext context,
    AppState app,
    ClientAccount a,
  ) async {
    final s = await app.repo.reminderSettings();
    if (!context.mounted) return;
    if (await openWhatsApp(
      context,
      a.contact.phone,
      s.messageFor(a.contact.name, fcfa(a.due)),
    )) {
      await app.repo.markReminded(clientId);
      app.changed();
    }
  }

  Future<void> _cancel(
    BuildContext context,
    AppState app,
    AccountMove m,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: Text('Annuler « ${m.title} » ?'),
        content: Text(
          '${fcfa(m.amount)} du ${shortDate(m.at)}. Le mouvement reste visible, barré.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oui, annuler'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await app.repo.cancelEntry(m.entry!.id);
      app.changed();
    } on StateError catch (e) {
      if (context.mounted) toast(context, e.message);
    }
  }
}
