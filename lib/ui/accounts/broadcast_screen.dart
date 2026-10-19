import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/database.dart';
import '../theme.dart';
import '../widgets.dart';
import 'common.dart';

/// Message proposé après un arrivage.
String arrivalMessage(List<String> products) {
  final names = products.toSet().toList();
  return 'Bonjour ! Nouvel arrivage à la boutique : ${names.join(', ')}. '
      'Passez vite, ou répondez à ce message pour réserver.';
}

/// Fichier contacts (.vcf) de tous les clients, à importer dans le
/// téléphone pour créer une liste de diffusion WhatsApp.
String clientsVcard(List<Contact> clients) {
  final b = StringBuffer();
  for (final c in clients.where((c) => c.phone != null)) {
    final name = c.name.replaceAll(RegExp(r'[\r\n;]'), ' ');
    b
      ..writeln('BEGIN:VCARD')
      ..writeln('VERSION:3.0')
      ..writeln('FN:$name')
      ..writeln('N:$name;;;;')
      ..writeln('TEL;TYPE=CELL:+${waPhone(c.phone)}');
    if (c.address != null) {
      b.writeln(
        'ADR;TYPE=HOME:;;${c.address!.replaceAll(RegExp(r'[\r\n;]'), ' ')};;;;',
      );
    }
    b.writeln('END:VCARD');
  }
  return b.toString();
}

/// Annonce (texte, photo ou vidéo) à tout le portefeuille clients.
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key, this.initialText});
  final String? initialText;

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  late final _text = TextEditingController(
    text:
        widget.initialText ??
        'Bonjour ! Découvrez les nouveautés de la boutique.',
  );
  XFile? _media;
  bool _video = false;
  final _sent = <int>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Annoncer aux clients')),
      body: Loader<List<Contact>>(
        load: (r) => r.contacts(kind: 'client'),
        builder: (context, all) {
          final clients = all.where((c) => c.phone != null).toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              TextField(
                controller: _text,
                maxLines: 5,
                minLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Message'),
              ),
              const SizedBox(height: 10),
              if (_media == null)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(video: true),
                        icon: const Icon(Icons.videocam_outlined),
                        label: const Text('Vidéo'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pick(video: false),
                        icon: const Icon(Icons.photo_outlined),
                        label: const Text('Photo'),
                      ),
                    ),
                  ],
                )
              else
                Panel(
                  padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
                  child: Row(
                    children: [
                      Icon(
                        _video ? Icons.videocam : Icons.photo,
                        color: Palette.mint,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _video ? 'Vidéo jointe' : 'Photo jointe',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Retirer',
                        onPressed: () => setState(() => _media = null),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(60),
                ),
                onPressed: _share,
                icon: const Icon(Icons.campaign_outlined),
                label: const Text('Envoyer à tous mes clients'),
              ),
              const SizedBox(height: 12),
              Panel(
                color: const Color(0xFF1B2A3A),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Comment ça marche',
                      style: TextStyle(
                        color: Palette.blue,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'WhatsApp ne permet à aucune application d’écrire à tous '
                      'vos clients à votre place. Le plus simple : dans '
                      'WhatsApp, créez une fois une « liste de diffusion » '
                      'avec vos clients. Ensuite, touchez « Envoyer à tous mes '
                      'clients », choisissez WhatsApp puis votre liste : tout '
                      'le monde reçoit le message et la vidéo en un seul envoi.',
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Vos clients doivent avoir votre numéro enregistré pour '
                      'recevoir une diffusion.',
                      style: TextStyle(color: Palette.muted),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: clients.isEmpty
                          ? null
                          : () => _exportContacts(clients),
                      icon: const Icon(Icons.contacts_outlined, size: 18),
                      label: Text(
                        'Mettre mes ${clients.length} clients dans le téléphone',
                      ),
                    ),
                  ],
                ),
              ),
              sectionTitle('Ou un par un (${clients.length})'),
              if (clients.isEmpty)
                const EmptyState(
                  'Aucun client avec un numéro de téléphone.',
                  icon: Icons.contacts_outlined,
                ),
              for (final c in clients)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: Text(
                    c.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    c.phone!,
                    style: const TextStyle(color: Palette.muted),
                  ),
                  trailing: _sent.contains(c.id)
                      ? const Icon(Icons.check_circle, color: Palette.mint)
                      : const Icon(Icons.send_outlined),
                  onTap: () async {
                    if (await openWhatsApp(context, c.phone, _text.text)) {
                      setState(() => _sent.add(c.id));
                    }
                  },
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _pick({required bool video}) async {
    final picker = ImagePicker();
    final f = video
        ? await picker.pickVideo(source: ImageSource.gallery)
        : await picker.pickImage(source: ImageSource.gallery);
    if (f != null) {
      setState(() {
        _media = f;
        _video = video;
      });
    }
  }

  Future<void> _share() => SharePlus.instance.share(
    ShareParams(text: _text.text, files: _media == null ? null : [_media!]),
  );

  Future<void> _exportContacts(List<Contact> clients) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/mes_clients.vcf');
    await file.writeAsString(clientsVcard(clients));
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/x-vcard')],
        text: 'Mes clients',
      ),
    );
  }
}
