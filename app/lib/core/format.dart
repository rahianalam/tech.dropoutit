import 'package:intl/intl.dart';
import 'config.dart';
import 'i18n.dart';

final _taka = NumberFormat.decimalPattern('en_IN');

/// 150000 paisa -> "৳1,500"
String taka(int paisa) => '৳${_taka.format(paisa ~/ 100)}';

String price(Map<String, dynamic> course) => course['isFree'] == true ? t('Free', 'ফ্রি') : taka(course['pricePaisa'] as int);

/// Price as students see it in the catalog. Store builds don't show prices for paid courses.
String catalogPrice(Map<String, dynamic> course, {bool store = storeBuild}) =>
    course['isFree'] != true && store ? t('Premium', 'প্রিমিয়াম') : price(course);

/// "Was" price to strike through, only when it is really higher (never in store builds).
String? originalPrice(Map<String, dynamic> course, {bool store = storeBuild}) {
  final was = course['originalPricePaisa'] as int?;
  if (store || course['isFree'] == true || was == null || was <= (course['pricePaisa'] as int)) return null;
  return taka(was);
}

int? discountPct(Map<String, dynamic> course) {
  final was = course['originalPricePaisa'] as int?;
  final now = course['pricePaisa'] as int;
  if (storeBuild || course['isFree'] == true || was == null || was <= now) return null;
  return ((1 - now / was) * 100).round();
}

String duration(int seconds) {
  final m = (seconds / 60).round();
  if (m >= 60) return t('${m ~/ 60}h ${m % 60}m', '${m ~/ 60} ঘণ্টা ${m % 60} মিনিট');
  return t('$m min', '$m মিনিট');
}

/// Total course length, e.g. "12.5 hours".
String hours(int seconds) {
  final h = seconds / 3600;
  if (h < 1) return duration(seconds);
  final v = h >= 10 ? h.round().toString() : h.toStringAsFixed(1).replaceAll('.0', '');
  return t('$v hours', '$v ঘণ্টা');
}

/// 1234 -> "1.2K"
String compact(num n) => NumberFormat.compact().format(n);

String levelLabel(String? level) => switch (level) {
      'BEGINNER' => t('Beginner', 'বিগিনার'),
      'INTERMEDIATE' => t('Intermediate', 'ইন্টারমিডিয়েট'),
      'ADVANCED' => t('Advanced', 'অ্যাডভান্সড'),
      _ => t('All levels', 'সব লেভেল'),
    };

String languageLabel(String? lang) => lang == 'en' ? 'English' : 'বাংলা';

/// "1 lesson", "3 lessons" (English only; Bangla has no plural form).
String plural(Object? count, String one) {
  final n = count is num ? count : num.tryParse('$count') ?? 0;
  return '$n ${n == 1 ? one : '${one}s'}';
}
