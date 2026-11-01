import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/management_repository.dart';
import '../accounts/common.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

enum _Span { mois, troisMois, douzeMois, tout }

const _spanLabels = {
  _Span.mois: 'Ce mois-ci',
  _Span.troisMois: '3 mois',
  _Span.douzeMois: '12 mois',
  _Span.tout: 'Depuis le début',
};

/// Rapports : chiffre d'affaires, marge, bénéfice net, ce qui se vend, ce
/// qui rapporte et ce qui dort en stock.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Span _span = _Span.mois;

  DateTime _from(DateTime t) => switch (_span) {
    _Span.mois => DateTime(t.year, t.month),
    _Span.troisMois => DateTime(t.year, t.month - 3, t.day),
    _Span.douzeMois => DateTime(t.year - 1, t.month, t.day),
    _Span.tout => DateTime(2000),
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Rapports'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: EyeButton()),
        ],
      ),
      body: Loader<Report>(
        key: ValueKey(_span),
        load: (r) => r.report(_from(r.now())),
        builder: (context, r) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in _Span.values)
                  ChoiceChip(
                    label: Text(_spanLabels[s]!),
                    selected: _span == s,
                    onSelected: (_) => setState(() => _span = s),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _kpi(app, 'Chiffre d’affaires', r.revenue, '${r.count} ventes'),
                const SizedBox(width: 10),
                _kpi(
                  app,
                  'Marge brute',
                  r.margin,
                  '${r.revenue == 0 ? 0 : (r.margin * 100 / r.revenue).round()} % du CA',
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _kpi(
                  app,
                  'Bénéfice net',
                  r.net,
                  'après ${app.money(r.expenses)} de dépenses',
                  color: r.net < 0 ? Palette.red : Palette.mint,
                ),
                const SizedBox(width: 10),
                _kpi(app, 'Panier moyen', r.basket, 'par vente'),
              ],
            ),
            sectionTitle('6 derniers mois'),
            Panel(child: _MonthsChart(r.months)),
            sectionTitle('Produits les plus vendus'),
            _list(r.topProducts, empty: 'Pas encore de ventes sur la période.'),
            sectionTitle('Ce qui rapporte le plus (marge)'),
            _list(r.topMargins, color: Palette.amber),
            sectionTitle('Meilleurs clients'),
            _list(
              r.topClients.take(5).toList(),
              color: Palette.blue,
              empty: 'Aucune vente à un client nommé sur la période.',
            ),
            if (r.sellers.isNotEmpty) ...[
              sectionTitle('Ventes par vendeur'),
              _list(r.sellers, color: Palette.purple),
            ],
            sectionTitle('Produits qui ne se vendent pas'),
            if (r.sleeping.isEmpty)
              const Panel(
                child: Text('Tous vos produits se sont vendus sur la période.'),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Aucune vente sur la période. Pensez à une promotion.',
                  style: TextStyle(color: Palette.muted),
                ),
              ),
              _list(r.sleeping, color: Palette.grey),
            ],
            sectionTitle('Modes de paiement'),
            _list(r.methods, color: Palette.blue),
          ],
        ),
      ),
    );
  }

  Widget _kpi(
    AppState app,
    String title,
    int value,
    String sub, {
    Color? color,
  }) => Expanded(
    child: Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: Palette.muted, fontSize: 13)),
          FittedBox(
            child: Text(
              app.money(value),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                fontFeatures: tabular,
                color: color,
              ),
            ),
          ),
          Text(sub, style: TextStyle(color: Palette.muted, fontSize: 12)),
        ],
      ),
    ),
  );

  Widget _list(List<Ranked> rows, {Color? color, String empty = ''}) {
    if (rows.isEmpty) {
      return Panel(
        child: Text(
          empty.isEmpty ? 'Pas encore de données sur la période.' : empty,
        ),
      );
    }
    final max = rows.map((r) => r.value).fold<int>(1, (a, b) => b > a ? b : a);
    return Panel(
      child: Column(
        children: [
          for (final r in rows)
            BarRow(
              label: r.name,
              value: r.value,
              max: max,
              detail: r.detail,
              color: color,
            ),
        ],
      ),
    );
  }
}

/// Chiffre d'affaires et bénéfice net des 6 derniers mois, en barres.
class _MonthsChart extends StatelessWidget {
  const _MonthsChart(this.months);
  final List<MonthPoint> months;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final max = months
        .expand((m) => [m.revenue, m.net.abs()])
        .fold<int>(1, (a, b) => b > a ? b : a);
    Widget bar(int v, Color c) => Container(
      width: 12,
      height: 4 + 116 * (v.abs() / max),
      decoration: BoxDecoration(
        color: v < 0 ? Palette.red : c,
        borderRadius: BorderRadius.circular(4),
      ),
    );
    return Column(
      children: [
        SizedBox(
          height: 150,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final m in months)
                Expanded(
                  child: Tooltip(
                    message:
                        'CA ${app.money(m.revenue)}\nBénéfice ${app.money(m.net)}',
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            bar(m.revenue, Palette.amber),
                            const SizedBox(width: 3),
                            bar(m.net, Palette.mint),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          monthNames[m.month.month - 1].substring(0, 3),
                          style: TextStyle(color: Palette.muted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 16,
          runSpacing: 4,
          children: [
            _legend(Palette.amber, 'Chiffre d’affaires'),
            _legend(Palette.mint, 'Bénéfice net'),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color c, String t) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: c,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
      const SizedBox(width: 6),
      Text(t, style: TextStyle(color: Palette.muted, fontSize: 12)),
    ],
  );
}
