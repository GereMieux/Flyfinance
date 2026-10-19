import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/database.dart';
import '../../data/notes_repository.dart';
import '../../data/services_repository.dart';
import '../services/common.dart';
import '../theme.dart';
import '../widgets.dart';

/// Agenda commun à l'écran « Agenda et notes » et à l'espace prestation :
/// un calendrier du mois, les rendez-vous du jour choisi, et l'ajout.

const monthNames = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

const _weekdays = [
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

/// « mardi 21 octobre ».
String longDay(DateTime d) =>
    '${_weekdays[d.weekday - 1]} ${d.day} ${monthNames[d.month - 1]}';

bool sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

class AgendaView extends StatefulWidget {
  const AgendaView({super.key});
  @override
  State<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<AgendaView> {
  late DateTime _month;
  late DateTime _day;

  @override
  void initState() {
    super.initState();
    _goToday();
  }

  void _goToday() {
    final t = context.read<AppState>().repo.now();
    _day = DateTime(t.year, t.month, t.day);
    _month = DateTime(t.year, t.month);
  }

  void _shift(int months) => setState(() {
    _month = DateTime(_month.year, _month.month + months);
    _day = _month;
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'agenda',
        backgroundColor: Palette.green,
        foregroundColor: Colors.white,
        onPressed: () => addAppointment(context, day: _day),
        icon: const Icon(Icons.add),
        label: const Text('Rendez-vous'),
      ),
      body: Loader<List<AppointmentItem>>(
        load: (r) => r.monthAppointments(_month),
        builder: (context, list) {
          final ofDay = list
              .where((a) => sameDay(a.appointment.at, _day))
              .toList();
          final title = '${monthNames[_month.month - 1]} ${_month.year}';
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [
              Panel(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Mois précédent',
                          icon: const Icon(Icons.chevron_left),
                          onPressed: () => _shift(-1),
                        ),
                        Expanded(
                          child: Text(
                            title[0].toUpperCase() + title.substring(1),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Mois suivant',
                          icon: const Icon(Icons.chevron_right),
                          onPressed: () => _shift(1),
                        ),
                      ],
                    ),
                    _MonthGrid(
                      month: _month,
                      selected: _day,
                      today: context.read<AppState>().repo.now(),
                      items: list,
                      onTap: (d) => setState(() => _day = d),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => setState(_goToday),
                        child: const Text('Aujourd’hui'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                longDay(_day)[0].toUpperCase() + longDay(_day).substring(1),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              if (ofDay.isEmpty)
                const EmptyState(
                  'Rien de prévu ce jour.\nTouchez « Rendez-vous » pour '
                  'ajouter une intervention, une livraison ou un rappel.',
                  icon: Icons.event_available_outlined,
                ),
              for (final a in ofDay) AppointmentTile(a, showDay: false),
            ],
          );
        },
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    required this.month,
    required this.selected,
    required this.today,
    required this.items,
    required this.onTap,
  });
  final DateTime month;
  final DateTime selected;
  final DateTime today;
  final List<AppointmentItem> items;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final first = DateTime(month.year, month.month);
    final days = DateTime(month.year, month.month + 1, 0).day;
    // Les semaines commencent le lundi.
    final blanks = first.weekday - 1;
    final cells = blanks + days;
    final rows = (cells / 7).ceil();
    return Column(
      children: [
        Row(
          children: [
            for (final l in ['L', 'M', 'M', 'J', 'V', 'S', 'D'])
              Expanded(
                child: Center(
                  child: Text(
                    l,
                    style: TextStyle(
                      color: Palette.muted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < rows; r++)
          Row(
            children: [
              for (var c = 0; c < 7; c++)
                Expanded(child: _cell(r * 7 + c - blanks + 1, days)),
            ],
          ),
      ],
    );
  }

  Widget _cell(int n, int days) {
    if (n < 1 || n > days) return const SizedBox(height: 46);
    final d = DateTime(month.year, month.month, n);
    final ofDay = items.where((a) => sameDay(a.appointment.at, d));
    final pending = ofDay.any((a) => !a.appointment.done);
    final isSelected = sameDay(d, selected);
    final isToday = sameDay(d, today);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onTap(d),
      child: SizedBox(
        height: 46,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected ? Palette.amber : null,
                shape: BoxShape.circle,
                border: isToday && !isSelected
                    ? Border.all(color: Palette.mint, width: 1.5)
                    : null,
              ),
              child: Text(
                '$n',
                style: TextStyle(
                  fontWeight: isSelected || isToday
                      ? FontWeight.w700
                      : FontWeight.w500,
                  color: isSelected ? Palette.ink : Palette.text,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ofDay.isEmpty
                    ? Colors.transparent
                    : pending
                    ? Palette.mint
                    : Palette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ajoute un rendez-vous, le `day` donné ou demain par défaut.
Future<void> addAppointment(BuildContext context, {DateTime? day}) async {
  final repo = context.read<AppState>().repo;
  final title = TextEditingController();
  final place = TextEditingController();
  final now = DateTime.now();
  var when = day ?? DateTime(now.year, now.month, now.day + 1);
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
                title: Text(dayDate(when)),
                onTap: () async {
                  final d = await showDatePicker(
                    context: ctx,
                    initialDate: when,
                    firstDate: DateTime(now.year - 1),
                    lastDate: DateTime(now.year + 3),
                  );
                  if (d != null) set(() => when = d);
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
      at: DateTime(when.year, when.month, when.day, time.hour, time.minute),
      contactId: client?.id,
      place: place.text,
    ),
  );
}

class AppointmentTile extends StatelessWidget {
  const AppointmentTile(this.a, {super.key, this.showDay = true});
  final AppointmentItem a;

  /// Faux quand la liste est déjà rangée par jour.
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    final ap = a.appointment;
    final hour =
        '${ap.at.hour.toString().padLeft(2, '0')}:${ap.at.minute.toString().padLeft(2, '0')}';
    final sub = [
      if (showDay) dayDate(ap.at),
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
            icon: Icon(Icons.delete_outline, color: Palette.muted),
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
