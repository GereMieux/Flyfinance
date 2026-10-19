import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import 'theme.dart';
import 'widgets.dart';

class _Day {
  _Day(this.details, this.stats);
  final List<SaleDetail> details;
  final PeriodStats stats;
}

/// Détail des ventes d'une journée : chiffres du jour, articles vendus et
/// chaque vente avec son contenu.
class DaySalesScreen extends StatefulWidget {
  const DaySalesScreen({super.key, this.day});
  final DateTime? day;
  @override
  State<DaySalesScreen> createState() => _DaySalesScreenState();
}

class _DaySalesScreenState extends State<DaySalesScreen> {
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    final d = widget.day ?? DateTime.now();
    _day = DateTime(d.year, d.month, d.day);
  }

  bool get _isToday {
    final n = DateTime.now();
    return _day == DateTime(n.year, n.month, n.day);
  }

  void _shift(int days) =>
      setState(() => _day = DateTime(_day.year, _day.month, _day.day + days));

  String get _title {
    if (_isToday) return "Ventes d'aujourd'hui";
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Ventes du ${two(_day.day)}/${two(_day.month)}/${_day.year}';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Choisir un jour',
            icon: const Icon(Icons.calendar_month_outlined),
            onPressed: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _day,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
              );
              if (picked != null) setState(() => _day = picked);
            },
          ),
        ],
      ),
      body: Loader<_Day>(
        key: ValueKey(_day),
        load: (r) async => _Day(
          await r.dayDetails(_day),
          await r.statsSince(
            _day,
            to: DateTime(_day.year, _day.month, _day.day + 1),
          ),
        ),
        builder: (context, d) {
          final products = _byProduct(d.details);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Row(
                children: [
                  IconButton.outlined(
                    tooltip: 'Jour précédent',
                    onPressed: () => _shift(-1),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  const Spacer(),
                  const EyeButton(),
                  const Spacer(),
                  IconButton.outlined(
                    tooltip: 'Jour suivant',
                    onPressed: _isToday ? null : () => _shift(1),
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Panel(
                color: const Color(0xFF18302A),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Total des ventes',
                      style: TextStyle(color: Palette.muted),
                    ),
                    FittedBox(
                      child: Text(
                        app.money(d.stats.sales),
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        statChip(
                          'Bénéfice',
                          app.money(d.stats.profit),
                          Palette.mint,
                        ),
                        const SizedBox(width: 8),
                        statChip(
                          'Argent reçu',
                          app.money(d.stats.cashIn),
                          Palette.text,
                        ),
                        const SizedBox(width: 8),
                        statChip('Ventes', '${d.stats.count}', Palette.text),
                      ],
                    ),
                  ],
                ),
              ),
              if (products.isNotEmpty) ...[
                const SizedBox(height: 16),
                const _Title('Articles vendus'),
                Panel(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    children: [
                      for (final p in products)
                        ListTile(
                          title: Text(
                            p.$1,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${p.$2} vendu${p.$2 > 1 ? 's' : ''}',
                            style: const TextStyle(color: Palette.muted),
                          ),
                          trailing: Text(
                            app.money(p.$3),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const _Title('Toutes les ventes'),
              if (d.details.isEmpty)
                const EmptyState('Aucune vente ce jour-là.'),
              for (final s in d.details) SaleCard(s),
            ],
          );
        },
      ),
    );
  }

  /// (nom, quantité, montant) par article, hors ventes annulées.
  List<(String, int, int)> _byProduct(List<SaleDetail> details) {
    final out = <int, (String, int, int)>{};
    for (final s in details) {
      if (s.summary.sale.cancelled) continue;
      for (final l in s.lines) {
        final prev = out[l.product.id];
        out[l.product.id] = (
          l.product.name,
          (prev?.$2 ?? 0) + l.qty,
          (prev?.$3 ?? 0) + l.total,
        );
      }
    }
    return out.values.toList()..sort((a, b) => b.$3.compareTo(a.$3));
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
  );
}

/// Une vente dépliable avec ses articles. `note` remplace l'heure de vente
/// sous le nom du client (ex. l'heure d'annulation dans la corbeille).
class SaleCard extends StatelessWidget {
  const SaleCard(this.d, {super.key, this.note});
  final SaleDetail d;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final s = d.summary;
    final cancelled = s.status == SaleStatus.annulee;
    String two(int n) => n.toString().padLeft(2, '0');
    final time =
        '${two(s.sale.createdAt.hour)}:${two(s.sale.createdAt.minute)}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Palette.card,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(
            s.contact?.name ?? 'Client de passage',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${note ?? time} · ${d.lines.length} article${d.lines.length > 1 ? 's' : ''}',
            style: const TextStyle(color: Palette.muted),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                app.money(s.sale.total),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: cancelled ? Palette.grey : Palette.text,
                  decoration: cancelled ? TextDecoration.lineThrough : null,
                ),
              ),
              Text(
                s.status.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: statusColor(s.status),
                ),
              ),
            ],
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          children: [
            for (final l in d.lines)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text('${l.qty} × ${l.product.name}')),
                    Text(app.money(l.total)),
                  ],
                ),
              ),
            const Divider(color: Palette.line),
            _row('Payé', app.money(s.paid), Palette.mint),
            if (s.due > 0)
              _row('Reste à payer', app.money(s.due), Palette.amber),
            if (!cancelled)
              _row('Bénéfice', app.money(d.margin), Palette.muted),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Palette.muted)),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.w700, color: color),
        ),
      ],
    ),
  );
}
