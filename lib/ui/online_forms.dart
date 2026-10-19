import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/database.dart';
import '../data/repository.dart';
import '../data/shop_database.dart';
import '../data/shop_repository.dart';
import 'online_shop_screen.dart';
import 'theme.dart';
import 'widgets.dart';

Widget _label(String text) => Padding(
  padding: const EdgeInsets.only(top: 16, bottom: 6),
  child: Text(
    text,
    style: TextStyle(fontWeight: FontWeight.w700, color: Palette.muted),
  ),
);

/// Champ texte avec des choix déjà connus en dessous (catégories, marques).
class _Suggest extends StatelessWidget {
  const _Suggest(this.controller, this.hint, this.options, this.onPick);
  final TextEditingController controller;
  final String hint;
  final List<String> options;
  final VoidCallback onPick;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextField(
        controller: controller,
        decoration: InputDecoration(hintText: hint),
      ),
      if (options.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final o in options)
                ActionChip(
                  label: Text(o),
                  onPressed: () {
                    controller.text = o;
                    onPick();
                  },
                ),
            ],
          ),
        ),
    ],
  );
}

// ------------------------------------------------------- Article en ligne

class ShopItemForm extends StatefulWidget {
  const ShopItemForm({super.key, this.item});

  /// Article déjà en ligne à modifier ; sinon on choisit dans le stock.
  final CatalogItem? item;

  @override
  State<ShopItemForm> createState() => _ShopItemFormState();
}

class _ShopItemFormState extends State<ShopItemForm> {
  Product? _product;
  late final _category = TextEditingController(
    text: widget.item?.category?.name,
  );
  late final _brand = TextEditingController(text: widget.item?.brand?.name);
  late final _description = TextEditingController(
    text: widget.item?.item.description,
  );
  late final _sizes = TextEditingController(text: widget.item?.item.sizes);
  late final _colors = TextEditingController(text: widget.item?.item.colors);
  late final _price = TextEditingController(
    text: widget.item?.item.onlinePrice?.toString(),
  );
  late bool _published = widget.item?.item.published ?? true;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shop = context.read<ShopRepository>();
    final editing = widget.item != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(editing ? widget.item!.name : 'Mettre en ligne'),
        actions: [
          if (editing)
            IconButton(
              tooltip: 'Retirer de la vente en ligne',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                if (await confirm(
                  context,
                  'Retirer cet article du catalogue en ligne ?',
                )) {
                  await shop.removeItem(widget.item!.item.id);
                  app.changed();
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body:
          Loader<
            (List<Product>, List<ShopCategory>, List<ShopBrand>, Set<int>)
          >(
            load: (r) async => (
              await r.products(),
              await shop.categories(),
              await shop.brands(),
              {for (final c in await shop.catalog()) c.product.id},
            ),
            builder: (context, data) {
              final (products, cats, brands, online) = data;
              final free = products
                  .where((p) => !online.contains(p.id))
                  .toList();
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                children: [
                  if (!editing) ...[
                    _label('Article du stock'),
                    if (free.isEmpty)
                      Text(
                        'Tous vos articles sont déjà en ligne. Ajoutez-en dans Stock.',
                        style: TextStyle(color: Palette.muted),
                      )
                    else
                      DropdownButtonFormField<Product>(
                        initialValue: _product,
                        isExpanded: true,
                        hint: const Text('Choisir un article'),
                        items: [
                          for (final p in free)
                            DropdownMenuItem(
                              value: p,
                              child: Text('${p.name} · ${fcfa(p.price)}'),
                            ),
                        ],
                        onChanged: (p) => setState(() => _product = p),
                      ),
                  ],
                  _label('Catégorie'),
                  _Suggest(
                    _category,
                    'Ex. : Vêtements, Chaussures, Alimentation',
                    [for (final c in cats) c.name],
                    () => setState(() {}),
                  ),
                  _label('Prix en ligne (vide = même prix qu’en boutique)'),
                  TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: fcfa(
                        widget.item?.product.price ?? _product?.price ?? 0,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: EdgeInsets.zero,
                    title: const Text(
                      'Plus de détails : marque, tailles, couleurs',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    initiallyExpanded:
                        (widget.item?.item.sizes ?? '').isNotEmpty ||
                        (widget.item?.item.colors ?? '').isNotEmpty,
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Marque'),
                      _Suggest(_brand, 'Ex. : Nike, Uniwax (facultatif)', [
                        for (final b in brands) b.name,
                      ], () => setState(() {})),
                      _label('Tailles proposées'),
                      TextField(
                        controller: _sizes,
                        decoration: const InputDecoration(
                          hintText: 'Ex. : S, M, L, XL ou 40, 41, 42',
                        ),
                      ),
                      _label('Couleurs proposées'),
                      TextField(
                        controller: _colors,
                        decoration: const InputDecoration(
                          hintText: 'Ex. : Noir, Blanc, Rouge',
                        ),
                      ),
                      _label('Description'),
                      TextField(
                        controller: _description,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          hintText: 'Matière, contenance, conseils…',
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Visible par les clients'),
                    value: _published,
                    onChanged: (v) => setState(() => _published = v),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: editing || _product != null
                        ? () => _save(app, shop)
                        : null,
                    child: Text(editing ? 'Enregistrer' : 'Mettre en ligne'),
                  ),
                ],
              );
            },
          ),
    );
  }

  Future<void> _save(AppState app, ShopRepository shop) async {
    final price = int.tryParse(_price.text.replaceAll(RegExp(r'[^0-9]'), ''));
    await shop.saveItem(
      productId: widget.item?.product.id ?? _product!.id,
      category: _category.text,
      brand: _brand.text,
      description: _description.text,
      sizes: splitOptions(_sizes.text),
      colors: splitOptions(_colors.text),
      onlinePrice: price,
      published: _published,
    );
    app.changed();
    if (mounted) {
      Navigator.pop(context);
      toast(context, 'Catalogue mis à jour.');
    }
  }
}

// ------------------------------------------------------- Promotion

class PromotionForm extends StatefulWidget {
  const PromotionForm({super.key});
  @override
  State<PromotionForm> createState() => _PromotionFormState();
}

class _PromotionFormState extends State<PromotionForm> {
  final _title = TextEditingController();
  final _details = TextEditingController();
  final _value = TextEditingController();
  bool _isSale = false;

  /// 'tout', 'categorie' ou 'article'.
  String _target = 'tout';
  int? _categoryId;
  CatalogItem? _item;
  bool _fixedPrice = false;
  late DateTime _start = _today();
  late DateTime _end = _start.add(const Duration(days: 7));

  DateTime _today() {
    final n = context.read<AppState>().repo.now();
    return DateTime(n.year, n.month, n.day);
  }

  Future<DateTime?> _pick(DateTime initial) => showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(2020),
    lastDate: DateTime(2100),
    helpText: 'Choisir la date',
    cancelText: 'Annuler',
    confirmText: 'Valider',
  );

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shop = context.read<ShopRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle promotion')),
      body: Loader<(List<CatalogItem>, List<ShopCategory>)>(
        load: (_) async => (await shop.catalog(), await shop.categories()),
        builder: (context, data) {
          final (items, cats) = data;
          if (_target != 'article') _fixedPrice = false;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              _label('Nom de la promotion'),
              TextField(
                controller: _title,
                decoration: const InputDecoration(
                  hintText: 'Ex. : Fête des mères, Black Friday',
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('C’est une période de soldes'),
                value: _isSale,
                onChanged: (v) => setState(() => _isSale = v),
              ),
              _label('Sur quoi ?'),
              Wrap(
                spacing: 8,
                children: [
                  for (final (k, label) in [
                    ('tout', 'Toute la boutique'),
                    ('categorie', 'Une catégorie'),
                    ('article', 'Un article'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _target == k,
                      onSelected: (_) => setState(() => _target = k),
                    ),
                ],
              ),
              if (_target == 'categorie') ...[
                const SizedBox(height: 8),
                if (cats.isEmpty)
                  Text(
                    'Aucune catégorie : donnez-en une à vos articles dans Catalogue.',
                    style: TextStyle(color: Palette.muted),
                  ),
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in cats)
                      ChoiceChip(
                        label: Text(c.name),
                        selected: _categoryId == c.id,
                        onSelected: (_) => setState(() => _categoryId = c.id),
                      ),
                  ],
                ),
              ],
              if (_target == 'article') ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<CatalogItem>(
                  initialValue: _item,
                  isExpanded: true,
                  hint: const Text('Choisir un article en ligne'),
                  items: [
                    for (final i in items)
                      DropdownMenuItem(
                        value: i,
                        child: Text('${i.name} · ${fcfa(i.basePrice)}'),
                      ),
                  ],
                  onChanged: (i) => setState(() => _item = i),
                ),
              ],
              _label('Réduction'),
              if (_target == 'article')
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('En pourcentage'),
                        selected: !_fixedPrice,
                        onSelected: (_) => setState(() => _fixedPrice = false),
                      ),
                      ChoiceChip(
                        label: const Text('Prix promotionnel'),
                        selected: _fixedPrice,
                        onSelected: (_) => setState(() => _fixedPrice = true),
                      ),
                    ],
                  ),
                ),
              if (!_fixedPrice)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final n in [10, 20, 30, 50])
                        ChoiceChip(
                          label: Text('−$n %'),
                          selected: _value.text == '$n',
                          onSelected: (_) => setState(() => _value.text = '$n'),
                        ),
                    ],
                  ),
                ),
              TextField(
                controller: _value,
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: _fixedPrice
                      ? 'Nouveau prix en FCFA'
                      : 'Autre pourcentage',
                  suffixText: _fixedPrice ? 'FCFA' : '%',
                ),
              ),
              _label('Dates'),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final d = await _pick(_start);
                        if (d != null) {
                          setState(() {
                            final len = _end.difference(_start);
                            _start = d;
                            _end = d.add(len);
                          });
                        }
                      },
                      child: Text('Début ${dayDate(_start)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () async {
                        final d = await _pick(_end);
                        if (d != null) setState(() => _end = d);
                      },
                      child: Text('Fin ${dayDate(_end)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final (label, n) in [
                    ('3 jours', 3),
                    ('1 semaine', 7),
                    ('2 semaines', 14),
                    ('1 mois', 30),
                  ])
                    ActionChip(
                      label: Text(label),
                      onPressed: () =>
                          setState(() => _end = _start.add(Duration(days: n))),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'La promo commence à minuit le jour du début et s’arrête à minuit le jour de fin.',
                style: TextStyle(color: Palette.muted, fontSize: 13),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Ajouter un message pour les clients',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                children: [
                  TextField(
                    controller: _details,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      hintText: 'Ex. : dans la limite des stocks',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => _save(app, shop),
                child: const Text('Enregistrer la promotion'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save(AppState app, ShopRepository shop) async {
    final n = int.tryParse(_value.text.replaceAll(RegExp(r'[^0-9]'), ''));
    final title = _title.text.trim().isEmpty
        ? (_isSale ? 'Soldes' : 'Promotion')
        : _title.text;
    try {
      if (_target == 'categorie' && _categoryId == null) {
        throw ArgumentError('Choisissez la catégorie.');
      }
      if (_target == 'article' && _item == null) {
        throw ArgumentError('Choisissez l’article.');
      }
      if (n == null) throw ArgumentError('Indiquez la réduction.');
      await shop.addPromotion(
        title: title,
        details: _details.text,
        percent: _fixedPrice ? null : n,
        promoPrice: _fixedPrice ? n : null,
        itemId: _target == 'article' ? _item!.item.id : null,
        categoryId: _target == 'categorie' ? _categoryId : null,
        isSale: _isSale,
        startsAt: _start,
        endsAt: _end,
      );
      app.changed();
      if (mounted) {
        Navigator.pop(context);
        toast(context, 'Promotion enregistrée.');
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    }
  }
}

// ------------------------------------------------------- Nouvelle commande

class NewOrderScreen extends StatefulWidget {
  const NewOrderScreen({super.key});
  @override
  State<NewOrderScreen> createState() => _NewOrderScreenState();
}

class _NewOrderScreenState extends State<NewOrderScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _note = TextEditingController();
  final _fee = TextEditingController();
  final _lines = <OrderItem>[];
  String? _method;
  bool _saving = false;
  bool _feeSet = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shop = context.read<ShopRepository>();
    return Scaffold(
      appBar: AppBar(title: const Text('Nouvelle commande')),
      body: Loader<(List<CatalogItem>, ShopInfo, List<Contact>)>(
        load: (r) async => (
          await shop.catalog(onlyPublished: true),
          await shop.info(),
          await r.contacts(kind: 'client'),
        ),
        builder: (context, data) {
          final (items, info, clients) = data;
          final methods = info.methods.isEmpty ? ['livraison'] : info.methods;
          _method ??= methods.first;
          if (!_feeSet && info.deliveryFee > 0) {
            _fee.text = '${info.deliveryFee}';
            _feeSet = true;
          }
          final total = _lines.fold(0, (s, l) => s + l.total);
          final fee = int.tryParse(_fee.text) ?? 0;
          final q = normalize(_name.text);
          final matches = q.length < 2
              ? <Contact>[]
              : clients
                    .where((c) => normalize(c.name).contains(q))
                    .take(4)
                    .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            children: [
              _label('Client'),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(hintText: 'Nom du client'),
              ),
              if (matches.isNotEmpty)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final c in matches)
                      ActionChip(
                        avatar: const Icon(Icons.person_outline, size: 18),
                        label: Text(c.name),
                        onPressed: () => setState(() {
                          _name.text = c.name;
                          _phone.text = c.phone ?? '';
                        }),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(hintText: 'Téléphone'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _address,
                decoration: const InputDecoration(
                  hintText: 'Adresse de livraison (quartier, repère)',
                ),
              ),
              _label('Articles'),
              for (var i = 0; i < _lines.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Panel(
                    padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_lines[i].qty} × ${_lines[i].item.name}'
                            '${[_lines[i].size, _lines[i].color].where((s) => s.isNotEmpty).map((s) => ' · $s').join()}',
                          ),
                        ),
                        Text(
                          app.money(_lines[i].total),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _lines.removeAt(i)),
                        ),
                      ],
                    ),
                  ),
                ),
              OutlinedButton.icon(
                onPressed: items.isEmpty ? null : () => _addLine(items),
                icon: const Icon(Icons.add),
                label: Text(
                  items.isEmpty
                      ? 'Aucun article en ligne pour l’instant'
                      : 'Ajouter un article',
                ),
              ),
              _label('Paiement'),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  for (final m in methods)
                    ChoiceChip(
                      label: Text(onlinePayMethods[m]!),
                      selected: _method == m,
                      onSelected: (_) => setState(() => _method = m),
                    ),
                ],
              ),
              if (info.methods.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Ajoutez vos numéros Orange Money et Wave dans Paiement et livraison (⚙).',
                    style: TextStyle(color: Palette.muted, fontSize: 13),
                  ),
                ),
              _label('Frais de livraison'),
              TextField(
                controller: _fee,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: '0',
                  suffixText: 'FCFA',
                ),
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text(
                  'Ajouter une note',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                children: [
                  TextField(
                    controller: _note,
                    decoration: const InputDecoration(
                      hintText: 'Heure de livraison, consignes…',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Panel(
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Total à payer',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    Text(
                      app.money(total + fee),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : () => _save(app, shop),
                child: const Text('Enregistrer la commande'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _addLine(List<CatalogItem> items) async {
    final line = await showModalBottomSheet<OrderItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Palette.card,
      showDragHandle: true,
      builder: (_) => _LinePicker(items),
    );
    if (line != null) setState(() => _lines.add(line));
  }

  Future<void> _save(AppState app, ShopRepository shop) async {
    setState(() => _saving = true);
    try {
      final id = await shop.createOrder(
        customerName: _name.text,
        phone: _phone.text,
        address: _address.text,
        note: _note.text,
        payMethod: _method!,
        deliveryFee:
            int.tryParse(_fee.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        items: _lines,
      );
      app.changed();
      if (mounted) {
        Navigator.of(
          context,
        ).pushReplacement(MaterialPageRoute(builder: (_) => OrderScreen(id)));
      }
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _LinePicker extends StatefulWidget {
  const _LinePicker(this.items);
  final List<CatalogItem> items;
  @override
  State<_LinePicker> createState() => _LinePickerState();
}

class _LinePickerState extends State<_LinePicker> {
  final _search = TextEditingController();
  CatalogItem? _item;
  int _qty = 1;
  String _size = '';
  String _color = '';

  @override
  Widget build(BuildContext context) {
    final q = normalize(_search.text);
    final list = widget.items
        .where((i) => normalize(i.name).contains(q))
        .toList();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: _item == null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Taper le nom de l’article',
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                  ),
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final i in list)
                        ListTile(
                          enabled: i.stock > 0,
                          title: Text(i.name),
                          subtitle: Text(
                            i.stock > 0 ? '${i.stock} en stock' : 'Rupture',
                          ),
                          trailing: Text(
                            fcfa(i.price),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          onTap: () => setState(() {
                            _item = i;
                            _size = i.sizes.firstOrNull ?? '';
                            _color = i.colors.firstOrNull ?? '';
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _item!.name,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(fcfa(_item!.price)),
                if (_item!.sizes.isNotEmpty) ...[
                  _label('Taille'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final s in _item!.sizes)
                        ChoiceChip(
                          label: Text(s),
                          selected: _size == s,
                          onSelected: (_) => setState(() => _size = s),
                        ),
                    ],
                  ),
                ],
                if (_item!.colors.isNotEmpty) ...[
                  _label('Couleur'),
                  Wrap(
                    spacing: 6,
                    children: [
                      for (final c in _item!.colors)
                        ChoiceChip(
                          label: Text(c),
                          selected: _color == c,
                          onSelected: (_) => setState(() => _color = c),
                        ),
                    ],
                  ),
                ],
                _label('Quantité'),
                Row(
                  children: [
                    IconButton.outlined(
                      onPressed: _qty > 1 ? () => setState(() => _qty--) : null,
                      icon: const Icon(Icons.remove),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '$_qty',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      onPressed: _qty < _item!.stock
                          ? () => setState(() => _qty++)
                          : null,
                      icon: const Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      OrderItem(_item!, _qty, size: _size, color: _color),
                    ),
                    child: Text('Ajouter · ${fcfa(_item!.price * _qty)}'),
                  ),
                ),
              ],
            ),
    );
  }
}

// ------------------------------------------------------- Réglages

class ShopSettingsScreen extends StatefulWidget {
  const ShopSettingsScreen({super.key});
  @override
  State<ShopSettingsScreen> createState() => _ShopSettingsScreenState();
}

class _ShopSettingsScreenState extends State<ShopSettingsScreen> {
  final _c = {
    for (final k in [
      'shop_name',
      'whatsapp',
      'orange_number',
      'wave_number',
      'wave_link',
      'delivery_fee',
    ])
      k: TextEditingController(),
  };
  bool? _cod;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final shop = context.read<ShopRepository>();
    Widget field(
      String key,
      String label, {
      TextInputType? type,
      String? hint,
    }) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: _c[key],
        keyboardType: type,
        decoration: InputDecoration(labelText: label, hintText: hint),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Paiement et livraison')),
      body: Loader<ShopInfo>(
        load: (_) => shop.info(),
        builder: (context, info) {
          if (_cod == null) {
            for (final e in _c.entries) {
              e.value.text = info.values[e.key] ?? '';
            }
            _cod = info.cashOnDelivery;
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              field('shop_name', 'Nom de la boutique en ligne'),
              field(
                'whatsapp',
                'Numéro WhatsApp pour les commandes',
                type: TextInputType.phone,
              ),
              _label('Mobile money'),
              field(
                'orange_number',
                'Numéro Orange Money',
                type: TextInputType.phone,
              ),
              field('wave_number', 'Numéro Wave', type: TextInputType.phone),
              field(
                'wave_link',
                'Lien de paiement Wave (facultatif)',
                type: TextInputType.url,
                hint: 'https://pay.wave.com/m/…',
              ),
              Text(
                'Le client paie sur votre numéro, puis vous touchez « J’ai reçu le paiement ». Le paiement automatique sera branché avec vos comptes marchands Orange Money et Wave.',
                style: TextStyle(color: Palette.muted, fontSize: 13),
              ),
              _label('Livraison'),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Accepter le paiement à la livraison'),
                value: _cod!,
                onChanged: (v) => setState(() => _cod = v),
              ),
              field(
                'delivery_fee',
                'Frais de livraison habituels (FCFA)',
                type: TextInputType.number,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () async {
                  try {
                    await shop.saveInfo({
                      for (final e in _c.entries) e.key: e.value.text,
                      'cod': _cod! ? 'oui' : 'non',
                    });
                  } catch (e) {
                    if (context.mounted) toast(context, errorText(e));
                    return;
                  }
                  app.changed();
                  if (context.mounted) {
                    Navigator.pop(context);
                    toast(context, 'Réglages enregistrés.');
                  }
                },
                child: const Text('Enregistrer'),
              ),
            ],
          );
        },
      ),
    );
  }
}
