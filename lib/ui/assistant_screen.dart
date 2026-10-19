import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../voice/assistant.dart';
import '../voice/voice_io.dart';
import 'theme.dart';

class _Turn {
  _Turn.user(this.text) : reply = null, fromUser = true;
  _Turn.bot(AssistantReply this.reply) : text = reply.text, fromUser = false;
  final String text;
  final AssistantReply? reply;
  final bool fromUser;

  /// null = en attente, true = confirmée, false = refusée.
  bool? confirmed;
  String? outcome;
}

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({super.key});
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _voice = VoiceIO();
  final _turns = <_Turn>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final Assistant _assistant = Assistant(context.read<AppState>().repo);
  bool _listening = false;
  String _partial = '';

  static const _languages = {
    'fr': 'Français',
    'en': 'English',
    'ar': 'العربية',
    'es': 'Español',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _advice());
  }

  @override
  void dispose() {
    _voice.stop();
    _voice.silence();
    super.dispose();
  }

  /// Conseil proactif à l'ouverture : les articles à commander.
  Future<void> _advice() async {
    final low = await context.read<AppState>().repo.lowStock();
    if (low.isEmpty || !mounted) return;
    setState(
      () => _turns.add(
        _Turn.bot(
          AssistantReply(
            'Conseil : ${low.length} article${low.length > 1 ? 's sont' : ' est'} '
            'bientôt en rupture. Pensez à commander.',
            lines: [
              for (final s in low)
                (s.product.name, '${s.qty} ${s.product.unit}'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _ask(String text) async {
    if (text.trim().isEmpty) return;
    final app = context.read<AppState>();
    setState(() {
      _turns.add(_Turn.user(text));
      _partial = '';
    });
    final reply = await _assistant.handle(text);
    if (!mounted) return;
    setState(() => _turns.add(_Turn.bot(reply)));
    _toBottom();
    await _voice.speak(reply.text, lang: app.language, voice: app.voice);
  }

  Future<void> _decide(_Turn t, bool yes) async {
    final app = context.read<AppState>();
    setState(() => t.confirmed = yes);
    String msg;
    if (yes) {
      try {
        msg = await t.reply!.action!.run();
        app.changed();
      } catch (e) {
        msg = e.toString().replaceFirst(RegExp(r'^\w+Error: '), '');
      }
    } else {
      msg = 'Annulé, rien n’a été enregistré.';
    }
    if (!mounted) return;
    setState(() => t.outcome = msg);
    _toBottom();
    await _voice.speak(msg, lang: app.language, voice: app.voice);
  }

  Future<void> _mic() async {
    final app = context.read<AppState>();
    if (_listening) {
      await _voice.stop();
      setState(() => _listening = false);
      return;
    }
    await _voice.silence();
    final ok = await _voice.init();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Micro indisponible. Autorisez le micro ou écrivez votre demande.',
            ),
          ),
        );
      }
      return;
    }
    setState(() => _listening = true);
    await _voice.listen(
      app.language,
      onPartial: (s) => setState(() => _partial = s),
      onDone: (s) {
        setState(() => _listening = false);
        _ask(s);
      },
    );
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  });

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Container(
      color: const Color(0xFF0E1814),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Assistant',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Row(
                          children: [
                            Icon(Icons.circle, size: 8, color: Palette.mint),
                            SizedBox(width: 6),
                            Text(
                              'Prêt, même hors ligne',
                              style: TextStyle(
                                fontSize: 13,
                                color: Palette.mint,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => app.setVoicePrefs(
                      voice: app.voice == 'female' ? 'male' : 'female',
                    ),
                    icon: const Icon(
                      Icons.graphic_eq,
                      color: Palette.amber,
                      size: 18,
                    ),
                    label: Text(
                      app.voice == 'female'
                          ? 'Voix féminine'
                          : 'Voix masculine',
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 52,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                children: [
                  for (final l in _languages.entries)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text(l.value),
                        selected: app.language == l.key,
                        onSelected: (_) => app.setVoicePrefs(language: l.key),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: _scroll,
                padding: const EdgeInsets.all(16),
                children: [
                  if (_turns.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(top: 40),
                      child: Text(
                        'Parlez comme à un employé :\n« Vends 3 sacs de riz à Fatou, elle paie la moitié par Wave »',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Palette.muted,
                          fontSize: 16,
                          height: 1.5,
                        ),
                      ),
                    ),
                  for (final t in _turns)
                    t.fromUser ? _userBubble(t.text) : _botCard(t),
                  if (_partial.isNotEmpty) _userBubble(_partial, faded: true),
                ],
              ),
            ),
            _controls(),
          ],
        ),
      ),
    );
  }

  Widget _userBubble(String text, {bool faded = false}) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      margin: const EdgeInsets.only(bottom: 10, left: 48),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF22332C),
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(6),
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 16,
          color: faded ? Palette.muted : Palette.text,
        ),
      ),
    ),
  );

  Widget _botCard(_Turn t) {
    final r = t.reply!;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10, right: 32),
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Palette.text,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
            bottomRight: Radius.circular(20),
            bottomLeft: Radius.circular(6),
          ),
        ),
        child: DefaultTextStyle(
          style: const TextStyle(color: Palette.ink, fontSize: 15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(r.text, style: const TextStyle(fontWeight: FontWeight.w700)),
              if (r.lines.isNotEmpty) const SizedBox(height: 8),
              for (final l in r.lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(
                    children: [
                      Expanded(child: Text(l.$1)),
                      Text(
                        l.$2,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              if (r.action != null && t.confirmed == null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Palette.ink,
                          side: const BorderSide(color: Color(0xFFD5DBD6)),
                        ),
                        onPressed: () => _decide(t, false),
                        child: const Text('Non'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: () => _decide(t, true),
                        child: const Text('Oui, valider'),
                      ),
                    ),
                  ],
                ),
              ],
              if (t.outcome != null) ...[
                const SizedBox(height: 8),
                Text(
                  t.outcome!,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: t.confirmed == true
                        ? const Color(0xFF17603F)
                        : const Color(0xFF56635D),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    child: Column(
      children: [
        SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final s in const [
                'Combien j’ai vendu aujourd’hui ?',
                'Qui me doit ?',
                'Que commander ?',
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ActionChip(label: Text(s), onPressed: () => _ask(s)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                textInputAction: TextInputAction.send,
                onSubmitted: (v) {
                  _input.clear();
                  _ask(v);
                },
                decoration: const InputDecoration(hintText: 'Ou écrivez ici…'),
              ),
            ),
            const SizedBox(width: 10),
            Semantics(
              button: true,
              label: _listening ? 'Arrêter l’écoute' : 'Parler',
              child: GestureDetector(
                onTap: _mic,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Palette.amber,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: _listening
                          ? const Color(0xFF6B5420)
                          : const Color(0xFF1E2A24),
                      width: _listening ? 8 : 5,
                    ),
                  ),
                  child: Icon(
                    _listening ? Icons.stop : Icons.mic,
                    color: Palette.ink,
                    size: 30,
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_listening)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Je vous écoute…',
              style: TextStyle(color: Palette.muted),
            ),
          ),
      ],
    ),
  );
}
