import '../data/repository.dart' show normalize;

/// Ce que l'utilisateur a demandé, compris à partir d'une phrase.
sealed class Intent {
  const Intent();
}

enum PayKind { full, half, none, amount }

class SellIntent extends Intent {
  const SellIntent({
    required this.qty,
    required this.product,
    this.client,
    this.pay = PayKind.full,
    this.amount,
    this.method,
  });
  final int qty;
  final String product;
  final String? client;
  final PayKind pay;
  final int? amount;
  final String? method;
}

class AddStockIntent extends Intent {
  const AddStockIntent(this.qty, this.product);
  final int qty;
  final String product;
}

class StockQueryIntent extends Intent {
  const StockQueryIntent(this.product);
  final String? product;
}

class DebtQueryIntent extends Intent {
  const DebtQueryIntent(this.client);
  final String? client;
}

class SalesTodayIntent extends Intent {
  const SalesTodayIntent();
}

class UnknownIntent extends Intent {
  const UnknownIntent(this.text);
  final String text;
}

const _numbers = {
  'un': 1,
  'une': 1,
  'one': 1,
  'deux': 2,
  'two': 2,
  'trois': 3,
  'three': 3,
  'quatre': 4,
  'four': 4,
  'cinq': 5,
  'five': 5,
  'six': 6,
  'sept': 7,
  'seven': 7,
  'huit': 8,
  'eight': 8,
  'neuf': 9,
  'nine': 9,
  'dix': 10,
  'ten': 10,
  'onze': 11,
  'douze': 12,
  'quinze': 15,
  'vingt': 20,
  'trente': 30,
  'quarante': 40,
  'cinquante': 50,
  'cent': 100,
};

const _methods = {
  'wave': 'wave',
  'orange': 'orange',
  'mtn': 'mtn',
  'momo': 'mtn',
  'moov': 'moov',
  'especes': 'especes',
  'cash': 'especes',
  'liquide': 'especes',
};

/// Analyseur hors ligne des commandes courantes (français, et quelques
/// formes anglaises). Les phrases qu'il ne comprend pas sont renvoyées en
/// [UnknownIntent] et pourront être confiées à l'IA en ligne.
class IntentParser {
  Intent parse(String input) {
    final t = _prepare(input);

    final sell = RegExp(
      r'^(?:vends?|vendre|vendu|sell|sold)\s+(\d+)\s+(.+?)(?:\s+(?:a|au|aux|pour|to)\s+([a-z][a-z\s\-]*?))?(?:\s*,?\s*(?:il|elle|he|she)?\s*(?:paie|paye|a paye|regle|verse|pays|paid)\s+(.+))?$',
    ).firstMatch(t);
    if (sell != null) {
      var product = sell.group(2)!.trim();
      var client = sell.group(3)?.trim();
      var payText = sell.group(4) ?? '';
      // « … à Fatou à crédit » : le crédit est collé au nom du client.
      for (final marker in [
        ' a credit',
        ' en credit',
        ' credit',
        ' on credit',
      ]) {
        if (client != null &&
            client.endsWith(marker.trim()) &&
            client.contains(marker)) {
          client = client.substring(0, client.lastIndexOf(marker)).trim();
          payText = '$payText rien';
        }
        if (product.endsWith(marker)) {
          product = product.substring(0, product.length - marker.length).trim();
          payText = '$payText rien';
        }
      }
      final pay = _payment(payText);
      return SellIntent(
        qty: int.parse(sell.group(1)!),
        product: product,
        client: (client == null || client.isEmpty) ? null : client,
        pay: pay.$1,
        amount: pay.$2,
        method: _method(payText),
      );
    }

    final add = RegExp(
      r"^(?:ajoute|ajouter|rajoute|j ai recu|recu|entree de|add|received)\s+(\d+)\s+(.+?)(?:\s+(?:au|en|dans le|to)\s+stock)?$",
    ).firstMatch(t);
    if (add != null) {
      return AddStockIntent(int.parse(add.group(1)!), add.group(2)!.trim());
    }

    if (RegExp(r'qui me doit|qui doit|dettes|credits|who owes').hasMatch(t)) {
      return const DebtQueryIntent(null);
    }
    final owes = RegExp(r'combien (?:me doit|doit|me doit encore)\s+(.+)$')
        .firstMatch(t);
    if (owes != null) return DebtQueryIntent(owes.group(1)!.trim());

    if (RegExp(
      r"(combien j ai vendu|ventes? du jour|ventes? d aujourd hui|chiffre du jour|today s sales|sales today)",
    ).hasMatch(t)) {
      return const SalesTodayIntent();
    }

    final stock = RegExp(
      r"^(?:combien (?:de |d )?(.+?) (?:il )?(?:reste|me reste|en stock|ai je)|il (?:me )?reste combien (?:de |d )?(.+)|stock (?:de |du |des |d )?(.+)|how many (.+?) (?:left|in stock))\s*$",
    ).firstMatch(t);
    if (stock != null) {
      final p =
          stock.group(1) ?? stock.group(2) ?? stock.group(3) ?? stock.group(4);
      return StockQueryIntent(p?.trim());
    }
    if (RegExp(r'ruptures?|a commander|que commander|stock bas').hasMatch(t)) {
      return const StockQueryIntent(null);
    }

    return UnknownIntent(input);
  }

  String _prepare(String input) {
    var t = normalize(input)
        .replaceAll(RegExp(r"[’'?!.]"), ' ')
        .replaceAll(RegExp(r'(?<=\d)[\s.](?=\d{3}\b)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    t = t.split(' ').map((w) => _numbers[w]?.toString() ?? w).join(' ');
    // « 20 mille » → 20000
    t = t.replaceAllMapped(
      RegExp(r'(\d+) mille'),
      (m) => '${int.parse(m.group(1)!) * 1000}',
    );
    return t.replaceAll(' mille', ' 1000').replaceAll('mille ', '1000 ');
  }

  (PayKind, int?) _payment(String text) {
    if (text.isEmpty) return (PayKind.full, null);
    if (RegExp(r'moitie|half').hasMatch(text)) return (PayKind.half, null);
    if (RegExp(r'\brien\b|nothing|credit').hasMatch(text)) {
      return (PayKind.none, null);
    }
    final n = RegExp(r'(\d+)').firstMatch(text);
    if (n != null) return (PayKind.amount, int.parse(n.group(1)!));
    return (PayKind.full, null);
  }

  String? _method(String text) {
    for (final e in _methods.entries) {
      if (RegExp('\\b${e.key}\\b').hasMatch(text)) return e.value;
    }
    return null;
  }
}

/// Trouve l'élément dont le nom ressemble le plus à `query`, en comptant
/// les mots en commun (« sacs de riz » trouve « Riz 25 kg »).
T? bestMatch<T>(String query, List<T> items, String Function(T) nameOf) {
  const stop = {
    'de',
    'du',
    'des',
    'd',
    'la',
    'le',
    'les',
    'l',
    'sac',
    'sacs',
    'bidon',
    'bidons',
    'paquet',
    'paquets',
    'boite',
    'boites',
    'carton',
    'cartons',
    'piece',
    'pieces',
    'of',
    'bag',
    'bags',
    'kg',
  };
  Set<String> words(String s) => normalize(s)
      .split(RegExp(r'[^a-z0-9]+'))
      .where((w) => w.isNotEmpty && !stop.contains(w))
      .map(
        (w) =>
            w.length > 3 && w.endsWith('s') ? w.substring(0, w.length - 1) : w,
      )
      .toSet();
  final q = words(query);
  if (q.isEmpty) return null;
  T? best;
  var bestScore = 0.0;
  for (final item in items) {
    final n = words(nameOf(item));
    final common = q.intersection(n).length;
    if (common == 0) continue;
    final score = common / (n.length + q.length - common);
    if (score > bestScore) {
      bestScore = score;
      best = item;
    }
  }
  return best;
}
