import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/notes_repository.dart';
import '../services/common.dart';
import '../theme.dart';
import '../widgets.dart';

/// Le bloc-notes : notes libres (`lists` faux) ou listes à cocher.
class NotesView extends StatefulWidget {
  const NotesView({super.key, required this.lists});
  final bool lists;
  @override
  State<NotesView> createState() => _NotesViewState();
}

class _NotesViewState extends State<NotesView> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (!widget.lists) {
      await openNote(context);
      return;
    }
    final title = await askText(
      context,
      'Nouvelle liste',
      hint: 'Nom (ex. Courses du marché)',
      ok: 'Créer',
    );
    if (title == null || !mounted) return;
    final id = await guarded(
      context,
      () => context.read<AppState>().repo.addNote(title: title, isList: true),
    );
    if (id != null && mounted) await openNote(context, id: id, isList: true);
  }

  @override
  Widget build(BuildContext context) {
    final lists = widget.lists;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        heroTag: lists ? 'lists' : 'notes',
        backgroundColor: Palette.green,
        foregroundColor: Colors.white,
        onPressed: _create,
        icon: Icon(lists ? Icons.playlist_add : Icons.edit_note),
        label: Text(lists ? 'Liste' : 'Note'),
      ),
      body: Loader<List<NoteEntry>>(
        load: (r) => r.notes(lists: lists, query: _search.text),
        builder: (context, entries) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: lists
                    ? 'Chercher dans les listes'
                    : 'Chercher une note',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Effacer',
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(_search.clear),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              EmptyState(
                _search.text.isNotEmpty
                    ? 'Rien trouvé.'
                    : lists
                    ? 'Aucune liste. Faites vos listes de courses, de '
                          'commandes ou de choses à faire, et cochez au fur '
                          'et à mesure.'
                    : 'Aucune note. Écrivez ici tout ce que vous ne voulez '
                          'pas oublier.',
                icon: lists ? Icons.checklist : Icons.sticky_note_2_outlined,
              ),
            for (final e in entries) _NoteCard(e),
          ],
        ),
      ),
    );
  }
}

/// Ouvre une note (ou une nouvelle si `id` est nul) ou une liste.
Future<void> openNote(BuildContext context, {int? id, bool isList = false}) =>
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            isList ? ListScreen(noteId: id!) : NoteEditorScreen(noteId: id),
      ),
    );

class _NoteCard extends StatelessWidget {
  const _NoteCard(this.e);
  final NoteEntry e;

  @override
  Widget build(BuildContext context) {
    final n = e.note;
    final preview = n.isList
        ? [
            for (final i in e.items.where((i) => !i.done).take(3))
              '• ${i.label}',
          ].join('\n')
        : n.title.trim().isEmpty
        ? n.body.split('\n').skip(1).join('\n').trim()
        : n.body;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Palette.card,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => openNote(context, id: n.id, isList: n.isList),
          onLongPress: () => noteMenu(context, e),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          if (n.pinned)
                            Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.push_pin,
                                size: 16,
                                color: Palette.amber,
                              ),
                            ),
                          Expanded(
                            child: Text(
                              e.heading,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          preview,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: Palette.muted),
                        ),
                      ],
                      if (n.isList && e.items.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: e.doneCount / e.items.length,
                            minHeight: 5,
                            color: Palette.mint,
                            backgroundColor: Palette.line,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${e.doneCount} sur ${e.items.length} fait'
                          '${e.doneCount > 1 ? 's' : ''}',
                          style: TextStyle(fontSize: 12, color: Palette.muted),
                        ),
                      ],
                      const SizedBox(height: 6),
                      Text(
                        'Modifié le ${shortDate(n.updatedAt)}',
                        style: TextStyle(fontSize: 12, color: Palette.muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Options',
                  icon: Icon(Icons.more_vert, color: Palette.muted),
                  onPressed: () => noteMenu(context, e),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Épingler ou supprimer. Renvoie vrai si la note a été supprimée.
Future<bool> noteMenu(BuildContext context, NoteEntry e) async {
  final repo = context.read<AppState>().repo;
  final n = e.note;
  final choice = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Palette.card,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(n.pinned ? Icons.push_pin_outlined : Icons.push_pin),
            title: Text(n.pinned ? 'Détacher du haut' : 'Épingler en haut'),
            onTap: () => Navigator.pop(ctx, 'pin'),
          ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: Palette.red),
            title: Text('Supprimer', style: TextStyle(color: Palette.red)),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return false;
  if (choice == 'pin') {
    await guarded(context, () => repo.setNotePinned(n.id, !n.pinned));
  } else if (choice == 'delete' &&
      await confirm(
        context,
        n.isList ? 'Supprimer cette liste ?' : 'Supprimer cette note ?',
        e.heading,
        ok: 'Supprimer',
      ) &&
      context.mounted) {
    await guarded(context, () => repo.deleteNote(n.id));
    return true;
  }
  return false;
}

/// Demande un texte court. Nul si annulé ou vide.
Future<String?> askText(
  BuildContext context,
  String title, {
  String hint = '',
  String initial = '',
  String ok = 'OK',
}) async {
  final c = TextEditingController(text: initial);
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Palette.card,
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (_) => Navigator.pop(ctx, true),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  final text = c.text.trim();
  c.dispose();
  return res == true && text.isNotEmpty ? text : null;
}

// ---------- Note ----------

/// Écrire une note. Enregistrée en quittant l'écran ; une note vide n'est
/// pas gardée.
class NoteEditorScreen extends StatefulWidget {
  const NoteEditorScreen({super.key, this.noteId});
  final int? noteId;
  @override
  State<NoteEditorScreen> createState() => _NoteEditorScreenState();
}

class _NoteEditorScreenState extends State<NoteEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  late final AppState _app = context.read<AppState>();
  NoteEntry? _entry;
  bool _loading = true;
  bool _deleted = false;

  @override
  void initState() {
    super.initState();
    final id = widget.noteId;
    if (id == null) {
      _loading = false;
      return;
    }
    _app.repo.note(id).then((e) {
      if (!mounted) return;
      setState(() {
        _entry = e;
        _title.text = e.note.title;
        _body.text = e.note.body;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_loading || _deleted) return;
    final title = _title.text.trim(), body = _body.text.trim();
    final e = _entry;
    if (e == null) {
      if (title.isEmpty && body.isEmpty) return;
      await _app.repo.addNote(title: title, body: body);
    } else if (title != e.note.title || body != e.note.body) {
      if (title.isEmpty && body.isEmpty) {
        await _app.repo.deleteNote(e.note.id);
      } else {
        await _app.repo.saveNote(e.note.id, title: title, body: body);
      }
    } else {
      return;
    }
    _app.changed();
  }

  @override
  Widget build(BuildContext context) {
    final e = _entry;
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _save();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(e == null ? 'Nouvelle note' : 'Note'),
          actions: [
            if (e != null)
              IconButton(
                tooltip: 'Options',
                icon: const Icon(Icons.more_vert),
                onPressed: () async {
                  await _save();
                  if (!context.mounted) return;
                  final fresh = await _app.repo.note(e.note.id);
                  if (!context.mounted) return;
                  if (await noteMenu(context, fresh)) {
                    _deleted = true;
                    if (context.mounted) Navigator.pop(context);
                  } else {
                    _entry = await _app.repo.note(e.note.id);
                  }
                },
              ),
            IconButton(
              tooltip: 'Terminé',
              icon: const Icon(Icons.check),
              onPressed: () => Navigator.maybePop(context),
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                children: [
                  TextField(
                    controller: _title,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Titre',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                  TextField(
                    controller: _body,
                    autofocus: widget.noteId == null,
                    minLines: 12,
                    maxLines: null,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(fontSize: 17, height: 1.4),
                    decoration: const InputDecoration(
                      hintText: 'Écrivez votre note…',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

// ---------- Liste ----------

/// Une liste à cocher : on ajoute en bas, on coche, on retire les cochés.
class ListScreen extends StatefulWidget {
  const ListScreen({super.key, required this.noteId});
  final int noteId;
  @override
  State<ListScreen> createState() => _ListScreenState();
}

class _ListScreenState extends State<ListScreen> {
  final _new = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _new.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final text = _new.text.trim();
    if (text.isEmpty) return;
    final id = await guarded(
      context,
      () => context.read<AppState>().repo.addNoteItem(widget.noteId, text),
    );
    if (id != null) _new.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AppState>().repo;
    return Loader<NoteEntry>(
      load: (r) => r.note(widget.noteId),
      builder: (context, e) {
        // Ce qui reste à faire d'abord, le fait en bas.
        final items = [
          ...e.items.where((i) => !i.done),
          ...e.items.where((i) => i.done),
        ];
        return Scaffold(
          appBar: AppBar(
            title: Text(e.heading),
            actions: [
              IconButton(
                tooltip: 'Renommer',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  final t = await askText(
                    context,
                    'Nom de la liste',
                    initial: e.note.title,
                  );
                  if (t != null && context.mounted) {
                    await guarded(
                      context,
                      () => repo.saveNote(e.note.id, title: t),
                    );
                  }
                },
              ),
              IconButton(
                tooltip: 'Options',
                icon: const Icon(Icons.more_vert),
                onPressed: () async {
                  if (await noteMenu(context, e) && context.mounted) {
                    Navigator.pop(context);
                  }
                },
              ),
            ],
          ),
          body: Column(
            children: [
              if (e.items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${e.doneCount} sur ${e.items.length} fait'
                          '${e.doneCount > 1 ? 's' : ''}',
                          style: TextStyle(color: Palette.muted),
                        ),
                      ),
                      if (e.doneCount > 0)
                        TextButton(
                          onPressed: () => guarded(
                            context,
                            () => repo.clearDoneItems(e.note.id),
                          ),
                          child: const Text('Retirer les cochés'),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: items.isEmpty
                    ? const EmptyState(
                        'Liste vide. Écrivez une ligne en bas puis touchez +.',
                        icon: Icons.checklist,
                      )
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                        children: [
                          for (final i in items)
                            ListTile(
                              key: ValueKey(i.id),
                              contentPadding: const EdgeInsets.only(left: 4),
                              leading: Checkbox(
                                value: i.done,
                                onChanged: (v) => guarded(
                                  context,
                                  () => repo.setNoteItemDone(i.id, v!),
                                ),
                              ),
                              title: Text(
                                i.label,
                                style: TextStyle(
                                  fontSize: 17,
                                  decoration: i.done
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: i.done ? Palette.muted : Palette.text,
                                ),
                              ),
                              onTap: () async {
                                final t = await askText(
                                  context,
                                  'Modifier la ligne',
                                  initial: i.label,
                                );
                                if (t != null && context.mounted) {
                                  await guarded(
                                    context,
                                    () => repo.renameNoteItem(i.id, t),
                                  );
                                }
                              },
                              trailing: IconButton(
                                tooltip: 'Retirer',
                                icon: Icon(Icons.close, color: Palette.muted),
                                onPressed: () => guarded(
                                  context,
                                  () => repo.deleteNoteItem(i.id),
                                ),
                              ),
                            ),
                        ],
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _new,
                          focusNode: _focus,
                          textCapitalization: TextCapitalization.sentences,
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _add(),
                          decoration: const InputDecoration(
                            hintText: 'Ajouter une ligne',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: 'Ajouter',
                        onPressed: _add,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
