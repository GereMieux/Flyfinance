import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/database.dart';
import '../../data/repository.dart';
import '../../data/services_repository.dart';
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
    void open(Widget w) =>
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Espace prestation'),
          actions: [
            IconButton(
              tooltip: 'Mes prestations',
              onPressed: () => open(const CatalogueScreen()),
              icon: const Icon(Icons.handyman_outlined),
            ),
            IconButton(
              tooltip: 'Mon entreprise',
              onPressed: () => open(const BusinessScreen()),
              icon: const Icon(Icons.business_outlined),
            ),
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: EyeButton(),
            ),
          ],
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            indicatorColor: Palette.amber,
            labelColor: Palette.text,
            unselectedLabelColor: Palette.muted,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            tabs: [
              Tab(text: 'Tableau'),
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
            _AgendaTab(),
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
            color: const Color(0xFF18302A),
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
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
                  style: const TextStyle(
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
          Row(
            children: [
              _Action(
                'Devis',
                Icons.request_quote_outlined,
                () => _newDoc(context, DocKind.devis),
                main: true,
              ),
              _Action(
                'Facture',
                Icons.receipt_long_outlined,
                () => _newDoc(context, DocKind.facture),
              ),
              _Action(
                'Rendez-vous',
                Icons.event_outlined,
                () => addAppointment(context),
              ),
              _Action(
                'Prestations',
                Icons.handyman_outlined,
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CatalogueScreen()),
                ),
              ),
            ],
          ),
          if (d.overdue.isNotEmpty) ...[
            const SizedBox(height: 18),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Palette.red),
                const SizedBox(width: 8),
                Text(
                  '${d.overdue.length} facture${d.overdue.length > 1 ? 's' : ''} en retard',
                  style: const TextStyle(
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
          for (final a in d.upcoming) _AppointmentTile(a),
        ],
      ),
    );
  }
}

class _Mini extends StatelessWidget {
  const _Mini(this.label, this.value, {this.color = Palette.text});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFF1D2D26),
        borderRadius: BorderRadius.circular(14),
      ),
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
  );
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.icon, this.onTap, {this.main = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool main;
  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: main ? Palette.green : Palette.card,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(icon, size: 28),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ],
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
      ? const {
          'tous': 'Tous',
          'attente': 'En attente',
          'facture': 'Facturés',
          'clos': 'Refusés / expirés',
        }
      : const {
          'tous': 'Toutes',
          'aencaisser': 'À encaisser',
          'retard': 'En retard',
          'payee': 'Payées',
        };

  bool _keep(DocSummary s) => switch (_filter) {
    'attente' => s.pendingQuote,
    'facture' => s.status == DocStatus.facture,
    'clos' => s.status == DocStatus.refuse || s.status == DocStatus.expire,
    'aencaisser' => s.due > 0,
    'retard' => s.status == DocStatus.enRetard,
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
        foregroundColor: Palette.text,
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
                    style: const TextStyle(color: Palette.muted),
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

// ---------- Agenda ----------

Future<void> addAppointment(BuildContext context) async {
  final repo = context.read<AppState>().repo;
  final title = TextEditingController();
  final place = TextEditingController();
  final now = DateTime.now();
  var day = DateTime(now.year, now.month, now.day + 1);
  var time = const TimeOfDay(hour: 9, minute: 0);
  Contact? client;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Nouveau rendez-vous'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: title,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Quoi ? (ex. Réparation frigo)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: place,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Où ? (facultatif)',
                ),
              ),
              const SizedBox(height: 6),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(client?.name ?? 'Client (facultatif)'),
                onTap: () async {
                  final c = await pickClient(ctx);
                  if (c != null) set(() => client = c);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: Text(dayDate(day)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: day,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 3),
                  );
                  if (d != null) set(() => day = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text(time.format(ctx)),
                onTap: () async {
                  final t = await showTimePicker(
                    context: ctx,
                    initialTime: time,
                  );
                  if (t != null) set(() => time = t);
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ajouter'),
          ),
        ],
      ),
    ),
  );
  if (ok != true || title.text.trim().isEmpty || !context.mounted) return;
  await guarded(
    context,
    () => repo.addAppointment(
      title: title.text,
      at: DateTime(day.year, day.month, day.day, time.hour, time.minute),
      contactId: client?.id,
      place: place.text,
    ),
  );
}

class _AgendaTab extends StatefulWidget {
  const _AgendaTab();
  @override
  State<_AgendaTab> createState() => _AgendaTabState();
}

class _AgendaTabState extends State<_AgendaTab> {
  bool _past = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'agenda',
        backgroundColor: Palette.green,
        foregroundColor: Palette.text,
        onPressed: () => addAppointment(context),
        icon: const Icon(Icons.add),
        label: const Text('Rendez-vous'),
      ),
      body: Loader<List<AppointmentItem>>(
        key: ValueKey(_past),
        load: (r) {
          final t = r.now();
          return r.appointments(
            from: _past ? null : DateTime(t.year, t.month, t.day),
          );
        },
        builder: (context, list) {
          final shown = _past ? list.reversed.toList() : list;
          String? lastDay;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Row(
                children: [
                  ChoiceChip(
                    label: const Text('À venir'),
                    selected: !_past,
                    onSelected: (_) => setState(() => _past = false),
                  ),
                  const SizedBox(width: 6),
                  ChoiceChip(
                    label: const Text('Tout l’historique'),
                    selected: _past,
                    onSelected: (_) => setState(() => _past = true),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (shown.isEmpty)
                const EmptyState(
                  'Aucun rendez-vous. Notez ici vos interventions et '
                  'chantiers pour ne rien oublier.',
                  icon: Icons.event_available_outlined,
                ),
              for (final a in shown) ...[
                if (dayDate(a.appointment.at) != lastDay)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
                    child: Text(
                      lastDay = dayDate(a.appointment.at),
                      style: const TextStyle(
                        color: Palette.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                _AppointmentTile(a),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AppointmentTile extends StatelessWidget {
  const _AppointmentTile(this.a);
  final AppointmentItem a;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    final ap = a.appointment;
    final hour =
        '${ap.at.hour.toString().padLeft(2, '0')}:${ap.at.minute.toString().padLeft(2, '0')}';
    final sub = [
      dayDate(ap.at),
      hour,
      if (a.contact != null) a.contact!.name,
      if (ap.place != null) ap.place!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Palette.card,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          leading: Checkbox(
            value: ap.done,
            onChanged: (v) =>
                guarded(context, () => repo.setAppointmentDone(ap.id, v!)),
          ),
          title: Text(
            ap.title,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              decoration: ap.done ? TextDecoration.lineThrough : null,
              color: ap.done ? Palette.muted : Palette.text,
            ),
          ),
          subtitle: Text(sub),
          trailing: IconButton(
            tooltip: 'Supprimer',
            icon: const Icon(Icons.delete_outline, color: Palette.muted),
            onPressed: () async {
              if (await confirm(
                    context,
                    'Supprimer ce rendez-vous ?',
                    ap.title,
                    ok: 'Supprimer',
                  ) &&
                  context.mounted) {
                await guarded(context, () => repo.deleteAppointment(ap.id));
              }
            },
          ),
        ),
      ),
    );
  }
}
