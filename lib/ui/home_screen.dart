import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import 'credits_screen.dart';
import 'new_sale_screen.dart';
import 'sales_list_screen.dart';
import 'stock_screen.dart';
import 'theme.dart';
import 'widgets.dart';

enum Period { jour, semaine, mois }

class _Dashboard {
  _Dashboard(this.stats, this.bars, this.low, this.recent, this.credit);
  final PeriodStats stats;
  final List<int> bars;
  final List<ProductStock> low;
  final List<SaleSummary> recent;
  final int credit;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Period _period = Period.jour;

  DateTime _from(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      Period.jour => today,
      Period.semaine => today.subtract(Duration(days: today.weekday - 1)),
      Period.mois => DateTime(now.year, now.month),
    };
  }

  Future<_Dashboard> _load(Repository repo) async {
    final stats = await repo.statsSince(_from(repo.now()));
    final debts = await repo.debtors();
    return _Dashboard(
      stats,
      await repo.dailySales(7),
      await repo.lowStock(),
      (await repo.sales()).take(4).toList(),
      debts.fold(0, (s, d) => s + d.due),
    );
  }

  void _open(Widget screen) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SafeArea(
      child: Loader<_Dashboard>(
        key: ValueKey(_period),
        load: _load,
        builder: (context, d) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                const CircleAvatar(
                  radius: 23,
                  backgroundColor: Palette.cardHigh,
                  child: Icon(Icons.storefront, color: Palette.amber),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Ma boutique',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                if (d.low.isNotEmpty)
                  Badge.count(
                    count: d.low.length,
                    child: IconButton(
                      tooltip: 'Articles bientôt en rupture',
                      onPressed: () => _open(const StockScreen(onlyLow: true)),
                      icon: const Icon(Icons.notifications_outlined),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            _hero(app, d),
            const SizedBox(height: 18),
            _actions(d),
            if (d.low.isNotEmpty) ...[
              const SizedBox(height: 16),
              Material(
                color: const Color(0xFF3A1F1B),
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: const Icon(
                    Icons.warning_amber_rounded,
                    color: Palette.red,
                  ),
                  title: Text(
                    '${d.low.length} article${d.low.length > 1 ? 's' : ''} bientôt en rupture',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Palette.red,
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Palette.red),
                  onTap: () => _open(const StockScreen(onlyLow: true)),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Panel(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Activité récente',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _open(const SalesListScreen()),
                        child: const Text('Tout voir'),
                      ),
                    ],
                  ),
                  if (d.recent.isEmpty)
                    const EmptyState(
                      'Aucune vente pour l’instant.\nTouchez « Vendre » pour commencer.',
                    ),
                  for (final s in d.recent) SaleTile(s, dense: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(AppState app, _Dashboard d) {
    const labels = {
      Period.jour: ("Chiffre d'affaires d'aujourd'hui", 'Jour'),
      Period.semaine: ("Chiffre d'affaires de la semaine", 'Semaine'),
      Period.mois: ("Chiffre d'affaires du mois", 'Mois'),
    };
    final max = d.bars.fold<int>(1, (m, v) => v > m ? v : m);
    const days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final today = DateTime.now();
    return Panel(
      color: const Color(0xFF18302A),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<Period>(
                  showSelectedIcon: false,
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor: Palette.amber,
                    selectedForegroundColor: Palette.ink,
                    side: const BorderSide(color: Palette.line),
                  ),
                  segments: [
                    for (final p in Period.values)
                      ButtonSegment(value: p, label: Text(labels[p]!.$2)),
                  ],
                  selected: {_period},
                  onSelectionChanged: (s) => setState(() => _period = s.first),
                ),
              ),
              const SizedBox(width: 8),
              const EyeButton(),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            labels[_period]!.$1,
            style: const TextStyle(color: Palette.muted, fontSize: 14),
          ),
          const SizedBox(height: 2),
          FittedBox(
            child: Text(
              app.money(d.stats.sales),
              style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            '${d.stats.count} vente${d.stats.count > 1 ? 's' : ''}',
            style: const TextStyle(
              color: Palette.mint,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 70,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < 7; i++)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Container(
                            height: 4 + 44 * d.bars[i] / max,
                            decoration: BoxDecoration(
                              color: i == 6
                                  ? Palette.amber
                                  : const Color(0xFF2F4239),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            days[today.subtract(Duration(days: 6 - i)).weekday -
                                1],
                            style: const TextStyle(
                              fontSize: 11,
                              color: Palette.muted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _mini('Bénéfice', app.money(d.stats.profit), Palette.text),
              const SizedBox(width: 8),
              _mini('Encaissé', app.money(d.stats.cashIn), Palette.text),
              const SizedBox(width: 8),
              _mini(
                'Crédits dehors',
                app.money(d.credit),
                Palette.amber,
                onTap: () => _open(const CreditsScreen()),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _mini(
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) => Expanded(
    child: Material(
      color: const Color(0xFF1D2D26),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 12, color: Palette.muted),
              ),
              FittedBox(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _actions(_Dashboard d) {
    Widget action(
      String label,
      IconData icon,
      VoidCallback onTap, {
      bool main = false,
      int badge = 0,
    }) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Column(
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: main ? Palette.green : Palette.card,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 28),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
    return Row(
      children: [
        action(
          'Vendre',
          Icons.shopping_cart_outlined,
          () => _open(const NewSaleScreen()),
          main: true,
        ),
        action(
          'Acheter',
          Icons.inventory_2_outlined,
          () => _open(const StockScreen(purchaseMode: true)),
        ),
        action(
          'Stock',
          Icons.grid_view_rounded,
          () => _open(const StockScreen()),
          badge: d.low.length,
        ),
        action(
          'Crédits',
          Icons.credit_card,
          () => _open(const CreditsScreen()),
        ),
      ],
    );
  }
}
