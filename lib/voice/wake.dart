/// Mot de réveil « Hello Zara ».
///
/// Renvoie ce qui suit le mot de réveil (chaîne vide si l'on a seulement
/// appelé Zara), ou `null` si la phrase ne commence pas par lui. Le moteur
/// de reconnaissance écrit parfois « Sara » ou « Zahra » : on les accepte
/// après un « hello », « ok »…
String? afterWakeWord(String heard) {
  final t = heard.trim();
  final m = _wake.firstMatch(t);
  if (m == null) return null;
  return t.substring(m.end).trim();
}

final _wake = RegExp(
  r'^(?:(?:hello|hey|hé|allo|allô|ok|okay|bonjour|salut)[\s,]*'
  r'(?:zara|sara|zahra|zarah)|zara|zahra)(?![a-zà-ÿ])[\s,.!?:]*',
  caseSensitive: false,
);
