import 'package:flutter_test/flutter_test.dart';
import 'package:techdropout/core/format.dart';
import 'package:techdropout/core/router.dart';

void main() {
  test('taka formats paisa with South Asian grouping', () {
    expect(taka(150000), '৳1,500');
    expect(taka(12345600), '৳1,23,456');
  });

  test('free courses show as ফ্রি', () {
    expect(price({'isFree': true, 'pricePaisa': 0}), 'ফ্রি');
    expect(price({'isFree': false, 'pricePaisa': 99900}), '৳999');
  });

  test('tabs follow roles', () {
    expect(tabsFor(null).length, 3);
  });
}
