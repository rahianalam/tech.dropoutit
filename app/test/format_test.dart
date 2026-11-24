import 'package:flutter_test/flutter_test.dart';
import 'package:techdropout/core/auth.dart';
import 'package:techdropout/core/format.dart';
import 'package:techdropout/core/i18n.dart';
import 'package:techdropout/core/router.dart';

void main() {
  test('taka formats paisa with South Asian grouping', () {
    expect(taka(150000), '৳1,500');
    expect(taka(12345600), '৳1,23,456');
  });

  test('English is the default; Bangla only when chosen', () {
    expect(currentLang, Lang.en);
    expect(price({'isFree': true, 'pricePaisa': 0}), 'Free');
    expect(t('Home', 'হোম'), 'Home');
  });

  test('free courses and store builds', () {
    expect(price({'isFree': false, 'pricePaisa': 99900}), '৳999');
    expect(catalogPrice({'isFree': false, 'pricePaisa': 99900}, store: true), 'Premium');
    expect(catalogPrice({'isFree': true, 'pricePaisa': 0}, store: true), 'Free');
    expect(catalogPrice({'isFree': false, 'pricePaisa': 99900}, store: false), '৳999');
  });

  test('struck-through price only when it is really higher', () {
    expect(originalPrice({'isFree': false, 'pricePaisa': 99900, 'originalPricePaisa': 199900}), '৳1,999');
    expect(originalPrice({'isFree': false, 'pricePaisa': 99900, 'originalPricePaisa': 99900}), isNull);
    expect(originalPrice({'isFree': false, 'pricePaisa': 99900, 'originalPricePaisa': 199900}, store: true), isNull);
    expect(discountPct({'isFree': false, 'pricePaisa': 50000, 'originalPricePaisa': 100000}), 50);
  });

  test('durations read naturally', () {
    expect(duration(300), '5 min');
    expect(duration(3900), '1h 5m');
    expect(hours(5400), '1.5 hours');
  });

  test('tabs follow roles and never exceed five', () {
    expect(tabsFor(null).map((t) => t.path), ['/', '/search', '/learning', '/jobs', '/profile']);
    final teacher = Me({'id': 't', 'name': 'T', 'roles': ['STUDENT', 'TEACHER']});
    expect(tabsFor(teacher).map((t) => t.path), ['/', '/search', '/learning', '/teacher', '/profile']);
    final admin = Me({'id': 'a', 'name': 'A', 'roles': ['ADMIN', 'TEACHER']});
    expect(tabsFor(admin).map((t) => t.path), ['/', '/search', '/jobs', '/admin', '/profile']);
  });
}
