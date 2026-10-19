import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/voice/intent_parser.dart';

void main() {
  final p = IntentParser();

  test('vente avec client et moitié payée par Wave', () {
    final i = p.parse(
      'Vends 3 sacs de riz à Fatou, elle paie la moitié par Wave.',
    ) as SellIntent;
    expect(i.qty, 3);
    expect(i.product, 'sacs de riz');
    expect(i.client, 'fatou');
    expect(i.pay, PayKind.half);
    expect(i.method, 'wave');
  });

  test('nombres en lettres et vente comptant', () {
    final i = p.parse('vends deux bidons d’huile') as SellIntent;
    expect(i.qty, 2);
    expect(i.product, 'bidons d huile');
    expect(i.client, isNull);
    expect(i.pay, PayKind.full);
  });

  test('vente à crédit', () {
    final i = p.parse('Vends 1 sac de riz à Kouassi à crédit') as SellIntent;
    expect(i.client, 'kouassi');
    expect(i.pay, PayKind.none);
  });

  test('montant payé en chiffres', () {
    final i = p.parse('vends 4 riz à Aya elle paie 20 000') as SellIntent;
    expect(i.pay, PayKind.amount);
    expect(i.amount, 20000);
  });

  test('entrée en stock', () {
    final i = p.parse("J'ai reçu 10 bidons d'huile") as AddStockIntent;
    expect(i.qty, 10);
    expect(i.product, 'bidons d huile');
  });

  test('questions', () {
    expect(p.parse('Qui me doit ?'), isA<DebtQueryIntent>());
    expect(
      (p.parse('Combien me doit Kouassi ?') as DebtQueryIntent).client,
      'kouassi',
    );
    expect(
      p.parse("Combien j'ai vendu aujourd'hui ?"),
      isA<SalesTodayIntent>(),
    );
    expect(
      (p.parse('Combien de riz il reste ?') as StockQueryIntent).product,
      'riz',
    );
    expect(
      (p.parse('Il reste combien de sucre') as StockQueryIntent).product,
      'sucre',
    );
    expect((p.parse('Que commander ?') as StockQueryIntent).product, isNull);
  });

  test('phrase inconnue', () {
    expect(p.parse('Raconte-moi une blague'), isA<UnknownIntent>());
  });

  test('anglais simple', () {
    final i = p.parse('Sell 2 bags of rice to Fatou') as SellIntent;
    expect(i.qty, 2);
    expect(i.client, 'fatou');
  });

  test('bestMatch retrouve le bon article', () {
    final names = ['Riz 25 kg', 'Huile 1 L', 'Sucre 1 kg'];
    expect(bestMatch('sacs de riz', names, (s) => s), 'Riz 25 kg');
    expect(bestMatch('bidons d huile', names, (s) => s), 'Huile 1 L');
    expect(bestMatch('savon', names, (s) => s), isNull);
  });
}
