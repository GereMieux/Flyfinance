import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app_state.dart';
import '../../data/management_repository.dart';
import '../accounts/common.dart';
import '../services/common.dart' show guarded;
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

/// Sauvegarde de toutes les données, et export des tableaux pour Excel.
class BackupScreen extends StatelessWidget {
  const BackupScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sauvegarde et export')),
    body: Loader<String>(
      // Chaîne vide quand il n'y a encore aucune sauvegarde.
      load: (r) async => await r.setting('backup.last') ?? '',
      builder: (context, saved) {
        final last = saved.isEmpty ? null : saved;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
          children: [
            Panel(
              color: last == null ? Palette.amberSoft : Palette.mintSoft,
              child: Text(
                last == null
                    ? 'Aucune sauvegarde pour l’instant. Si le téléphone est '
                          'perdu ou cassé, vos données le sont aussi : '
                          'sauvegardez et envoyez le fichier sur WhatsApp ou '
                          'Google Drive.'
                    : 'Dernière sauvegarde : le $last.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: last == null ? Palette.amber : Palette.mint,
                ),
              ),
            ),
            sectionTitle('Sauvegarde'),
            TilesPanel(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  ListTile(
                    leading: IconBubble(Icons.backup_outlined, Palette.mint),
                    title: const Text('Sauvegarder maintenant'),
                    subtitle: const Text(
                      'Un fichier avec toutes vos données, à garder en lieu sûr',
                    ),
                    onTap: () => _backup(context),
                  ),
                  ListTile(
                    leading: IconBubble(Icons.restore_outlined, Palette.amber),
                    title: const Text('Restaurer une sauvegarde'),
                    subtitle: const Text(
                      'Remplace les données de ce téléphone',
                    ),
                    onTap: () => _restore(context),
                  ),
                ],
              ),
            ),
            sectionTitle('Exporter pour Excel'),
            TilesPanel(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                children: [
                  for (final e in const {
                    'ventes': ('Ventes', Icons.receipt_long_outlined),
                    'stock': ('Stock', Icons.inventory_2_outlined),
                    'depenses': ('Dépenses', Icons.payments_outlined),
                    'journal': ('Journal de caisse', Icons.menu_book_outlined),
                  }.entries)
                    ListTile(
                      leading: IconBubble(e.value.$2, Palette.blue),
                      title: Text(e.value.$1),
                      trailing: const Icon(Icons.ios_share_outlined),
                      onTap: () => _export(context, e.key, e.value.$1),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    ),
  );

  Future<File> _file(String name, String content) async {
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/$name');
    await f.writeAsString(content, encoding: utf8);
    return f;
  }

  String _day(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _export(BuildContext context, String what, String title) async {
    final repo = context.read<AppState>().repo;
    final csv = await repo.exportCsv(what);
    final f = await _file('flyfinance-$what-${_day(repo.now())}.csv', csv);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: 'text/csv')],
        title: title,
      ),
    );
  }

  Future<void> _backup(BuildContext context) async {
    final app = context.read<AppState>();
    if (!await askOwnerPin(
      context,
      title: 'Sauvegarder',
      text: 'Le fichier contient toutes vos données. Gardez-le pour vous.',
    )) {
      return;
    }
    final json = await app.repo.backupJson();
    final now = app.repo.now();
    final f = await _file('sauvegarde-flyfinance-${_day(now)}.json', json);
    final r = await SharePlus.instance.share(
      ShareParams(
        files: [XFile(f.path, mimeType: 'application/json')],
        title: 'Sauvegarde FLYFINANCE',
      ),
    );
    if (r.status != ShareResultStatus.dismissed) {
      await app.repo.setSetting('backup.last', dayOnly(now));
      app.changed();
    }
  }

  Future<void> _restore(BuildContext context) async {
    final app = context.read<AppState>();
    final pick = await FilePicker.pickFiles();
    if (pick.isEmpty || !context.mounted) return;
    final bytes = await pick.single.readAsBytes();
    if (!context.mounted) return;
    if (!await askOwnerPin(
      context,
      title: 'Restaurer ?',
      text:
          'Toutes les données de ce téléphone seront remplacées par celles '
          'de la sauvegarde.',
      action: 'Restaurer',
    )) {
      return;
    }
    if (!context.mounted) return;
    final when = await guarded(
      context,
      () => app.repo.restoreJson(utf8.decode(bytes)),
    );
    if (when != null && context.mounted) {
      toast(context, 'Sauvegarde du ${dayOnly(when)} restaurée');
    }
  }
}
