import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

const jobTypes = {
  'FULL_TIME': 'ফুল টাইম',
  'PART_TIME': 'পার্ট টাইম',
  'REMOTE': 'রিমোট',
  'CONTRACT': 'কন্ট্রাক্ট',
  'INTERNSHIP': 'ইন্টার্নশিপ',
};

const stages = {
  'APPLIED': 'নতুন',
  'SHORTLISTED': 'শর্টলিস্টেড',
  'INTERVIEW': 'ইন্টারভিউ',
  'HIRED': 'নিয়োগ',
  'REJECTED': 'বাদ',
};

const jobStatuses = {
  'PENDING': 'রিভিউতে আছে',
  'LIVE': 'লাইভ',
  'CLOSED': 'বন্ধ',
  'REJECTED': 'অনুমোদন হয়নি',
};

final _n = NumberFormat.decimalPattern('en_IN');
final deadlineFormat = DateFormat('d MMM yyyy');

/// "৳25,000 – ৳40,000 / মাস", or null when the employer left salary out.
String? salary(Map<String, dynamic> job) {
  final lo = job['salaryMin'] as int?;
  final hi = job['salaryMax'] as int?;
  if (lo == null && hi == null) return null;
  if (lo != null && hi != null) return '৳${_n.format(lo)} – ৳${_n.format(hi)} / মাস';
  return '৳${_n.format(lo ?? hi)} / মাস';
}

String? deadline(Map<String, dynamic> job) {
  final d = job['deadline'] as String?;
  return d == null ? null : 'শেষ তারিখ ${deadlineFormat.format(DateTime.parse(d).toLocal())}';
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
