import 'package:flutter/material.dart';

import '../theme.dart';
import 'agenda_view.dart';
import 'notes_view.dart';

/// Agenda et bloc-notes : rendez-vous, notes libres et listes à cocher.
/// Tout reste dans la base chiffrée du téléphone et marche hors ligne.
class AgendaScreen extends StatelessWidget {
  const AgendaScreen({super.key, this.initialTab = 0});
  final int initialTab;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Agenda et notes'),
          bottom: const TabBar(
            indicatorColor: Palette.amber,
            labelColor: Palette.text,
            unselectedLabelColor: Palette.muted,
            labelStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            tabs: [
              Tab(text: 'Agenda'),
              Tab(text: 'Notes'),
              Tab(text: 'Listes'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            AgendaView(),
            NotesView(lists: false),
            NotesView(lists: true),
          ],
        ),
      ),
    );
  }
}
