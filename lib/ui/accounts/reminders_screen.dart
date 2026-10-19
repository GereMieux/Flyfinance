import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/accounts_repository.dart';
import '../../data/repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

class _Data {
  _Data(this.settings, this.due, this.debtors, this.last);
  final ReminderSettings settings;
  final List<ReminderDue> due;
  final List<Debtor> debtors;
  final Map<int, DateTime> last;
}

/// Relances des clients qui doivent de l'argent : délai, heure et message
/// réglables ; les clients à relancer apparaissent chaque jour à l'heure
/// choisie.
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  Future<_Data> _load(Repository r) async => _Data(
    await r.reminderSettings(),
    await r.remindersDue(),
    await r.debtors(),
    await r.lastReminders(),
  );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Relances')),
      body: Loader<_Data>(
        load: _load,
        builder: (context, d) {
          final s = d.settings;
          final dueIds = {for (final r in d.due) r.debtor.contact.id};
          final later = d.debtors
              .where((x) => !dueIds.contains(x.contact.id))
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              TilesPanel(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Relances automatiques',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        s.enabled
                            ? 'Chaque jour à ${_hm(s.hour, s.minute)}, les clients à relancer sont prêts.'
                            : 'Désactivées',
                        style: TextStyle(color: Palette.muted),
                      ),
                      value: s.enabled,
                      onChanged: (v) => _save(app, _copy(s, enabled: v)),
                    ),
                    _setting(
                      'Relancer après',
                      '${s.afterDays} jour${s.afterDays > 1 ? 's' : ''} de dette',
                      () async {
                        final n = await askNumber(
                          context,
                          title: 'Relancer après combien de jours ?',
                          initial: s.afterDays,
                        );
                        if (n != null) _save(app, _copy(s, afterDays: n));
                      },
                    ),
                    _setting(
                      'Puis relancer tous les',
                      '${s.everyDays} jour${s.everyDays > 1 ? 's' : ''}',
                      () async {
                        final n = await askNumber(
                          context,
                          title:
                              'Relancer de nouveau tous les combien de jours ?',
                          initial: s.everyDays,
                        );
                        if (n != null && n > 0) {
                          _save(app, _copy(s, everyDays: n));
                        }
                      },
                    ),
                    _setting('À partir de', _hm(s.hour, s.minute), () async {
                      final t = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay(hour: s.hour, minute: s.minute),
                      );
                      if (t != null) {
                        _save(app, _copy(s, hour: t.hour, minute: t.minute));
                      }
                    }),
                    _setting(
                      'Message',
                      s.messageFor('Fatou', fcfa(15000)),
                      () => _editMessage(context, app, s),
                    ),
                  ],
                ),
              ),
              sectionTitle('À relancer maintenant (${d.due.length})'),
              if (d.due.isEmpty)
                EmptyState(
                  !s.enabled
                      ? 'Les relances sont désactivées.'
                      : d.debtors.isEmpty
                      ? 'Personne ne vous doit d’argent.'
                      : 'Personne à relancer pour l’instant.',
                  icon: Icons.thumb_up_alt_outlined,
                ),
              for (final r in d.due)
                _tile(context, app, s, r.debtor, r.lastReminder, now: true),
              if (later.isNotEmpty) ...[
                sectionTitle('Plus tard (${later.length})'),
                for (final x in later)
                  _tile(context, app, s, x, d.last[x.contact.id], now: false),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _tile(
    BuildContext context,
    AppState app,
    ReminderSettings s,
    Debtor d,
    DateTime? last, {
    required bool now,
  }) {
    final days = app.repo.now().difference(d.oldest).inDays;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
        child: Row(
          children: [
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
                    '${app.money(d.due)} · depuis $days jour${days > 1 ? 's' : ''}',
                    style: TextStyle(color: Palette.amber),
                  ),
                  Text(
                    last == null
                        ? 'Jamais relancé'
                        : 'Relancé le ${shortDate(last)}',
                    style: TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            now
                ? FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 46),
                    ),
                    onPressed: () => _send(context, app, s, d),
                    icon: const Icon(Icons.send, size: 18),
                    label: const Text('Relancer'),
                  )
                : OutlinedButton(
                    onPressed: () => _send(context, app, s, d),
                    child: const Text('Relancer'),
                  ),
          ],
        ),
      ),
    );
  }

  Future<void> _send(
    BuildContext context,
    AppState app,
    ReminderSettings s,
    Debtor d,
  ) async {
    if (await openWhatsApp(
      context,
      d.contact.phone,
      s.messageFor(d.contact.name, fcfa(d.due)),
    )) {
      await app.repo.markReminded(d.contact.id);
      app.changed();
    }
  }

  Widget _setting(String label, String value, VoidCallback onTap) => ListTile(
    contentPadding: const EdgeInsets.only(right: 4),
    title: Text(label, style: TextStyle(color: Palette.muted)),
    subtitle: Text(
      value,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontWeight: FontWeight.w700, color: Palette.text),
    ),
    trailing: const Icon(Icons.edit_outlined, size: 20),
    onTap: onTap,
  );

  Future<void> _editMessage(
    BuildContext context,
    AppState app,
    ReminderSettings s,
  ) async {
    final c = TextEditingController(text: s.message);
    final v = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Message de rappel'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: c,
              maxLines: 5,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 8),
            Text(
              '{nom} devient le nom du client, {montant} ce qu’il doit.',
              style: TextStyle(color: Palette.muted, fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, ReminderSettings.defaultReminderMessage),
            child: const Text('Par défaut'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (v != null) await _save(app, _copy(s, message: v));
  }

  Future<void> _save(AppState app, ReminderSettings s) async {
    await app.repo.saveReminderSettings(s);
    app.changed();
  }
}

ReminderSettings _copy(
  ReminderSettings s, {
  bool? enabled,
  int? afterDays,
  int? everyDays,
  int? hour,
  int? minute,
  String? message,
}) => ReminderSettings(
  enabled: enabled ?? s.enabled,
  afterDays: afterDays ?? s.afterDays,
  everyDays: everyDays ?? s.everyDays,
  hour: hour ?? s.hour,
  minute: minute ?? s.minute,
  message: message ?? s.message,
);

String _hm(int h, int m) =>
    '${h.toString().padLeft(2, '0')} h ${m.toString().padLeft(2, '0')}';
