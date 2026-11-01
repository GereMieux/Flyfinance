import 'package:flutter_test/flutter_test.dart';
import 'package:flyfinance/voice/wake.dart';

void main() {
  test('mot de réveil Hello Zara', () {
    expect(afterWakeWord('Hello Zara'), '');
    expect(
      afterWakeWord('hello zara, combien j’ai vendu ?'),
      'combien j’ai vendu ?',
    );
    expect(afterWakeWord('OK Sara vends 2 sacs de riz'), 'vends 2 sacs de riz');
    expect(afterWakeWord('Zara'), '');
    expect(afterWakeWord('Sara a payé'), isNull);
    expect(afterWakeWord('vends 2 sacs'), isNull);
    expect(afterWakeWord('Zarafa'), isNull);
  });
}
