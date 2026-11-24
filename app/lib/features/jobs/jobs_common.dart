import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/i18n.dart';

Map<String, String> get jobTypes => {
  'FULL_TIME': t('Full time', 'ফুল টাইম'),
  'PART_TIME': t('Part time', 'পার্ট টাইম'),
  'REMOTE': t('Remote', 'রিমোট'),
  'CONTRACT': t('Contract', 'কন্ট্রাক্ট'),
  'INTERNSHIP': t('Internship', 'ইন্টার্নশিপ'),
};

Map<String, String> get stages => {
  'APPLIED': t('New', 'নতুন'),
  'SHORTLISTED': t('Shortlisted', 'শর্টলিস্টেড'),
  'INTERVIEW': t('Interview', 'ইন্টারভিউ'),
  'HIRED': t('Hired', 'নিয়োগ'),
  'REJECTED': t('Rejected', 'বাদ'),
};

Map<String, String> get jobStatuses => {
  'PENDING': t('In review', 'রিভিউতে আছে'),
  'LIVE': t('Live', 'লাইভ'),
  'CLOSED': t('Closed', 'বন্ধ'),
  'REJECTED': t('Not approved', 'অনুমোদন হয়নি'),
};

final _n = NumberFormat.decimalPattern('en_IN');
final deadlineFormat = DateFormat('d MMM yyyy');

/// "৳25,000 – ৳40,000 / মাস", or null when the employer left salary out.
String? salary(Map<String, dynamic> job) {
  final lo = job['salaryMin'] as int?;
  final hi = job['salaryMax'] as int?;
  if (lo == null && hi == null) return null;
  if (lo != null && hi != null) return t('৳${_n.format(lo)} – ৳${_n.format(hi)} / month', '৳${_n.format(lo)} – ৳${_n.format(hi)} / মাস');
  return t('৳${_n.format(lo ?? hi)} / month', '৳${_n.format(lo ?? hi)} / মাস');
}

String? deadline(Map<String, dynamic> job) {
  final d = job['deadline'] as String?;
  return d == null ? null : t('Deadline ${deadlineFormat.format(DateTime.parse(d).toLocal())}', 'শেষ তারিখ ${deadlineFormat.format(DateTime.parse(d).toLocal())}');
}

Color stageColor(BuildContext context, String stage) {
  final c = Theme.of(context).colorScheme;
  return switch (stage) {
    'HIRED' => Colors.green.shade700,
    'REJECTED' => c.error,
    'APPLIED' => c.outline,
    _ => c.primary,
  };
}

class StatusPill extends StatelessWidget {
  const StatusPill(this.text, {super.key, this.color});
  final String text;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

/// Splits "Flutter, Dart, Firebase" into a clean list.
List<String> splitSkills(String text) =>
    text.split(RegExp(r'[,،\n]')).map((s) => s.trim()).where((s) => s.isNotEmpty).toSet().toList();
