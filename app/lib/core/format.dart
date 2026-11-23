import 'package:intl/intl.dart';
import 'config.dart';

final _taka = NumberFormat.decimalPattern('en_IN');

/// 150000 paisa -> "৳1,500"
String taka(int paisa) => '৳${_taka.format(paisa ~/ 100)}';

String price(Map<String, dynamic> course) =>
    course['isFree'] == true ? 'ফ্রি' : taka(course['pricePaisa'] as int);

/// Price as students see it in the catalog. Store builds don't show prices for paid courses.
String catalogPrice(Map<String, dynamic> course, {bool store = storeBuild}) =>
    course['isFree'] != true && store ? 'প্রিমিয়াম' : price(course);

String duration(int seconds) {
  final m = seconds ~/ 60;
  return m >= 60 ? '${m ~/ 60} ঘণ্টা ${m % 60} মিনিট' : '$m মিনিট';
}
