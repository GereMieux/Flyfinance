import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/database.dart';
import '../data/repository.dart';
import 'receipt_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class _SaleData {
  _SaleData(this.stock, this.clients);
  final List<ProductStock> stock;
  final List<Contact> clients;
}

/// Choix proposé par la barre client : un client existant, ou un nom tapé
/// qui deviendra un nouveau client à l'enregistrement de la vente.
class _ClientOption {
  const _ClientOption.existing(Contact this.contact) : newName = null;
  const _ClientOption.create(String this.newName) : contact = null;
  final Contact? contact;
  final String? newName;
}

class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key});
  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  final _qty = <int, int>{};

  /// Ordre d'ajout au panier, pour afficher le dernier article en haut.
  final _order = <int>[];
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _clientText = TextEditingController();
  final _clientFocus = FocusNode();
  bool _wholesale = false;

  /// Client de passage (aucun nom) ou client nommé.
  bool _walkIn = true;
  int? _clientId;
  String? _clientName;
  String? _newClient;
  String? _newPhone;
  String _payMode = 'tout';
  int _customPaid = 0;
  String _method = 'especes';
  bool _saving = false;

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    _clientText.dispose();
    _clientFocus.dispose();
    super.dispose();
  }

  int _price(Product p) => _wholesale ? (p.wholesalePrice ?? p.price) : p.price;

  void _setQty(ProductStock s, int n) {
    final id = s.product.id;
    if (n > s.qty) {
      toast(context, 'Il ne reste que ${s.qty} ${s.product.name}.');
      n = s.qty;
    }
    setState(() {
      if (n <= 0) {
        _qty.remove(id);
        _order.remove(id);
      } else {
        _qty[id] = n;
        if (!_order.contains(id)) _order.insert(0, id);
      }
    });
  }

  /// Pavé numérique : la quantité se tape d'un coup au lieu d'appuyer
  /// plusieurs fois sur +.
  Future<void> _typeQty(ProductStock s) async {
    final v = await askQuantity(
      context,
      title: s.product.name,
      unitPrice: _price(s.product),
      initial: _qty[s.product.id] ?? 0,
      max: s.qty,
    );
    if (v != null) _setQty(s, v);
  }

  /// Article choisi dans la barre de recherche : on en ajoute un au panier
  /// et la barre se vide pour taper l'article suivant.
  void _pick(ProductStock s) {
    if (s.qty <= 0) {
      toast(context, '${s.product.name} est en rupture de stock.');
    } else {
      _setQty(s, (_qty[s.product.id] ?? 0) + 1);
    }
    _search.clear();
    _searchFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Loader<_SaleData>(
      load: (r) async =>
          _SaleData(await r.stock(), await r.contacts(kind: 'client')),
      builder: (context, d) {
        final byId = {for (final s in d.stock) s.product.id: s};
        final cart = [
          for (final id in _order)
            if (byId[id] != null) byId[id]!,
        ];
        final others = d.stock
            .where((s) => !_qty.containsKey(s.product.id))
            .toList();
        final total = cart.fold<int>(
          0,
          (a, s) => a + _qty[s.product.id]! * _price(s.product),
        );
        final paid = switch (_payMode) {
          'tout' => total,
          'moitie' => total ~/ 2,
          'rien' => 0,
          _ => _customPaid.clamp(0, total),
        };
        return Scaffold(
          appBar: AppBar(
            title: const Text('Vendre'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: FilterChip(
                  label: const Text('Prix de gros'),
                  selected: _wholesale,
                  onSelected: (v) => setState(() => _wholesale = v),
                ),
              ),
            ],
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: _clientBar(d),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: _productBar(d),
              ),
              Expanded(
                child: d.stock.isEmpty
                    ? const EmptyState(
                        'Aucun article. Ajoutez vos articles dans le Stock.',
                        icon: Icons.inventory_2_outlined,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        children: [
                          if (cart.isNotEmpty) ...[
                            _header(
                              'Panier · ${cart.length} article${cart.length > 1 ? 's' : ''}',
                            ),
                            for (final s in cart) _tile(s, inCart: true),
                            if (others.isNotEmpty) _header('Autres articles'),
                          ],
                          for (final s in others) _tile(s),
                        ],
                      ),
              ),
              if (total > 0) _checkout(app, d, total, paid),
            ],
          ),
        );
      },
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
    child: Text(
      text,
      style: TextStyle(color: Palette.muted, fontWeight: FontWeight.w700),
    ),
  );

  // ---------- Barre client ----------

  Widget _clientBar(_SaleData d) {
    final segments = SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        showSelectedIcon: false,
        style: SegmentedButton.styleFrom(
          selectedBackgroundColor: Palette.amber,
          selectedForegroundColor: Palette.ink,
          side: BorderSide(color: Palette.line),
        ),
        segments: const [
          ButtonSegment(value: true, label: Text('De passage')),
          ButtonSegment(value: false, label: Text('Client connu')),
        ],
        selected: {_walkIn},
        onSelectionChanged: (s) {
          setState(() => _walkIn = s.first);
          if (!_walkIn && _clientName == null) _clientFocus.requestFocus();
        },
      ),
    );
    if (_walkIn) return segments;
    final chosen = _clientName ?? _newClient;
    return Column(
      children: [
        segments,
        const SizedBox(height: 8),
        if (chosen != null)
          Material(
            color: Palette.cardHigh,
            borderRadius: BorderRadius.circular(16),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              leading: Icon(Icons.person, color: Palette.mint),
              title: Text(
                chosen,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: _newClient != null
                  ? Text(
                      _newPhone == null
                          ? 'Nouveau client'
                          : 'Nouveau client · $_newPhone',
                      style: TextStyle(color: Palette.amber),
                    )
                  : null,
              trailing: IconButton(
                tooltip: 'Changer de client',
                onPressed: () {
                  setState(() {
                    _clientId = null;
                    _clientName = null;
                    _newClient = null;
                    _newPhone = null;
                  });
                  _clientText.clear();
                  _clientFocus.requestFocus();
                },
                icon: const Icon(Icons.close),
              ),
            ),
          )
        else
          RawAutocomplete<_ClientOption>(
            textEditingController: _clientText,
            focusNode: _clientFocus,
            optionsBuilder: (v) {
              final q = normalize(v.text);
              if (q.isEmpty) {
                return [for (final c in d.clients) _ClientOption.existing(c)];
              }
              final found = d.clients
                  .where((c) => normalize(c.name).contains(q))
                  .toList();
              return [
                for (final c in found) _ClientOption.existing(c),
                if (!found.any((c) => normalize(c.name) == q))
                  _ClientOption.create(v.text.trim()),
              ];
            },
            displayStringForOption: (o) => o.contact?.name ?? o.newName!,
            onSelected: _chooseClient,
            fieldViewBuilder: (context, controller, focus, submit) => TextField(
              controller: controller,
              focusNode: focus,
              textCapitalization: TextCapitalization.words,
              onSubmitted: (_) => submit(),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.person_search_outlined),
                hintText: 'Nom du client',
              ),
            ),
            optionsViewBuilder: (context, select, options) => _optionsView(
              options,
              select,
              (o) => o.contact != null
                  ? ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(o.contact!.name),
                      subtitle: o.contact!.phone == null
                          ? null
                          : Text(
                              o.contact!.phone!,
                              style: TextStyle(color: Palette.muted),
                            ),
                    )
                  : ListTile(
                      leading: Icon(
                        Icons.person_add_alt_1,
                        color: Palette.amber,
                      ),
                      title: Text('Nouveau client : « ${o.newName} »'),
                    ),
            ),
          ),
      ],
    );
  }

  Future<void> _chooseClient(_ClientOption o) async {
    if (o.contact != null) {
      setState(() {
        _clientId = o.contact!.id;
        _clientName = o.contact!.name;
      });
      return;
    }
    final phone = await _askPhone(o.newName!);
    if (phone == null) {
      _clientText.clear();
      return;
    }
    setState(() {
      _newClient = o.newName;
      _newPhone = phone.trim().isEmpty ? null : phone.trim();
    });
  }

  /// Confirme l'ajout d'un nouveau client ; le téléphone est facultatif.
  /// Renvoie null si l'utilisateur annule.
  Future<String?> _askPhone(String name) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: Text('Ajouter $name'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Téléphone (facultatif)',
            prefixIcon: Icon(Icons.phone_outlined),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  // ---------- Barre article ----------

  Widget _productBar(_SaleData d) => RawAutocomplete<ProductStock>(
    textEditingController: _search,
    focusNode: _searchFocus,
    optionsBuilder: (v) {
      final q = normalize(v.text);
      if (q.isEmpty) return const [];
      final found = d.stock
          .where((s) => normalize(s.product.name).contains(q))
          .toList();
      // Les noms qui commencent par le texte tapé passent devant.
      found.sort((a, b) {
        final pa = normalize(a.product.name).startsWith(q) ? 0 : 1;
        final pb = normalize(b.product.name).startsWith(q) ? 0 : 1;
        return pa != pb ? pa - pb : a.product.name.compareTo(b.product.name);
      });
      return found.take(8);
    },
    displayStringForOption: (s) => s.product.name,
    onSelected: _pick,
    fieldViewBuilder: (context, controller, focus, submit) => TextField(
      controller: controller,
      focusNode: focus,
      onSubmitted: (_) => submit(),
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        hintText: 'Taper le nom de l’article',
      ),
    ),
    optionsViewBuilder: (context, select, options) => _optionsView(
      options,
      select,
      (s) => ListTile(
        enabled: s.qty > 0,
        title: Text(
          s.product.name,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          s.qty > 0 ? '${s.qty} en stock' : 'Rupture de stock',
          style: TextStyle(color: s.low ? Palette.red : Palette.muted),
        ),
        trailing: Text(
          fcfa(_price(s.product)),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    ),
  );

  Widget _optionsView<T extends Object>(
    Iterable<T> options,
    void Function(T) select,
    Widget Function(T) row,
  ) => Align(
    alignment: Alignment.topLeft,
    child: Material(
      color: Palette.cardHigh,
      elevation: 6,
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: 320,
          maxWidth: MediaQuery.sizeOf(context).width - 32,
        ),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          shrinkWrap: true,
          children: [
            for (final o in options)
              InkWell(onTap: () => select(o), child: row(o)),
          ],
        ),
      ),
    ),
  );

  // ---------- Liste des articles ----------

  Widget _tile(ProductStock s, {bool inCart = false}) {
    final n = _qty[s.product.id] ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Panel(
        color: inCart ? Palette.cardHigh : null,
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Expanded(
              // Toucher l'article en ajoute un, comme le bouton +.
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: n >= s.qty ? null : () => _setQty(s, n + 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.product.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      inCart
                          ? '${fcfa(_price(s.product))} × $n = ${fcfa(_price(s.product) * n)}'
                          : '${fcfa(_price(s.product))} · ${s.qty} en stock',
                      style: TextStyle(
                        color: inCart
                            ? Palette.mint
                            : (s.low ? Palette.red : Palette.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Les boutons − et la quantité n'apparaissent que pour les
            // articles déjà dans le panier : moins de boutons à l'écran.
            // Toucher la quantité ouvre le pavé numérique.
            if (n > 0) ...[
              IconButton.outlined(
                tooltip: 'Retirer un',
                iconSize: 26,
                onPressed: () => _setQty(s, n - 1),
                icon: const Icon(Icons.remove),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _typeQty(s),
                child: SizedBox(
                  width: 44,
                  height: 48,
                  child: Center(
                    child: Text(
                      '$n',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Palette.mint,
                        decoration: TextDecoration.underline,
                        decorationColor: Palette.mint,
                      ),
                    ),
                  ),
                ),
              ),
            ] else
              IconButton(
                tooltip: 'Taper la quantité',
                iconSize: 26,
                onPressed: s.qty == 0 ? null : () => _typeQty(s),
                icon: Icon(Icons.dialpad, color: Palette.mint),
              ),
            IconButton.filled(
              tooltip: 'Ajouter un',
              iconSize: 28,
              style: IconButton.styleFrom(backgroundColor: Palette.green),
              onPressed: n >= s.qty ? null : () => _setQty(s, n + 1),
              icon: const Icon(Icons.add, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  // ---------- Paiement ----------

  bool get _hasClient => !_walkIn && (_clientId != null || _newClient != null);

  Widget _checkout(AppState app, _SaleData d, int total, int paid) {
    final credit = paid < total;
    final needsClient = credit && !_hasClient;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Palette.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _hasClient
                        ? 'Total · ${_clientName ?? _newClient}'
                        : 'Total · client de passage',
                    style: TextStyle(color: Palette.muted, fontSize: 16),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  fcfa(total),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in const [
                  ('tout', 'Tout payé'),
                  ('moitie', 'Moitié'),
                  ('rien', 'À crédit'),
                  ('autre', 'Autre montant'),
                ])
                  ChoiceChip(
                    label: Text(m.$2),
                    selected: _payMode == m.$1,
                    onSelected: (_) async {
                      if (m.$1 == 'autre') {
                        final v = await askNumber(
                          context,
                          title: 'Montant payé maintenant',
                        );
                        if (v == null) return;
                        _customPaid = v;
                      }
                      setState(() => _payMode = m.$1);
                    },
                  ),
              ],
            ),
            if (paid > 0) ...[
              const SizedBox(height: 8),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final e in paymentMethods.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: _method == e.key,
                          onSelected: (_) => setState(() => _method = e.key),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (credit)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  needsClient
                      ? 'Pour une vente à crédit, choisissez « Client connu » et son nom en haut.'
                      : 'Reste à payer : ${fcfa(total - paid)}',
                  style: TextStyle(
                    color: needsClient ? Palette.red : Palette.amber,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(62),
                  textStyle: const TextStyle(
                    fontFamily: appFont,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: needsClient || _saving
                    ? null
                    : () => _save(app, d, paid),
                icon: const Icon(Icons.check_circle_outline, size: 26),
                label: Text(_saving ? 'Enregistrement…' : 'Valider la vente'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save(AppState app, _SaleData d, int paid) async {
    setState(() => _saving = true);
    try {
      int? contactId;
      if (_hasClient) {
        if (_clientId == null) {
          // Le client est créé une seule fois, même si la vente échoue
          // et qu'on la valide à nouveau.
          final id = await app.repo.addContact(_newClient!, phone: _newPhone);
          _clientId = id;
          _clientName = _newClient;
          _newClient = null;
          _newPhone = null;
        }
        contactId = _clientId;
      }
      final saleId = await app.repo.recordSale(
        lines: [
          for (final s in d.stock)
            if ((_qty[s.product.id] ?? 0) > 0)
              CartLine(
                s.product,
                _qty[s.product.id]!,
                unitPrice: _price(s.product),
              ),
        ],
        contactId: contactId,
        paidNow: paid,
        method: _method,
      );
      app.changed();
      if (!mounted) return;
      // Le reçu s'ouvre tout de suite : imprimer, partager ou terminer.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => ReceiptScreen(saleId: saleId, justSold: true),
        ),
      );
    } catch (e) {
      if (mounted) {
        toast(context, e.toString().replaceFirst(RegExp(r'^\w+Error: '), ''));
      }
      setState(() => _saving = false);
    }
  }
}
