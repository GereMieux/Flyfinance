import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

const _locales = {'fr': 'fr-FR', 'en': 'en-US', 'ar': 'ar-SA', 'es': 'es-ES'};

/// Micro et haut-parleur, avec les moteurs du téléphone (hors ligne quand
/// le pack de langue est installé).
class VoiceIO {
  final _stt = SpeechToText();
  final _tts = FlutterTts();
  bool _ready = false;

  bool get listening => _stt.isListening;

  Future<bool> init() async {
    if (_ready) return true;
    _ready = await _stt.initialize();
    await _tts.awaitSpeakCompletion(true);
    return _ready;
  }

  /// Écoute une phrase. `onPartial` affiche le texte pendant qu'on parle,
  /// `onDone` reçoit la phrase complète.
  Future<void> listen(
    String lang, {
    required void Function(String) onPartial,
    required void Function(String) onDone,
  }) async {
    if (!await init()) return;
    await _stt.listen(
      onResult: (r) {
        onPartial(r.recognizedWords);
        if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
          onDone(r.recognizedWords);
        }
      },
      listenOptions: SpeechListenOptions(
        localeId: _locales[lang],
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
        pauseFor: const Duration(seconds: 3),
        listenFor: const Duration(seconds: 30),
      ),
    );
  }

  Future<void> stop() => _stt.stop();

  /// Lit la réponse avec la voix choisie : féminine, ou masculine grave.
  /// Si le téléphone n'a pas de voix du bon genre, la hauteur est ajustée.
  Future<void> speak(
    String text, {
    required String lang,
    required String voice,
  }) async {
    final locale = _locales[lang]!;
    await _tts.setLanguage(locale);
    final male = voice == 'male';
    var found = false;
    try {
      final voices = (await _tts.getVoices as List?) ?? const [];
      for (final v in voices) {
        final m = Map<String, String>.from(
          (v as Map).map((k, v) => MapEntry('$k', '$v')),
        );
        final name = (m['name'] ?? '').toLowerCase();
        final gender = (m['gender'] ?? '').toLowerCase();
        final sameLang = (m['locale'] ?? '').toLowerCase().startsWith(lang);
        final isMale =
            gender == 'male' ||
            name.contains('male') && !name.contains('female') ||
            RegExp(r'#male|-x-[a-z]{2}d-|-x-[a-z]{2}b-').hasMatch(name);
        if (sameLang && isMale == male) {
          await _tts.setVoice({'name': m['name']!, 'locale': m['locale']!});
          found = true;
          break;
        }
      }
    } catch (_) {}
    await _tts.setPitch(male ? (found ? 0.9 : 0.75) : 1.05);
    await _tts.setSpeechRate(0.48);
    await _tts.speak(text);
  }

  Future<void> silence() => _tts.stop();
}
