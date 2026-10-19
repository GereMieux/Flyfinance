import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import 'agenda/agenda_screen.dart';
import 'credits_screen.dart';
import 'day_sales_screen.dart';
import 'new_sale_screen.dart';
import 'sales_list_screen.dart';
import 'services/services_screen.dart';
import 'stock_screen.dart';
import 'trash_screen.dart';
import 'theme.dart';
import 'widgets.dart';

enum Period { jour, semaine, mois }

class _Dashboard {
  _Dashboard(
    this.stats,
    this.bars,
    this.low,
    this.today,
    this.credit,
    this.todayStats,
    this.monthStats,
    this.cancelledToday,
  );
  final PeriodStats stats;
  final List<int> bars;
  final List<ProductStock> low;

  /// Toutes les ventes d'aujourd'hui, de la plus récente à la plus ancienne.
  final List<SaleSummary> today;
  final int credit;
  final PeriodStats todayStats;
  final PeriodStats monthStats;
  final List<CancelledSale> cancelledToday;
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
    final now = repo.now();
    final today = DateTime(now.year, now.month, now.day);
    final stats = await repo.statsSince(_from(now));
    final debts = await repo.debtors();
    return _Dashboard(
      stats,
      await repo.dailySales(7),
      await repo.lowStock(),
      await repo.sales(from: today),
      debts.fold(0, (s, d) => s + d.due),
      await repo.statsSince(today),
      await repo.statsSince(DateTime(now.year, now.month)),
      await repo.cancelledSales(from: today),
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
                CircleAvatar(
                  radius: 23,
                  backgroundColor: Palette.cardHigh,
                  child: Icon(Icons.storefront, color: Palette.amber),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ma boutique',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        longDate(app.repo.now()),
                        style: TextStyle(fontSize: 13, color: Palette.muted),
                      ),
                    ],
                  ),
                ),
                const AppearanceButton(),
                // Notification des annulations pas encore vues dans la corbeille.
                Builder(
                  builder: (context) {
                    final seen = app.cancellationsSeenAt;
                    final unseen = d.cancelledToday
                        .where(
                          (c) => seen == null || c.cancelledAt.isAfter(seen),
                        )
                        .length;
                    return Badge.count(
                      count: unseen,
                      isLabelVisible: unseen > 0,
                      child: IconButton(
                        tooltip: 'Ventes annulées',
                        onPressed: () => _open(const TrashScreen()),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    );
                  },
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
            if (d.cancelledToday.isNotEmpty) ...[
              const SizedBox(height: 16),
              Material(
                color: Palette.amberSoft,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Icon(Icons.delete_outline, color: Palette.amber),
                  title: Text(
                    '${d.cancelledToday.length} vente${d.cancelledToday.length > 1 ? 's' : ''} annulée${d.cancelledToday.length > 1 ? 's' : ''} aujourd’hui',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Palette.amber,
                    ),
                  ),
                  subtitle: Text(
                    app.money(
                      d.cancelledToday.fold(
                        0,
                        (s, c) => s + c.detail.summary.sale.total,
                      ),
                    ),
                    style: TextStyle(color: Palette.muted),
                  ),
                  trailing: Icon(Icons.chevron_right, color: Palette.amber),
                  onTap: () => _open(const TrashScreen()),
                ),
              ),
            ],
            if (d.low.isNotEmpty) ...[
              const SizedBox(height: 16),
              Material(
                color: Palette.redSoft,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Icon(
                    Icons.warning_amber_rounded,
                    color: Palette.red,
                  ),
                  title: Text(
                    '${d.low.length} article${d.low.length > 1 ? 's' : ''} bientôt en rupture',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Palette.red,
                    ),
                  ),
                  trailing: Icon(Icons.chevron_right, color: Palette.red),
                  onTap: () => _open(const StockScreen(onlyLow: true)),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // L'action la plus fréquente, en très grand pour tout le monde.
            FilledButton.icon(
              onPressed: () => _open(const NewSaleScreen()),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(68),
                textStyle: const TextStyle(
                  fontFamily: appFont,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.shopping_cart_outlined, size: 28),
              label: const Text('Nouvelle vente'),
            ),
            const SizedBox(height: 16),
            _hero(app, d),
            const SizedBox(height: 18),
            _actions(d),
            const SizedBox(height: 16),
            Material(
              color: Palette.card,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(Icons.handyman_outlined, color: Palette.mint),
                title: const Text(
                  'Espace prestation',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Devis, factures, rendez-vous'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(const ServicesScreen()),
              ),
            ),
            const SizedBox(height: 10),
            Material(
              color: Palette.card,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                leading: Icon(Icons.event_note_outlined, color: Palette.amber),
                title: const Text(
                  'Agenda et notes',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: const Text('Rendez-vous, notes, listes'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _open(const AgendaScreen()),
              ),
            ),
            const SizedBox(height: 18),
            _profits(app, d),
            const SizedBox(height: 16),
            Panel(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Ventes du jour (${d.today.length})',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _open(const DaySalesScreen()),
                        child: const Text('Détail du jour'),
                      ),
                    ],
                  ),
                  if (d.today.isEmpty)
                    EmptyState(
                      'Aucune vente aujourd’hui.',
                      icon: Icons.receipt_long_outlined,
                      actionLabel: 'Faire une vente',
                      onAction: () => _open(const NewSaleScreen()),
                    ),
                  for (final s in d.today) SaleTile(s, dense: true),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _open(const SalesListScreen()),
                      child: const Text('Toutes les ventes'),
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

  Widget _hero(AppState app, _Dashboard d) {
    const labels = {
      Period.jour: ("Total des ventes d'aujourd'hui", 'Jour'),
      Period.semaine: ('Total des ventes de la semaine', 'Semaine'),
      Period.mois: ('Total des ventes du mois', 'Mois'),
    };
    final max = d.bars.fold<int>(1, (m, v) => v > m ? v : m);
    const days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final today = DateTime.now();
    return Panel(
      color: Palette.hero,
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
                    side: BorderSide(color: Palette.line),
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
            style: TextStyle(color: Palette.muted, fontSize: 14),
          ),
          const SizedBox(height: 2),
          FittedBox(
            child: AnimatedMoney(
              d.stats.sales,
              style: const TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5,
              ),
            ),
          ),
          Text(
            '${d.stats.count} vente${d.stats.count > 1 ? 's' : ''}',
            style: TextStyle(color: Palette.mint, fontWeight: FontWeight.w700),
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
                          // Les barres montent doucement à l'ouverture.
                          TweenAnimationBuilder<double>(
                            tween: Tween(begin: 0, end: d.bars[i] / max),
                            duration: Motion.slow,
                            curve: Motion.curve,
                            builder: (_, v, child) =>
                                SizedBox(height: 4 + 44 * v, child: child),
                            child: Container(
                              decoration: BoxDecoration(
                                color: i == 6 ? Palette.amber : Palette.bar,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            days[today.subtract(Duration(days: 6 - i)).weekday -
                                1],
                            style: TextStyle(
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
              _mini('Argent reçu', app.money(d.stats.cashIn), Palette.text),
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

  /// Chiffres fixes du jour et du mois, quel que soit l'onglet choisi
  /// au-dessus.
  Widget _profits(AppState app, _Dashboard d) => Panel(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text(
            'Bénéfices',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
        ),
        Row(
          children: [
            statChip(
              'Ventes du jour',
              app.money(d.todayStats.sales),
              Palette.text,
            ),
            const SizedBox(width: 8),
            statChip(
              'Bénéfice du jour',
              app.money(d.todayStats.profit),
              Palette.mint,
            ),
            const SizedBox(width: 8),
            statChip(
              'Bénéfice du mois',
              app.money(d.monthStats.profit),
              Palette.mint,
            ),
          ],
        ),
      ],
    ),
  );

  Widget _mini(
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) => Expanded(
    child: Material(
      color: Palette.heroTile,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 12, color: Palette.muted)),
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
                  color: Palette.card,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(icon, size: 28),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        action(
          'Ventes du jour',
          Icons.receipt_long_outlined,
          () => _open(const DaySalesScreen()),
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
