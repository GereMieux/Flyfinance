import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/shop_database.dart';
import '../data/shop_repository.dart';
import 'online_shop_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class _Front {
  _Front(this.items, this.news, this.promos, this.info);
  final List<CatalogItem> items;
  final List<Announcement> news;
  final List<Promotion> promos;
  final ShopInfo info;
}

/// La vitrine telle que la voit un client : annonces, soldes, catégories,
/// articles et modes de paiement.
class StorefrontScreen extends StatefulWidget {
  const StorefrontScreen({super.key});
  @override
  State<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends State<StorefrontScreen> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final shop = context.read<ShopRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Vitrine')),
      body: Loader<_Front>(
        load: (_) async => _Front(
          await shop.catalog(onlyPublished: true),
          await shop.announcements(onlyActive: true),
          await shop.activePromotions(),
          await shop.info(),
        ),
        builder: (context, f) {
          final cats = {
            for (final i in f.items)
              if (i.category != null) i.category!.name,
          }.toList()..sort();
          final list = _category == null
              ? f.items
              : f.items.where((i) => i.category?.name == _category).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Text(
                f.info.shopName,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              for (final p in f.promos.where((p) => p.isSale))
                _banner(
                  Icons.local_fire_department_outlined,
                  Palette.red,
                  '${p.title}${p.percent != null ? ' : −${p.percent} %' : ''}',
                  'Jusqu’au ${dayDate(p.endsAt)}${p.details.isEmpty ? '' : ' · ${p.details}'}',
                ),
              for (final a in f.news)
                _banner(
                  Icons.campaign_outlined,
                  Palette.amber,
                  a.title,
                  a.body,
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
                            label: Text(c ?? 'Tout'),
                            selected: _category == c,
                            onSelected: (_) => setState(() => _category = c),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const EmptyState(
                  'La vitrine est vide.\nMettez des articles en ligne dans Catalogue.',
                  icon: Icons.storefront_outlined,
                ),
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.78,
                children: [for (final i in list) _card(i)],
              ),
              if (f.info.methods.isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Modes de paiement',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final m in f.info.methods)
                      Chip(
                        avatar: Icon(
                          m == 'livraison'
                              ? Icons.local_shipping_outlined
                              : Icons.phone_android,
                          size: 18,
                        ),
                        label: Text(onlinePayMethods[m]!),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: () => shareCatalog(context, shop),
                icon: const Icon(Icons.share_outlined),
                label: const Text('Partager la vitrine sur WhatsApp'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _banner(IconData icon, Color color, String title, String body) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Panel(
          color: color.withValues(alpha: 0.14),
          child: Row(
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                    if (body.isNotEmpty) Text(body),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _card(CatalogItem i) => Panel(
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Palette.cardHigh,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    i.name.characters.first.toUpperCase(),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      color: Palette.muted,
                    ),
                  ),
                ),
              ),
              if (i.onPromo)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Palette.amber,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '−${(100 - i.price * 100 / i.basePrice).round()} %',
                      style: const TextStyle(
                        color: Palette.ink,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              if (i.stock <= 0)
                Positioned(
                  bottom: 6,
                  left: 6,
                  child: Text(
                    'Épuisé',
                    style: TextStyle(
                      color: Palette.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          i.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          [
            i.brand?.name,
            if (i.sizes.isNotEmpty) i.sizes.join('/'),
            if (i.colors.isNotEmpty) i.colors.join('/'),
          ].whereType<String>().join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: Palette.muted, fontSize: 12),
        ),
        Row(
          children: [
            Flexible(
              child: Text(
                fcfa(i.price),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: i.onPromo ? Palette.amber : Palette.text,
                ),
              ),
            ),
            if (i.onPromo) ...[
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  fcfa(i.basePrice, unit: false),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Palette.muted,
                    fontSize: 12,
                    decoration: TextDecoration.lineThrough,
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}
