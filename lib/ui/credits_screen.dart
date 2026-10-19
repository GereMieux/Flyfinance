import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/accounts_repository.dart';
import '../data/repository.dart';
import 'accounts/client_account_screen.dart';
import 'accounts/common.dart';
import 'theme.dart';
import 'widgets.dart';

class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key, this.embedded = false});
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !embedded,
        title: const Text('Crédits clients'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: EyeButton()),
        ],
      ),
      body: Loader<List<Debtor>>(
        load: (r) => r.debtors(),
        builder: (context, list) {
          final total = list.fold<int>(0, (a, d) => a + d.due);
          final late = list
              .where((d) => app.repo.now().difference(d.oldest).inDays > 30)
              .length;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Panel(
                color: const Color(0xFF2A2414),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'On vous doit au total',
                      style: TextStyle(color: Palette.amber),
                    ),
                    FittedBox(
                      child: Text(
                        app.money(total),
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${list.length} client${list.length > 1 ? 's' : ''}'
                      '${late > 0 ? ' · $late en retard de plus de 30 jours' : ''}',
                      style: const TextStyle(color: Palette.amber),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const EmptyState(
                  'Personne ne vous doit d’argent.',
                  icon: Icons.thumb_up_alt_outlined,
                ),
              for (final d in list) _DebtorCard(d),
            ],
          );
        },
      ),
    );
  }
}

class _DebtorCard extends StatelessWidget {
  const _DebtorCard(this.d);
  final Debtor d;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final days = app.repo.now().difference(d.oldest).inDays;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ClientAccountScreen(d.contact.id),
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: const Color(0xFF1F3A2F),
                    child: Text(
                      d.contact.name.characters.first.toUpperCase(),
                      style: const TextStyle(
                        color: Palette.mint,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d.contact.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Depuis $days jour${days > 1 ? 's' : ''}',
                          style: TextStyle(
                            color: days > 30 ? Palette.red : Palette.muted,
                            fontWeight: days > 30 ? FontWeight.w700 : null,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    app.money(d.due),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _remind(context, app),
                    icon: const Icon(Icons.chat_outlined, size: 18),
                    label: const Text('Rappeler'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 48),
                    ),
                    onPressed: () => _receive(context, app),
                    child: const Text('Encaisser'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Ouvre WhatsApp avec le message de rappel choisi dans Relances. Rien
  /// n'est envoyé sans que le commerçant appuie lui-même sur Envoyer.
  Future<void> _remind(BuildContext context, AppState app) async {
    final s = await app.repo.reminderSettings();
    if (!context.mounted) return;
    if (await openWhatsApp(
      context,
      d.contact.phone,
      s.messageFor(d.contact.name, fcfa(d.due)),
    )) {
      await app.repo.markReminded(d.contact.id);
      app.changed();
    }
  }

  Future<void> _receive(BuildContext context, AppState app) async {
    final amount = await askNumber(
      context,
      title: 'Montant reçu de ${d.contact.name}',
      initial: d.due,
    );
    if (amount == null || amount <= 0) return;
    final applied = await app.repo.receivePayment(d.contact.id, amount);
    app.changed();
    if (context.mounted) toast(context, '${fcfa(applied)} encaissés.');
  }
}
