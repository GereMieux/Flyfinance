import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/repository.dart';
import '../../data/services_repository.dart';
import '../agenda/agenda_view.dart';
import '../theme.dart';
import '../widgets.dart';
import 'business_screen.dart';
import 'catalogue_screen.dart';
import 'common.dart';
import 'doc_editor_screen.dart';

/// Espace prestation : pour les prestataires de services (artisans,
/// réparateurs, couturières, consultants…). Devis, factures, paiements,
/// agenda et catalogue des prestations.
class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Espace prestation'),
          actions: const [
            Padding(padding: EdgeInsets.only(right: 8), child: EyeButton()),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Palette.amber,
            labelColor: Palette.text,
            unselectedLabelColor: Palette.muted,
            labelStyle: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
            tabs: const [
              Tab(text: 'Accueil'),
              Tab(text: 'Devis'),
              Tab(text: 'Factures'),
              Tab(text: 'Agenda'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _DashboardTab(),
            _DocsTab(DocKind.devis),
            _DocsTab(DocKind.facture),
            AgendaView(),
          ],
        ),
      ),
    );
  }
}

void _newDoc(BuildContext context, DocKind kind) =>
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => DocEditorScreen(kind: kind)));

// ---------- Tableau de bord ----------

class _DashboardTab extends StatelessWidget {
  const _DashboardTab();

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Loader<ServicesDashboard>(
      load: (r) => r.servicesDashboard(),
      builder: (context, d) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Panel(
            color: Palette.hero,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Encaissé ce mois',
                  style: TextStyle(color: Palette.muted),
                ),
                FittedBox(
                  child: Text(
                    app.money(d.cashInMonth),
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  'Aujourd’hui : ${app.money(d.cashInToday)}',
                  style: TextStyle(
                    color: Palette.mint,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _Mini('Facturé ce mois', app.money(d.invoicedMonth)),
                    const SizedBox(width: 8),
                    _Mini(
                      'Reste à encaisser',
                      app.money(d.outstanding),
                      color: Palette.amber,
                    ),
                    const SizedBox(width: 8),
                    _Mini(
                      'Devis en attente',
                      '${d.pendingQuotes} · ${app.money(d.pendingQuotesTotal)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _BigButton(
            'Faire un devis',
            'Le prix proposé au client, avant le travail',
            Icons.request_quote_outlined,
            () => _newDoc(context, DocKind.devis),
            main: true,
          ),
          _BigButton(
            'Faire une facture',
            'Ce que le client doit payer',
            Icons.receipt_long_outlined,
            () => _newDoc(context, DocKind.facture),
          ),
          _BigButton(
            'Noter un rendez-vous',
            'Une intervention, un chantier',
            Icons.event_outlined,
            () => addAppointment(context),
          ),
          if (d.overdue.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Palette.red),
                const SizedBox(width: 8),
                Text(
                  '${d.overdue.length} facture${d.overdue.length > 1 ? 's' : ''} en retard',
                  style: TextStyle(
                    color: Palette.red,
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final s in d.overdue) DocTile(s),
          ],
          const SizedBox(height: 18),
          const Text(
            'Prochains rendez-vous',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (d.upcoming.isEmpty)
            const EmptyState(
              'Aucun rendez-vous prévu.',
              icon: Icons.event_available_outlined,
            ),
          for (final a in d.upcoming) AppointmentTile(a),
          const SizedBox(height: 18),
          const Text(
            'Réglages',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          _BigButton(
            'Mes prestations et mes prix',
            'Pour remplir vos devis en un geste',
            Icons.handyman_outlined,
            () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CatalogueScreen())),
          ),
          _BigButton(
            'Mon entreprise',
            'Logo, coordonnées et modèles de vos documents',
            Icons.business_outlined,
            () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const BusinessScreen())),
          ),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value, {this.color});
  final String label;
  final String value;
  final Color? color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Palette.heroTile,
        borderRadius: BorderRadius.circular(14),
      ),
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
                color: color ?? Palette.text,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Gros bouton pleine largeur, avec une phrase qui dit à quoi il sert.
class _BigButton extends StatelessWidget {
  const _BigButton(
    this.label,
    this.help,
    this.icon,
    this.onTap, {
    this.main = false,
  });
  final String label;
  final String help;
  final IconData icon;
  final VoidCallback onTap;
  final bool main;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Material(
      color: main ? Palette.green : Palette.card,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 32),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      help,
                      style: TextStyle(
                        color: main ? Palette.text : Palette.muted,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    ),
  );
}

// ---------- Devis / Factures ----------

class _DocsTab extends StatefulWidget {
  const _DocsTab(this.kind);
  final DocKind kind;
  @override
  State<_DocsTab> createState() => _DocsTabState();
}

class _DocsTabState extends State<_DocsTab> {
  final _search = TextEditingController();
  String _filter = 'tous';

  Map<String, String> get _filters => widget.kind == DocKind.devis
      ? const {'tous': 'Tous', 'attente': 'En attente', 'facture': 'Acceptés'}
      : const {
          'tous': 'Toutes',
          'aencaisser': 'Pas encore payées',
          'payee': 'Payées',
        };

  bool _keep(DocSummary s) => switch (_filter) {
    'attente' => s.pendingQuote,
    'facture' => s.status == DocStatus.facture || s.status == DocStatus.accepte,
    'aencaisser' => s.due > 0,
    'payee' => s.status == DocStatus.payee,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final quote = widget.kind == DocKind.devis;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: widget.kind.key,
        backgroundColor: Palette.green,
        foregroundColor: Colors.white,
        onPressed: () => _newDoc(context, widget.kind),
        icon: const Icon(Icons.add),
        label: Text(quote ? 'Nouveau devis' : 'Nouvelle facture'),
      ),
      body: Loader<List<DocSummary>>(
        key: ValueKey(widget.kind),
        load: (r) => r.docs(kind: widget.kind),
        builder: (context, all) {
          final q = normalize(_search.text);
          final list = all
              .where(_keep)
              .where(
                (s) =>
                    q.isEmpty ||
                    normalize(s.contact.name).contains(q) ||
                    normalize(s.doc.number).contains(q),
              )
              .toList();
          final sum = list.fold<int>(
            0,
            (a, s) => a + (quote ? s.doc.total : s.due),
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Client ou numéro',
                ),
              ),
              const SizedBox(height: 10),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final e in _filters.entries)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(e.value),
                          selected: _filter == e.key,
                          onSelected: (_) => setState(() => _filter = e.key),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              if (list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8, left: 4),
                  child: Text(
                    '${list.length} ${quote ? 'devis' : 'facture${list.length > 1 ? 's' : ''}'}'
                    ' · ${quote ? 'total' : 'reste à encaisser'} ${app.money(sum)}',
                    style: TextStyle(color: Palette.muted),
                  ),
                ),
              if (list.isEmpty)
                EmptyState(
                  all.isEmpty
                      ? (quote
                            ? 'Aucun devis. Touchez « Nouveau devis » pour '
                                  'chiffrer un travail.'
                            : 'Aucune facture. Créez-en une, ou transformez '
                                  'un devis accepté en facture.')
                      : 'Rien ne correspond.',
                  icon: quote
                      ? Icons.request_quote_outlined
                      : Icons.receipt_long_outlined,
                ),
              for (final s in list) DocTile(s),
            ],
          );
        },
      ),
    );
  }
}
