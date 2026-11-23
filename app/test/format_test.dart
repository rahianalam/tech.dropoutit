import 'package:flutter_test/flutter_test.dart';
import 'package:techdropout/core/auth.dart';
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
    expect(tabsFor(null).map((t) => t.path), ['/', '/learning', '/jobs', '/profile']);
    final teacher = Me({'id': 't', 'name': 'T', 'roles': ['STUDENT', 'TEACHER']});
    expect(tabsFor(teacher).map((t) => t.path), contains('/teacher'));
    final admin = Me({'id': 'a', 'name': 'A', 'roles': ['ADMIN', 'TEACHER']});
    expect(tabsFor(admin).length, 5);
    expect(tabsFor(admin).map((t) => t.path), isNot(contains('/teacher')));
  });
}
