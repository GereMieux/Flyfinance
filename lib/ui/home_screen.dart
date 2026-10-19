import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/accounts_repository.dart';
import '../data/repository.dart';
import 'accounts/contacts_screen.dart';
import 'accounts/reminders_screen.dart';
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
    this.reminders,
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

  /// Clients à relancer maintenant (délai et heure réglés dans Relances).
  final int reminders;
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
      (await repo.remindersDue()).length,
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            _header(app, d),
            const SizedBox(height: 18),
            _hero(app, d),
            const SizedBox(height: 14),
            _saleButton(),
            ..._alerts(app, d),
            const SizedBox(height: 22),
            _actions(d),
            const SizedBox(height: 26),
            const SectionTitle('Mes espaces'),
            const SizedBox(height: 10),
            Panel(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                children: [
                  _space(
                    Icons.handyman_outlined,
                    Palette.mint,
                    'Espace prestation',
                    'Devis, factures, rendez-vous',
                    () => _open(const ServicesScreen()),
                  ),
                  _divider(),
                  _space(
                    Icons.event_note_outlined,
                    Palette.amber,
                    'Agenda et notes',
                    'Rendez-vous, notes, listes',
                    () => _open(const AgendaScreen()),
                  ),
                  _divider(),
                  _space(
                    Icons.contacts_outlined,
                    Palette.blue,
                    'Clients et fournisseurs',
                    'Carnet d’adresses, comptes, relances',
                    () => _open(const ContactsScreen()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 26),
            const SectionTitle('Bénéfices'),
            const SizedBox(height: 10),
            _profits(app, d),
            const SizedBox(height: 26),
            SectionTitle(
              'Ventes du jour (${d.today.length})',
              action: 'Détail du jour',
              onAction: () => _open(const DaySalesScreen()),
            ),
            const SizedBox(height: 10),
            Panel(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              child: Column(
                children: [
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
                    child: TextButton.icon(
                      onPressed: () => _open(const SalesListScreen()),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                      label: const Text('Toutes les ventes'),
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

  Widget _header(AppState app, _Dashboard d) {
    final seen = app.cancellationsSeenAt;
    final unseen = d.cancelledToday
        .where((c) => seen == null || c.cancelledAt.isAfter(seen))
        .length;
    return Row(
      children: [
        // Pastille de la boutique, entourée d'un anneau dégradé.
        Container(
          padding: const EdgeInsets.all(2.5),
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [Color(0xFFF2B544), Color(0xFF2E9E6E)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: CircleAvatar(
            radius: 22,
            backgroundColor: Palette.card,
            child: Icon(Icons.storefront_rounded, color: Palette.amber),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                longDate(app.repo.now()),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Palette.muted),
              ),
              const Text(
                'Ma boutique',
                style: TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
            ],
          ),
        ),
        const AppearanceButton(),
        // Notification des annulations pas encore vues dans la corbeille.
        Badge.count(
          count: unseen,
          isLabelVisible: unseen > 0,
          child: IconButton(
            tooltip: 'Ventes annulées',
            onPressed: () => _open(const TrashScreen()),
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ),
        Badge.count(
          count: d.low.length,
          isLabelVisible: d.low.isNotEmpty,
          child: IconButton(
            tooltip: 'Articles bientôt en rupture',
            onPressed: () => _open(const StockScreen(onlyLow: true)),
            icon: const Icon(Icons.notifications_none_rounded),
          ),
        ),
      ],
    );
  }

  /// L'action la plus fréquente, en très grand pour tout le monde.
  Widget _saleButton() => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: const LinearGradient(
        colors: [Color(0xFFF6C35C), Color(0xFFE9A21F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      boxShadow: [
        BoxShadow(
          color: const Color(0xFFE9A21F).withValues(alpha: 0.28),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Haptics.tap();
          _open(const NewSaleScreen());
        },
        child: SizedBox(
          height: 66,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Palette.ink.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.add_shopping_cart_rounded,
                  color: Palette.ink,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Nouvelle vente',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Palette.ink,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  List<Widget> _alerts(AppState app, _Dashboard d) => [
    if (d.low.isNotEmpty) ...[
      const SizedBox(height: 12),
      AlertTile(
        icon: Icons.warning_amber_rounded,
        color: Palette.red,
        background: Palette.redSoft,
        title:
            '${d.low.length} article${d.low.length > 1 ? 's' : ''} bientôt en rupture',
        subtitle: 'Pensez à commander',
        onTap: () => _open(const StockScreen(onlyLow: true)),
      ),
    ],
    if (d.reminders > 0) ...[
      const SizedBox(height: 12),
      AlertTile(
        icon: Icons.notifications_active_outlined,
        color: Palette.amber,
        background: Palette.amberSoft,
        title: '${d.reminders} client${d.reminders > 1 ? 's' : ''} à relancer',
        subtitle: 'Paiements en retard',
        onTap: () => _open(const RemindersScreen()),
      ),
    ],
    if (d.cancelledToday.isNotEmpty) ...[
      const SizedBox(height: 12),
      AlertTile(
        icon: Icons.delete_outline_rounded,
        color: Palette.amber,
        background: Palette.amberSoft,
        title:
            '${d.cancelledToday.length} vente${d.cancelledToday.length > 1 ? 's' : ''} annulée${d.cancelledToday.length > 1 ? 's' : ''} aujourd’hui',
        subtitle: app.money(
          d.cancelledToday.fold(0, (s, c) => s + c.detail.summary.sale.total),
        ),
        onTap: () => _open(const TrashScreen()),
      ),
    ],
  ];

  Widget _divider() => Divider(height: 1, indent: 68, color: Palette.line);

  Widget _space(
    IconData icon,
    Color color,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    leading: IconBubble(icon, color),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(subtitle),
    trailing: Icon(Icons.chevron_right_rounded, color: Palette.muted),
    onTap: onTap,
  );

  Widget _hero(AppState app, _Dashboard d) {
    const labels = {
      Period.jour: ("Ventes d'aujourd'hui", 'Jour'),
      Period.semaine: ('Ventes de la semaine', 'Semaine'),
      Period.mois: ('Ventes du mois', 'Mois'),
    };
    final max = d.bars.fold<int>(1, (m, v) => v > m ? v : m);
    const days = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    final today = DateTime.now();
    const white = Colors.white;
    final soft = white.withValues(alpha: 0.7);
    // Évolution par rapport à hier, comme dans les applis bancaires.
    final yesterday = d.bars[5];
    final change = yesterday == 0
        ? null
        : ((d.bars[6] - yesterday) * 100 / yesterday).round();
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F4A35), Color(0xFF1F6B4F), Color(0xFF2B8A63)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F4A35)
                .withValues(alpha: Palette.isDark ? 0.5 : 0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Cercles décoratifs, comme sur une carte bancaire.
          Positioned(
            right: -60,
            top: -70,
            child: _ring(200, white.withValues(alpha: 0.07)),
          ),
          Positioned(
            right: 40,
            top: -100,
            child: _ring(180, white.withValues(alpha: 0.05)),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: _periodTabs(labels)),
                    const SizedBox(width: 8),
                    const EyeButton(onDark: true),
                  ],
                ),
                const SizedBox(height: 20),
                Text(
                  labels[_period]!.$1,
                  style: TextStyle(color: soft, fontSize: 14),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  child: AnimatedMoney(
                    d.stats.sales,
                    style: const TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.8,
                      color: white,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _pill(
                      '${d.stats.count} vente${d.stats.count > 1 ? 's' : ''}',
                      Icons.receipt_long_rounded,
                    ),
                    if (_period == Period.jour && change != null) ...[
                      const SizedBox(width: 8),
                      _pill(
                        '${change >= 0 ? '+' : ''}$change % vs hier',
                        change >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: change >= 0
                            ? const Color(0xFF9BF0C3)
                            : const Color(0xFFFFB4A6),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 18),
                SizedBox(
                  height: 76,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      for (var i = 0; i < 7; i++)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 5),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                // Les barres montent doucement à l'ouverture.
                                TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0, end: d.bars[i] / max),
                                  duration: Motion.slow,
                                  curve: Motion.curve,
                                  builder: (_, v, child) => SizedBox(
                                    height: 6 + 48 * v,
                                    child: child,
                                  ),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(8),
                                      gradient: i == 6
                                          ? const LinearGradient(
                                              colors: [
                                                Color(0xFFFFD27A),
                                                Color(0xFFF2B544),
                                              ],
                                              begin: Alignment.topCenter,
                                              end: Alignment.bottomCenter,
                                            )
                                          : null,
                                      color: i == 6
                                          ? null
                                          : white.withValues(alpha: 0.18),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  days[today
                                          .subtract(Duration(days: 6 - i))
                                          .weekday -
                                      1],
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: i == 6
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: i == 6 ? white : soft,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      _mini('Bénéfice', app.money(d.stats.profit), white),
                      _vline(),
                      _mini('Argent reçu', app.money(d.stats.cashIn), white),
                      _vline(),
                      _mini(
                        'Crédits dehors',
                        app.money(d.credit),
                        const Color(0xFFFFD27A),
                        onTap: () => _open(const CreditsScreen()),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ring(double size, Color color) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: color, width: 28),
    ),
  );

  Widget _vline() => Container(
    width: 1,
    height: 34,
    color: Colors.white.withValues(alpha: 0.14),
  );

  Widget _pill(String text, IconData icon, {Color? color}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.13),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: color ?? Colors.white),
        const SizedBox(width: 5),
        Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color ?? Colors.white,
          ),
        ),
      ],
    ),
  );

  /// Onglets Jour / Semaine / Mois en pilule translucide.
  Widget _periodTabs(Map<Period, (String, String)> labels) => Container(
    height: 44,
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Row(
      children: [
        for (final p in Period.values)
          Expanded(
            child: Semantics(
              button: true,
              selected: p == _period,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (p == _period) return;
                  Haptics.tap();
                  setState(() => _period = p);
                },
                child: AnimatedContainer(
                  duration: Motion.normal,
                  curve: Motion.curve,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: p == _period ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Text(
                    labels[p]!.$2,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: p == _period
                          ? const Color(0xFF0F4A35)
                          : Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );

  /// Chiffres fixes du jour et du mois, quel que soit l'onglet choisi
  /// au-dessus.
  Widget _profits(AppState app, _Dashboard d) => IntrinsicHeight(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kpi(
          Icons.payments_outlined,
          Palette.blue,
          'Ventes du jour',
          app.money(d.todayStats.sales),
          Palette.text,
        ),
        const SizedBox(width: 10),
        _kpi(
          Icons.trending_up_rounded,
          Palette.mint,
          'Bénéfice du jour',
          app.money(d.todayStats.profit),
          Palette.mint,
        ),
        const SizedBox(width: 10),
        _kpi(
          Icons.calendar_month_outlined,
          Palette.purple,
          'Bénéfice du mois',
          app.money(d.monthStats.profit),
          Palette.mint,
        ),
      ],
    ),
  );

  Widget _kpi(
    IconData icon,
    Color tint,
    String label,
    String value,
    Color color,
  ) => Expanded(
    child: Panel(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBubble(icon, tint, size: 34),
          const SizedBox(height: 10),
          Text(
            label,
            maxLines: 2,
            style: TextStyle(fontSize: 12, color: Palette.muted, height: 1.25),
          ),
          const Spacer(),
          const SizedBox(height: 4),
          FittedBox(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _mini(
    String label,
    String value,
    Color color, {
    VoidCallback? onTap,
  }) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 2),
            FittedBox(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _actions(_Dashboard d) {
    Widget action(
      String label,
      IconData icon,
      Color color,
      VoidCallback onTap, {
      int badge = 0,
    }) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              Badge(
                isLabelVisible: badge > 0,
                label: Text('$badge'),
                child: Container(
                  width: 62,
                  height: 62,
                  decoration: BoxDecoration(
                    color: Palette.card,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Palette.line),
                  ),
                  child: Center(child: IconBubble(icon, color, size: 42)),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        action(
          'Ventes du jour',
          Icons.receipt_long_rounded,
          Palette.mint,
          () => _open(const DaySalesScreen()),
        ),
        action(
          'Acheter',
          Icons.local_shipping_outlined,
          Palette.blue,
          () => _open(const StockScreen(purchaseMode: true)),
        ),
        action(
          'Stock',
          Icons.inventory_2_outlined,
          Palette.amber,
          () => _open(const StockScreen()),
          badge: d.low.length,
        ),
        action(
          'Crédits',
          Icons.account_balance_wallet_outlined,
          Palette.purple,
          () => _open(const CreditsScreen()),
        ),
      ],
    );
  }
}
