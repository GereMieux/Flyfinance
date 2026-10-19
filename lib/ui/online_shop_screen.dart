import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../data/shop_database.dart';
import '../data/shop_repository.dart';
import 'online_forms.dart';
import 'storefront_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Espace vente en ligne : commandes, catalogue, promotions et annonces.
class OnlineShopScreen extends StatelessWidget {
  const OnlineShopScreen({super.key, this.embedded = false});

  /// Affiché comme onglet (sans bouton retour).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    final shop = context.read<ShopRepository>();
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !embedded,
          title: const Text('Vente en ligne'),
          actions: [
            IconButton(
              tooltip: 'Voir la vitrine comme un client',
              icon: const Icon(Icons.storefront_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StorefrontScreen()),
              ),
            ),
            IconButton(
              tooltip: 'Partager le catalogue sur WhatsApp',
              icon: const Icon(Icons.share_outlined),
              onPressed: () => shareCatalog(context, shop),
            ),
            IconButton(
              tooltip: 'Paiement et livraison',
              icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ShopSettingsScreen()),
              ),
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Palette.amber,
            labelColor: Palette.text,
            unselectedLabelColor: Palette.muted,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            tabs: [
              Tab(icon: Icon(Icons.local_shipping_outlined), text: 'Commandes'),
              Tab(icon: Icon(Icons.shopping_bag_outlined), text: 'Catalogue'),
              Tab(icon: Icon(Icons.local_offer_outlined), text: 'Promos'),
              Tab(icon: Icon(Icons.campaign_outlined), text: 'Annonces'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_OrdersTab(), _CatalogTab(), _PromosTab(), _NewsTab()],
        ),
      ),
    );
  }
}

/// Ouvre WhatsApp avec le texte déjà écrit. Rien ne part sans que le
/// commerçant appuie lui-même sur Envoyer.
Future<void> shareOnWhatsApp(
  BuildContext context,
  String text, {
  String phone = '',
}) async {
  final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
  final to = digits.isEmpty
      ? ''
      : (digits.length == 10 ? '225$digits' : digits);
  final uri = Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent(text)}');
  if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
      context.mounted) {
    toast(context, 'WhatsApp n’a pas pu s’ouvrir.');
  }
}

Future<void> shareCatalog(BuildContext context, ShopRepository shop) async {
  final text = await shop.catalogMessage();
  if (context.mounted) await shareOnWhatsApp(context, text);
}

/// Message d'erreur sans « Bad state: » ni « Invalid argument(s): ».
String errorText(Object e) => '$e'.replaceFirst(
  RegExp(r'^(Invalid argument\(s\)|Bad state|\w+Error): '),
  '',
);

Color orderColor(OrderStatus s) => switch (s) {
  OrderStatus.nouvelle => Palette.amber,
  OrderStatus.confirmee => Palette.blue,
  OrderStatus.livraison => Palette.blue,
  OrderStatus.livree => Palette.mint,
  OrderStatus.annulee => Palette.grey,
};

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.16),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

Widget _addButton(String label, VoidCallback onTap) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: FilledButton.icon(
    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(60)),
    onPressed: onTap,
    icon: const Icon(Icons.add, size: 26),
    label: Text(label),
  ),
);

// ---------------------------------------------------------------- Commandes

class _OrdersData {
  _OrdersData(this.orders, this.stats, this.info);
  final List<OrderDetail> orders;
  final ShopStats stats;
  final ShopInfo info;
}

class _OrdersTab extends StatefulWidget {
  const _OrdersTab();
  @override
  State<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends State<_OrdersTab> {
  bool _onlyOpen = true;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shop = context.read<ShopRepository>();
    return Loader<_OrdersData>(
      load: (_) async => _OrdersData(
        await shop.orders(),
        await shop.stats(),
        await shop.info(),
      ),
      builder: (context, d) {
        final list = _onlyOpen
            ? d.orders.where((o) => o.status.open).toList()
            : d.orders;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Row(
              children: [
                _stat('À traiter', '${d.stats.toHandle}', Palette.amber),
                const SizedBox(width: 8),
                _stat(
                  'Livrées ce mois',
                  '${d.stats.deliveredMonth}',
                  Palette.mint,
                ),
                const SizedBox(width: 8),
                _stat(
                  'Vendu en ligne',
                  app.money(d.stats.revenueMonth),
                  Palette.text,
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (d.info.orangeNumber.isEmpty && d.info.waveNumber.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Material(
                  color: const Color(0xFF3A2F1B),
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    leading: const Icon(
                      Icons.phone_android,
                      color: Palette.amber,
                    ),
                    title: const Text(
                      'Ajoutez vos numéros Orange Money et Wave',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Palette.amber,
                      ),
                    ),
                    subtitle: const Text('Pour être payé à distance.'),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: Palette.amber,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ShopSettingsScreen(),
                      ),
                    ),
                  ),
                ),
              ),
            _addButton(
              'Nouvelle commande',
              () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const NewOrderScreen())),
            ),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(
                  label: Text('À traiter (${d.stats.toHandle})'),
                  selected: _onlyOpen,
                  onSelected: (_) => setState(() => _onlyOpen = true),
                ),
                ChoiceChip(
                  label: Text('Toutes (${d.orders.length})'),
                  selected: !_onlyOpen,
                  onSelected: (_) => setState(() => _onlyOpen = false),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const EmptyState(
                'Aucune commande à traiter.\nLes commandes reçues par WhatsApp ou par téléphone s’enregistrent ici.',
                icon: Icons.local_shipping_outlined,
              ),
            for (final o in list) _orderTile(context, app, o),
          ],
        );
      },
    );
  }

  Widget _stat(String label, String value, Color color) => Expanded(
    child: Panel(
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
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _orderTile(
    BuildContext context,
    AppState app,
    OrderDetail o,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Palette.card,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => OrderScreen(o.order.id))),
        title: Text(
          'N°${o.order.id} · ${o.order.customerName}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${shortDate(o.order.createdAt)}\n${onlinePayMethods[o.order.payMethod]}${o.order.paid ? ' · payé' : ''}',
          style: const TextStyle(color: Palette.muted),
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              app.money(o.toPay),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            _Tag(o.status.label, orderColor(o.status)),
          ],
        ),
      ),
    ),
  );
}

/// Détail d'une commande et ses étapes : confirmer, livrer, encaisser.
class OrderScreen extends StatelessWidget {
  const OrderScreen(this.orderId, {super.key});
  final int orderId;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shop = context.read<ShopRepository>();
    return Scaffold(
      appBar: AppBar(title: Text('Commande n°$orderId')),
      body: Loader<(OrderDetail, ShopInfo)>(
        load: (_) async => (await shop.order(orderId), await shop.info()),
        builder: (context, data) {
          final (d, info) = data;
          final o = d.order;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            o.customerName,
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        _Tag(d.status.label, orderColor(d.status)),
                      ],
                    ),
                    if (o.phone.isNotEmpty) Text('Tél. ${o.phone}'),
                    if (o.address.isNotEmpty) Text('Livrer à : ${o.address}'),
                    if (o.note.isNotEmpty)
                      Text(
                        o.note,
                        style: const TextStyle(color: Palette.muted),
                      ),
                    Text(
                      shortDate(o.createdAt),
                      style: const TextStyle(color: Palette.muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Panel(
                child: Column(
                  children: [
                    for (final l in d.lines)
                      _row(
                        '${l.qty} × ${l.name}${[l.size, l.color].where((s) => s.isNotEmpty).map((s) => ' · $s').join()}',
                        app.money(l.qty * l.unitPrice),
                      ),
                    if (o.deliveryFee > 0)
                      _row('Livraison', app.money(o.deliveryFee)),
                    const Divider(color: Palette.line),
                    _row('Total à payer', app.money(d.toPay), bold: true),
                    _row(
                      onlinePayMethods[o.payMethod]!,
                      o.paid ? 'Payé' : 'Pas encore payé',
                      color: o.paid ? Palette.mint : Palette.amber,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (d.status.open) ..._actions(context, app, shop, d, info),
              if (d.status == OrderStatus.livree)
                const Text(
                  'Livrée : la vente est dans « Toutes les ventes » et le stock est à jour.',
                  style: TextStyle(color: Palette.mint),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String a, String b, {bool bold = false, Color? color}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(child: Text(a)),
        Text(
          b,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
            color: color,
          ),
        ),
      ],
    ),
  );

  List<Widget> _actions(
    BuildContext context,
    AppState app,
    ShopRepository shop,
    OrderDetail d,
    ShopInfo info,
  ) {
    Future<void> run(Future<void> Function() f, String done) async {
      try {
        await f();
        app.changed();
        if (context.mounted) toast(context, done);
      } catch (e) {
        if (context.mounted) toast(context, errorText(e));
      }
    }

    final o = d.order;
    final next = switch (d.status) {
      OrderStatus.nouvelle => (OrderStatus.confirmee, 'Confirmer la commande'),
      _ => (OrderStatus.livree, 'Livrée au client'),
    };
    return [
      if (o.payMethod != 'livraison' && !o.paid) ...[
        OutlinedButton.icon(
          onPressed: () => shareOnWhatsApp(
            context,
            shop.paymentMessage(d, info),
            phone: o.phone,
          ),
          icon: const Icon(Icons.send_outlined),
          label: Text(
            'Envoyer la demande de paiement ${onlinePayMethods[o.payMethod]}',
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: () => run(() => shop.markPaid(o.id), 'Paiement noté.'),
          icon: const Icon(Icons.check),
          label: const Text('J’ai reçu le paiement'),
        ),
        const SizedBox(height: 8),
      ],
      if (o.payMethod == 'livraison' || o.paid) ...[
        FilledButton(
          onPressed: () => run(
            () => shop.setStatus(o.id, next.$1),
            next.$1 == OrderStatus.livree
                ? 'Livrée. La vente est enregistrée.'
                : 'Commande ${next.$1.label.toLowerCase()}.',
          ),
          child: Text(next.$2),
        ),
        const SizedBox(height: 8),
        if (o.phone.isNotEmpty)
          OutlinedButton.icon(
            onPressed: () => shareOnWhatsApp(
              context,
              shop.paymentMessage(d, info),
              phone: o.phone,
            ),
            icon: const Icon(Icons.send_outlined),
            label: const Text('Envoyer le récapitulatif au client'),
          ),
        const SizedBox(height: 8),
      ],
      TextButton(
        onPressed: () async {
          final ok = await confirm(context, 'Annuler la commande n°${o.id} ?');
          if (ok) {
            await run(
              () => shop.setStatus(o.id, OrderStatus.annulee),
              'Commande annulée.',
            );
          }
        },
        child: const Text(
          'Annuler la commande',
          style: TextStyle(color: Palette.red),
        ),
      ),
    ];
  }
}

Future<bool> confirm(BuildContext context, String question) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: Text(question),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oui'),
          ),
        ],
      ),
    ) ??
    false;

// ---------------------------------------------------------------- Catalogue

class _CatalogTab extends StatefulWidget {
  const _CatalogTab();
  @override
  State<_CatalogTab> createState() => _CatalogTabState();
}

class _CatalogTabState extends State<_CatalogTab> {
  int? _category;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shop = context.read<ShopRepository>();
    return Loader<(List<CatalogItem>, List<ShopCategory>)>(
      load: (_) async => (await shop.catalog(), await shop.categories()),
      builder: (context, data) {
        final (all, cats) = data;
        final list = _category == null
            ? all
            : all.where((c) => c.item.categoryId == _category).toList();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _addButton(
              'Mettre un article en ligne',
              () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const ShopItemForm())),
            ),
            if (cats.isNotEmpty)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final c in [null, ...cats])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(c?.name ?? 'Tout'),
                          selected: _category == c?.id,
                          onSelected: (_) => setState(() => _category = c?.id),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (list.isEmpty)
              const EmptyState(
                'Aucun article en ligne.\nChoisissez des articles de votre stock pour les présenter.',
                icon: Icons.shopping_bag_outlined,
              ),
            for (final c in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: Palette.card,
                  borderRadius: BorderRadius.circular(16),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ShopItemForm(item: c)),
                    ),
                    title: Text(
                      c.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: c.item.published ? Palette.text : Palette.muted,
                      ),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          [
                            c.category?.name,
                            c.brand?.name,
                            if (c.sizes.isNotEmpty) c.sizes.join('/'),
                            if (c.colors.isNotEmpty) c.colors.join('/'),
                          ].whereType<String>().join(' · '),
                          style: const TextStyle(color: Palette.muted),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (!c.item.published)
                              const _Tag('Masqué', Palette.grey),
                            if (c.onPromo)
                              _Tag(c.promotion!.title, Palette.amber),
                            _Tag(
                              c.stock > 0 ? '${c.stock} en stock' : 'Rupture',
                              c.stock > 0 ? Palette.mint : Palette.red,
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          app.money(c.price),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: c.onPromo ? Palette.amber : Palette.text,
                          ),
                        ),
                        if (c.onPromo)
                          Text(
                            app.money(c.basePrice),
                            style: const TextStyle(
                              color: Palette.muted,
                              fontSize: 12,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- Promotions

class _PromosTab extends StatelessWidget {
  const _PromosTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shop = context.read<ShopRepository>();
    return Loader<(List<Promotion>, List<CatalogItem>, List<ShopCategory>)>(
      load: (_) async => (
        await shop.promotions(),
        await shop.catalog(),
        await shop.categories(),
      ),
      builder: (context, data) {
        final (promos, items, cats) = data;
        final t = app.repo.now();
        String target(Promotion p) {
          if (p.itemId != null) {
            return items
                    .where((i) => i.item.id == p.itemId)
                    .map((i) => i.name)
                    .firstOrNull ??
                'Article';
          }
          if (p.categoryId != null) {
            return cats
                    .where((c) => c.id == p.categoryId)
                    .map((c) => 'Catégorie ${c.name}')
                    .firstOrNull ??
                'Catégorie';
          }
          return 'Toute la boutique';
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _addButton(
              'Nouvelle promotion ou soldes',
              () => Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const PromotionForm())),
            ),
            if (promos.isEmpty)
              const EmptyState(
                'Aucune promotion.\nUne promo a une date de début et de fin : elle s’applique et s’arrête toute seule.',
                icon: Icons.local_offer_outlined,
              ),
            for (final p in promos)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  p.title,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                  ),
                                ),
                                if (p.isSale) const _Tag('Soldes', Palette.red),
                                if (t.isBefore(p.startsAt))
                                  const _Tag('À venir', Palette.blue)
                                else if (t.isBefore(p.endsAt))
                                  const _Tag('En cours', Palette.mint)
                                else
                                  const _Tag('Terminée', Palette.grey),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${p.percent != null ? '−${p.percent} %' : app.money(p.promoPrice!)} · ${target(p)}',
                              style: const TextStyle(color: Palette.amber),
                            ),
                            Text(
                              'Du ${dayDate(p.startsAt)} au ${dayDate(p.endsAt)}',
                              style: const TextStyle(color: Palette.muted),
                            ),
                            if (p.details.isNotEmpty) Text(p.details),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          if (await confirm(
                            context,
                            'Supprimer « ${p.title} » ?',
                          )) {
                            await shop.deletePromotion(p.id);
                            app.changed();
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

String dayDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

// ---------------------------------------------------------------- Annonces

class _NewsTab extends StatelessWidget {
  const _NewsTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shop = context.read<ShopRepository>();
    return Loader<List<Announcement>>(
      load: (_) => shop.announcements(),
      builder: (context, list) {
        final t = app.repo.now();
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _addButton('Nouvelle annonce', () => _add(context, app, shop)),
            if (list.isEmpty)
              const EmptyState(
                'Aucune annonce.\nExemple : « Nouvel arrivage de pagnes », « Fermé dimanche ».',
                icon: Icons.campaign_outlined,
              ),
            for (final a in list)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            if (a.body.isNotEmpty) Text(a.body),
                            Text(
                              a.endsAt == null
                                  ? 'Depuis le ${dayDate(a.startsAt)}'
                                  : 'Du ${dayDate(a.startsAt)} au ${dayDate(a.endsAt!)}',
                              style: TextStyle(
                                color: a.endsAt != null && a.endsAt!.isBefore(t)
                                    ? Palette.grey
                                    : Palette.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Supprimer',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await shop.deleteAnnouncement(a.id);
                          app.changed();
                        },
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Future<void> _add(
    BuildContext context,
    AppState app,
    ShopRepository shop,
  ) async {
    final title = TextEditingController();
    final body = TextEditingController();
    int? days;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          backgroundColor: Palette.card,
          title: const Text('Nouvelle annonce'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                decoration: const InputDecoration(hintText: 'Titre'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: body,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Détails (facultatif)',
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final (label, n) in [
                    ('Sans fin', null),
                    ('1 semaine', 7),
                    ('1 mois', 30),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: days == n,
                      onSelected: (_) => setState(() => days = n),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, title.text.trim().isNotEmpty),
              child: const Text('Publier'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final start = app.repo.now();
    await shop.addAnnouncement(
      title: title.text,
      body: body.text,
      startsAt: start,
      endsAt: days == null ? null : start.add(Duration(days: days!)),
    );
    app.changed();
  }
}
