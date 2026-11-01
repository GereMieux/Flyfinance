import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/database.dart';
import '../../data/management_repository.dart';
import '../../data/repository.dart';
import '../../data/services_repository.dart';
import '../accounts/common.dart';
import '../services/common.dart' show guarded;
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

class _CashData {
  _CashData(
    this.result,
    this.situation,
    this.journal,
    this.opening,
    this.closings,
    this.months,
  );
  final MonthResult result;
  final Situation situation;
  final List<CashEntry> journal;
  final int opening;
  final List<CashClosing> closings;
  final List<DateTime> months;
}

/// Caisse et comptabilité : tout est calculé à partir des ventes, achats,
/// paiements et dépenses. Rien à saisir ici, sauf la clôture du soir.
class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  late DateTime _month;

  @override
  void initState() {
    super.initState();
    final t = context.read<AppState>().repo.now();
    _month = DateTime(t.year, t.month);
  }

  Future<_CashData> _load(Repository r) async {
    final next = DateTime(_month.year, _month.month + 1);
    final journal = await r.cashJournal();
    final t = r.now();
    final first = journal.isEmpty ? t : journal.first.at;
    final months = <DateTime>[];
    for (
      var m = DateTime(t.year, t.month);
      !m.isBefore(DateTime(first.year, first.month)) && months.length < 24;
      m = DateTime(m.year, m.month - 1)
    ) {
      months.add(m);
    }
    return _CashData(
      await r.result(_month, next),
      await r.situation(),
      journal,
      await r.openingCash(),
      await r.closings(),
      months,
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caisse et comptabilité'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: EyeButton()),
        ],
      ),
      body: Loader<_CashData>(
        key: ValueKey(_month),
        load: _load,
        builder: (context, d) {
          final next = DateTime(_month.year, _month.month + 1);
          var balance = d.opening;
          final withBalance = <(CashEntry, int)>[];
          for (final e in d.journal) {
            balance += e.amount;
            withBalance.add((e, balance));
          }
          final rows = withBalance
              .where((x) => !x.$1.at.isBefore(_month) && x.$1.at.isBefore(next))
              .toList()
              .reversed
              .toList();
          final ins = rows
              .where((x) => x.$1.amount > 0)
              .fold<int>(0, (s, x) => s + x.$1.amount);
          final outs = -rows
              .where((x) => x.$1.amount < 0)
              .fold<int>(0, (s, x) => s + x.$1.amount);
          final r = d.result;
          final s = d.situation;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Panel(
                color: Palette.mintSoft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Argent en caisse',
                      style: TextStyle(color: Palette.mint),
                    ),
                    Text(
                      app.money(s.cash),
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabular,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            icon: const Icon(Icons.calculate_outlined),
                            label: const Text('Clôturer'),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const CloseCashScreen(),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.send_outlined),
                            label: const Text('Rapport'),
                            onPressed: () => sendDailyReport(context),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              sectionTitle('Situation aujourd’hui'),
              Panel(
                child: Column(
                  children: [
                    AmountLine('Argent en caisse', s.cash, strong: true),
                    AmountLine(
                      'Les clients me doivent',
                      s.clientsOwe,
                      color: Palette.mint,
                    ),
                    AmountLine(
                      'Je dois aux fournisseurs',
                      -s.iOwe,
                      color: Palette.red,
                    ),
                    AmountLine('Valeur du stock (prix d’achat)', s.stockValue),
                    const Divider(),
                    AmountLine(
                      'Valeur nette de la boutique',
                      s.netValue,
                      strong: true,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Résultat du mois',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    DropdownButton<DateTime>(
                      value: _month,
                      underline: const SizedBox(),
                      items: [
                        for (final m in d.months)
                          DropdownMenuItem(
                            value: m,
                            child: Text(monthLabel(m)),
                          ),
                      ],
                      onChanged: (m) => setState(() => _month = m!),
                    ),
                  ],
                ),
              ),
              Panel(
                child: Column(
                  children: [
                    AmountLine('Chiffre d’affaires (ventes)', r.revenue),
                    AmountLine('Coût des marchandises vendues', -r.cost),
                    AmountLine('Marge brute', r.margin, strong: true),
                    AmountLine('Dépenses (loyer, transport…)', -r.expenses),
                    const Divider(),
                    AmountLine(
                      'Bénéfice net',
                      r.net,
                      strong: true,
                      color: r.net < 0 ? Palette.red : Palette.mint,
                    ),
                  ],
                ),
              ),
              sectionTitle('Journal de caisse'),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Entrées ${app.money(ins)} · Sorties ${app.money(outs)}',
                  style: TextStyle(color: Palette.muted),
                ),
              ),
              TilesPanel(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    if (rows.isEmpty)
                      const EmptyState(
                        'Aucun mouvement d’argent ce mois-ci.',
                        icon: Icons.account_balance_wallet_outlined,
                      ),
                    for (final x in rows)
                      ListTile(
                        dense: true,
                        title: Text(
                          x.$1.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${dayOnly(x.$1.at)} · ${x.$1.category} · '
                          'solde ${app.money(x.$2)}',
                        ),
                        trailing: Text(
                          '${x.$1.amount > 0 ? '+' : ''}${app.money(x.$1.amount)}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontFeatures: tabular,
                            color: x.$1.amount < 0 ? Palette.red : Palette.mint,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              sectionTitle('Clôtures de caisse'),
              TilesPanel(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    if (d.closings.isEmpty)
                      const EmptyState(
                        'Chaque soir, comptez votre argent : l’application '
                        'vous dit s’il manque quelque chose.',
                        icon: Icons.calculate_outlined,
                      ),
                    for (final c in d.closings)
                      ListTile(
                        dense: true,
                        title: Text(
                          shortDate(c.createdAt),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          'Attendu ${app.money(c.expected)} · compté '
                          '${app.money(c.counted)}'
                          '${c.seller == null ? '' : ' · ${c.seller}'}'
                          '${c.note == null ? '' : ' · ${c.note}'}',
                        ),
                        trailing: _gap(app, c.counted - c.expected),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: Text(
                  'Argent en caisse au départ : ${app.money(d.opening)}',
                ),
                onPressed: () async {
                  final v = await askNumber(
                    context,
                    title: 'Argent en caisse au départ',
                    hint: 'Ce que vous aviez avant d’utiliser l’application',
                    initial: d.opening,
                  );
                  if (v == null || !context.mounted) return;
                  await guarded(context, () => app.repo.setOpeningCash(v));
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _gap(AppState app, int gap) => Text(
    gap == 0 ? 'Juste' : '${gap > 0 ? '+' : ''}${app.money(gap)}',
    style: TextStyle(
      fontWeight: FontWeight.w700,
      color: gap == 0
          ? Palette.mint
          : gap < 0
          ? Palette.red
          : Palette.amber,
    ),
  );
}

/// Ouvre WhatsApp avec le rapport de la journée déjà écrit.
Future<void> sendDailyReport(BuildContext context) async {
  final repo = context.read<AppState>().repo;
  final shop = (await repo.businessInfo())['biz.name'] ?? 'Ma boutique';
  final text = await repo.dailyReport(shop: shop);
  final phone = await repo.setting('report.phone');
  if (!context.mounted) return;
  final c = TextEditingController(text: phone ?? '');
  final go = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Palette.card,
      title: const Text('Rapport du jour'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Palette.cardHigh,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(text, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Numéro WhatsApp qui reçoit le rapport',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Fermer'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.send_outlined, size: 18),
          onPressed: () => Navigator.pop(ctx, true),
          label: const Text('WhatsApp'),
        ),
      ],
    ),
  );
  if (go != true || !context.mounted) return;
  if (c.text.trim() != (phone ?? '')) {
    await repo.setSetting('report.phone', c.text);
  }
  if (context.mounted) await openWhatsApp(context, c.text, text);
}

/// Compter l'argent du soir, billet par billet, et voir l'écart.
class CloseCashScreen extends StatefulWidget {
  const CloseCashScreen({super.key});

  @override
  State<CloseCashScreen> createState() => _CloseCashScreenState();
}

class _CloseCashScreenState extends State<CloseCashScreen> {
  final _notes = {for (final n in cashNotes) n: TextEditingController()};
  final _mobile = TextEditingController();
  final _total = TextEditingController();
  final _note = TextEditingController();
  bool _adjust = true;

  int get _counted {
    final direct = parseAmount(_total.text);
    if (_total.text.trim().isNotEmpty && direct != null) return direct;
    var s = parseAmount(_mobile.text) ?? 0;
    for (final e in _notes.entries) {
      s += e.key * (parseAmount(e.value.text) ?? 0);
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Clôture de caisse')),
      body: Loader<(int, Map<String, int>)>(
        load: (r) async => (await r.cashBalance(), await r.todayByMethod()),
        builder: (context, d) {
          final expected = d.$1;
          final counted = _counted;
          final gap = counted - expected;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              Panel(
                color: Palette.cardHigh,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Argent attendu (selon l’application)',
                      style: TextStyle(color: Palette.muted),
                    ),
                    Text(
                      app.money(expected),
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                        fontFeatures: tabular,
                      ),
                    ),
                    if (d.$2.isNotEmpty)
                      Text(
                        'Encaissé aujourd’hui : '
                        '${d.$2.entries.map((e) => '${e.key} ${app.money(e.value)}').join(' · ')}',
                        style: TextStyle(color: Palette.muted, fontSize: 13),
                      ),
                  ],
                ),
              ),
              sectionTitle('Comptez votre argent'),
              Panel(
                child: Column(
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final n in cashNotes)
                          SizedBox(
                            width: 150,
                            child: TextField(
                              controller: _notes[n],
                              keyboardType: TextInputType.number,
                              onChanged: (_) => setState(() {}),
                              decoration: InputDecoration(
                                prefixText: '${fcfa(n, unit: false)} × ',
                                hintText: '0',
                                isDense: true,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _mobile,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Wave, Orange Money… (montant)',
                        suffixText: 'FCFA',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _total,
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Ou total compté directement',
                        suffixText: 'FCFA',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Panel(
                color: gap == 0
                    ? Palette.mintSoft
                    : gap < 0
                    ? Palette.redSoft
                    : Palette.amberSoft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AmountLine('Argent compté', counted, strong: true),
                    Text(
                      gap == 0
                          ? '✓ La caisse est juste.'
                          : gap < 0
                          ? 'Il manque ${app.money(-gap)}.'
                          : 'Il y a ${app.money(gap)} de plus que prévu.',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: gap == 0
                            ? Palette.mint
                            : gap < 0
                            ? Palette.red
                            : Palette.amber,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note (facultatif)',
                  hintText: 'ex. avance à Moussa',
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _adjust,
                onChanged: (v) => setState(() => _adjust = v!),
                title: const Text(
                  'Corriger la caisse de l’application au montant compté',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                icon: const Icon(Icons.lock_outline),
                label: const Text('Clôturer la caisse'),
                onPressed: () => _close(counted),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _close(int counted) async {
    final app = context.read<AppState>();
    final gap = await guarded(
      context,
      () => app.repo.closeCash(
        counted: counted,
        note: _note.text,
        adjust: _adjust,
        seller: app.seller?.name,
      ),
    );
    if (gap == null || !mounted) return;
    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Caisse clôturée'),
        content: Text(
          '${gap == 0
              ? '✓ La caisse est juste.'
              : gap < 0
              ? 'Il manquait ${app.money(-gap)}.'
              : 'Il y avait ${app.money(gap)} de plus.'} '
          'Envoyez maintenant le rapport de la journée sur WhatsApp.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Plus tard'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Envoyer le rapport'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (send == true) await sendDailyReport(context);
    if (mounted) Navigator.pop(context);
  }
}
