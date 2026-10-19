import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/database.dart';
import '../data/repository.dart';
import 'credits_screen.dart';
import 'sales_list_screen.dart';
import 'stock_screen.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Kind { tout, articles, clients, ventes, fournisseurs }

class _Results {
  _Results(this.stock, this.contacts, this.sales);
  final List<ProductStock> stock;
  final List<Contact> contacts;
  final List<SaleSummary> sales;
}

/// Recherche dans tout ce que contient la boutique, hors ligne.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key, this.onVoice});
  final VoidCallback? onVoice;
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _q = TextEditingController();
  _Kind _kind = _Kind.tout;

  Future<_Results> _load(Repository r) async =>
      _Results(await r.stock(), await r.contacts(), await r.sales());

  void _open(Widget w) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                if (Navigator.canPop(context)) const BackButton(),
                Expanded(
                  child: TextField(
                    controller: _q,
                    autofocus: Navigator.canPop(context),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search),
                      hintText: 'Article, client, vente…',
                      suffixIcon: widget.onVoice == null
                          ? null
                          : IconButton(
                              tooltip: 'Chercher à la voix',
                              onPressed: widget.onVoice,
                              icon: Icon(Icons.mic, color: Palette.amber),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final k in _Kind.values)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(switch (k) {
                        _Kind.tout => 'Tout',
                        _Kind.articles => 'Articles',
                        _Kind.clients => 'Clients',
                        _Kind.ventes => 'Ventes',
                        _Kind.fournisseurs => 'Fournisseurs',
                      }),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Loader<_Results>(
              load: _load,
              builder: (context, r) {
                final q = normalize(_q.text);
                bool hit(String s) => q.isEmpty || normalize(s).contains(q);
                final tiles = <Widget>[];
                if (_kind == _Kind.tout || _kind == _Kind.articles) {
                  for (final s in r.stock.where((s) => hit(s.product.name))) {
                    tiles.add(
                      _tile(
                        'Article',
                        Palette.mint,
                        s.product.name,
                        '${s.qty} ${s.product.unit} · ${fcfa(s.product.price)}',
                        () => _open(const StockScreen()),
                      ),
                    );
                  }
                }
                for (final c in r.contacts.where((c) => hit(c.name))) {
                  final supplier = c.kind == 'fournisseur';
                  if (_kind == _Kind.tout ||
                      (_kind == _Kind.clients && !supplier) ||
                      (_kind == _Kind.fournisseurs && supplier)) {
                    tiles.add(
                      _tile(
                        supplier ? 'Fournisseur' : 'Client',
                        supplier ? Palette.purple : Palette.amber,
                        c.name,
                        c.phone ?? '',
                        () => _open(const CreditsScreen()),
                      ),
                    );
                  }
                }
                if (_kind == _Kind.tout || _kind == _Kind.ventes) {
                  for (final s
                      in r.sales
                          .where(
                            (s) =>
                                q.isNotEmpty &&
                                hit(s.contact?.name ?? 'client de passage'),
                          )
                          .take(20)) {
                    tiles.add(
                      _tile(
                        'Vente',
                        Palette.blue,
                        'Vente · ${s.contact?.name ?? 'client de passage'}',
                        '${shortDate(s.sale.createdAt)} · ${app.money(s.sale.total)} · ${s.status.label}',
                        () => _open(const SalesListScreen()),
                      ),
                    );
                  }
                }
                return ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (q.isEmpty && widget.onVoice != null)
                      Panel(
                        color: Palette.hero,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Essayez à la voix',
                              style: TextStyle(color: Palette.muted),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              '« Combien de riz il reste ? »',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text(
                              '« Combien me doit Kouassi ? »',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '${tiles.length} résultat${tiles.length > 1 ? 's' : ''}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    ...tiles,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(
    String kind,
    Color color,
    String title,
    String sub,
    VoidCallback onTap,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Palette.card,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: onTap,
        leading: Container(
          width: 92,
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            kind,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(sub, style: TextStyle(color: Palette.muted)),
        trailing: Icon(Icons.chevron_right, color: Palette.muted),
      ),
    ),
  );
}
