import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/checkout.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../booking/booking_screens.dart';

/// Tier, blue tick progress, fees and storage for the signed-in instructor.
final teacherStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(apiProvider).get('/teacher/status'));

/// The rules shown before someone applies to teach (public).
final instructorRulesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(apiProvider).get('/instructor-rules'));

String bps(Object? v) {
  final n = (v as num? ?? 0) / 100;
  return '${n == n.roundToDouble() ? n.toInt() : n}%';
}

/// Silver / Gold badge, and the blue tick.
class TierBadge extends StatelessWidget {
  const TierBadge(this.tier, {super.key, this.size = 13});
  final String? tier;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (tier == null) return const SizedBox.shrink();
    final gold = tier == 'GOLD';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gold ? const [Color(0xFFF7D774), Color(0xFFD4A017)] : const [Color(0xFFE8ECEF), Color(0xFFAEB7BE)]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.workspace_premium_rounded, size: size + 2, color: gold ? const Color(0xFF6B4E00) : const Color(0xFF3D4A52)),
        const SizedBox(width: 4),
        Text(gold ? t('Gold', 'গোল্ড') : t('Silver', 'সিলভার'),
            style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: gold ? const Color(0xFF6B4E00) : const Color(0xFF3D4A52))),
      ]),
    );
  }
}

class BlueTick extends StatelessWidget {
  const BlueTick({super.key, this.size = 18});
  final double size;
  @override
  Widget build(BuildContext context) => Tooltip(
        message: t('Verified instructor', 'ভেরিফায়েড ইন্সট্রাক্টর'),
        child: Icon(Icons.verified_rounded, size: size, color: const Color(0xFF1D9BF0)),
      );
}

class _Bar extends StatelessWidget {
  const _Bar(this.label, this.value, this.target, {this.unit = ''});
  final String label;
  final int value;
  final int target;
  final String unit;
  @override
  Widget build(BuildContext context) {
    final done = value >= target;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked, size: 16, color: done ? Brand.success : Brand.muted),
          const SizedBox(width: 6),
          Expanded(child: Text(label)),
          Text('${compact(value)} / ${compact(target)}$unit', style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(value: target == 0 ? 1 : (value / target).clamp(0, 1).toDouble(), minHeight: 6, color: done ? Brand.success : null),
        ),
      ]),
    );
  }
}

/// Top of the instructor dashboard: tier, blue tick progress and storage use.
class InstructorStatusCards extends ConsumerWidget {
  const InstructorStatusCards({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(teacherStatusProvider);
    final text = Theme.of(context).textTheme;
    return status.when(
      loading: () => const Skeleton(height: 120),
      error: (_, _) => const SizedBox.shrink(),
      data: (s) {
        final v = s['verification'] as Map<String, dynamic>;
        final targets = v['targets'] as Map<String, dynamic>;
        final fees = s['fees'] as Map<String, dynamic>;
        final storage = s['storage'] as Map<String, dynamic>;
        final next = s['nextTier'] as Map<String, dynamic>?;
        final sales = s['sales'] as int;
        final limit = storage['limit'] as int?;
        final videos = storage['videos'] as int;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Level card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(gradient: Brand.teachGradient, borderRadius: BorderRadius.circular(Gap.l)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(t('Your level', 'আপনার লেভেল'), style: const TextStyle(color: Colors.white70)),
                const Spacer(),
                if (v['verified'] == true) ...[const BlueTick(), const SizedBox(width: 6)],
                TierBadge(s['tier'] as String?),
              ]),
              const SizedBox(height: 6),
              Text(
                s['tier'] == 'GOLD'
                    ? t('Gold instructor', 'গোল্ড ইন্সট্রাক্টর')
                    : s['tier'] == 'SILVER'
                        ? t('Silver instructor', 'সিলভার ইন্সট্রাক্টর')
                        : t('Rising instructor', 'উদীয়মান ইন্সট্রাক্টর'),
                style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                t('${plural(sales, 'course sale')} · course fee ${bps(fees['courseCommissionBps'])} · 1:1 fee ${bps(fees['sessionCommissionBps'])} · VAT ${bps(fees['vatBps'])}',
                    '$salesটি কোর্স বিক্রি · কোর্স ফি ${bps(fees['courseCommissionBps'])} · ১:১ ফি ${bps(fees['sessionCommissionBps'])} · VAT ${bps(fees['vatBps'])}'),
                style: const TextStyle(color: Colors.white, fontSize: 12.5),
              ),
              if (next != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: (sales / (next['at'] as int)).clamp(0, 1).toDouble(),
                    minHeight: 7,
                    color: Brand.orange,
                    backgroundColor: Colors.white24,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  next['name'] == 'SILVER'
                      ? t('${(next['at'] as int) - sales} more sales to Silver: course fee drops to ${bps(fees['silverCourseCommissionBps'])}',
                          'সিলভার হতে আর ${(next['at'] as int) - sales}টি বিক্রি: কোর্স ফি কমে ${bps(fees['silverCourseCommissionBps'])}')
                      : t('${(next['at'] as int) - sales} more sales to Gold: course fee drops to ${bps(fees['goldCourseCommissionBps'])}',
                          'গোল্ড হতে আর ${(next['at'] as int) - sales}টি বিক্রি: কোর্স ফি কমে ${bps(fees['goldCourseCommissionBps'])}'),
                  style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ],
            ]),
          ),
          // Blue tick progress (until paid courses are unlocked)
          if (v['canSellPaid'] != true) ...[
            const SizedBox(height: 12),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const BlueTick(size: 22),
                  const SizedBox(width: 8),
                  Expanded(child: Text(t('Unlock paid courses', 'পেইড কোর্স চালু করুন'), style: text.titleMedium)),
                ]),
                const SizedBox(height: 4),
                Text(t('New instructors start with free courses. Reach all three targets to get the blue tick; after that you can sell your courses.',
                    'নতুন ইন্সট্রাক্টররা ফ্রি কোর্স দিয়ে শুরু করেন। তিনটা লক্ষ্য পূরণ হলে ব্লু টিক পাবেন, তারপর থেকে কোর্স বিক্রি করতে পারবেন।'), style: text.bodySmall),
                _Bar(t('Free courses published', 'পাবলিশ করা ফ্রি কোর্স'), v['freeCourses'] as int, targets['freeCourses'] as int),
                _Bar(t('Lesson views', 'লেসন ভিউ'), v['views'] as int, targets['views'] as int),
                _Bar(t('Watch time', 'দেখার সময়'), v['watchMinutes'] as int, targets['watchMinutes'] as int, unit: t(' min', ' মিনিট')),
              ]),
            ),
          ],
          // Storage
          if (limit != null) ...[
            const SizedBox(height: 12),
            Panel(
              onTap: () => context.push('/teacher/storage'),
              child: Row(children: [
                const IconBadge(Icons.cloud_upload_outlined, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('Video storage · ${_planName(storage['plan'] as String)}', 'ভিডিও স্টোরেজ · ${_planName(storage['plan'] as String)}'), style: text.titleSmall),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(value: (videos / limit).clamp(0, 1).toDouble(), minHeight: 6, color: videos >= limit ? Brand.orangeStrong : null),
                    ),
                    const SizedBox(height: 4),
                    Text(t('$videos of $limit videos used', '$limit-এর মধ্যে $videosটি ভিডিও ব্যবহার হয়েছে'), style: text.bodySmall),
                  ]),
                ),
                const SizedBox(width: 8),
                Text(t('Upgrade', 'আপগ্রেড'), style: const TextStyle(color: Brand.orangeStrong, fontWeight: FontWeight.w700)),
              ]),
            ),
          ],
        ]);
      },
    );
  }
}

String _planName(String plan) => switch (plan) {
      'STARTER' => 'Starter',
      'PRO' => 'Pro',
      'UNLIMITED' => 'Unlimited',
      _ => t('Free', 'ফ্রি'),
    };

/// Requests waiting for the instructor's answer, shown on the dashboard.
class BookingRequestsCard extends ConsumerWidget {
  const BookingRequestsCard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(teacherBookingsProvider).value ?? const [];
    final requests = list.where((b) => b['status'] == 'REQUESTED').toList();
    if (requests.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(t('Booking requests (${requests.length})', 'বুকিং রিকোয়েস্ট (${requests.length})'), padding: const EdgeInsets.fromLTRB(0, 20, 0, 6)),
      for (final b in requests) BookingTile(b as Map<String, dynamic>, asTeacher: true),
    ]);
  }
}

/// Plans for more than the free number of videos. Yearly costs 10 months.
class StoragePlansScreen extends ConsumerStatefulWidget {
  const StoragePlansScreen({super.key});
  @override
  ConsumerState<StoragePlansScreen> createState() => _StoragePlansScreenState();
}

class _StoragePlansScreenState extends ConsumerState<StoragePlansScreen> {
  bool _yearly = false;
  String? _busy;

  Future<void> _buy(String plan) async {
    setState(() => _busy = plan);
    try {
      final res = await ref.read(apiProvider).post<Map<String, dynamic>>('/teacher/storage-plan', {'plan': plan, 'months': _yearly ? 12 : 1});
      if (!mounted) return;
      if (await payOrder(context, ref, res)) {
        ref.invalidate(teacherStatusProvider);
        if (mounted) showMessage(context, t('Your plan is active.', 'আপনার প্ল্যান চালু হয়েছে।'));
      }
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(teacherStatusProvider);
    final text = Theme.of(context).textTheme;
    final date = DateFormat('d MMM y');
    return Scaffold(
      appBar: AppBar(title: Text(t('Storage plans', 'স্টোরেজ প্ল্যান'))),
      body: AsyncView(
        value: status,
        onRetry: () => ref.invalidate(teacherStatusProvider),
        data: (s) {
          final storage = s['storage'] as Map<String, dynamic>;
          final current = storage['plan'] as String;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(t('Your first ${storage['plans'][0]['videos']} videos are free. Pick a plan to upload more.', 'প্রথম ${storage['plans'][0]['videos']}টি ভিডিও ফ্রি। আরও আপলোড করতে একটা প্ল্যান বেছে নিন।'), style: text.bodyMedium),
            if (current != 'FREE' && storage['until'] != null) ...[
              const SizedBox(height: 8),
              Tag(t('${_planName(current)} until ${date.format(DateTime.parse(storage['until'] as String).toLocal())}', '${_planName(current)} চলবে ${date.format(DateTime.parse(storage['until'] as String).toLocal())} পর্যন্ত'),
                  color: const Color(0xFFD7F5E6), textColor: const Color(0xFF13633F), icon: Icons.check_circle_rounded),
            ],
            const SizedBox(height: 16),
            Center(
              child: SegmentedButton<bool>(
                segments: [
                  ButtonSegment(value: false, label: Text(t('Monthly', 'মাসিক'))),
                  ButtonSegment(value: true, label: Text(t('Yearly · 2 months free', 'বার্ষিক · ২ মাস ফ্রি'))),
                ],
                selected: {_yearly},
                onSelectionChanged: (v) => setState(() => _yearly = v.first),
              ),
            ),
            const SizedBox(height: 16),
            for (final p in storage['plans'] as List)
              if (p['plan'] != 'FREE')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Panel(
                    child: Row(children: [
                      IconBadge(p['plan'] == 'UNLIMITED' ? Icons.all_inclusive_rounded : Icons.cloud_outlined, size: 44, color: p['plan'] == 'PRO' ? Brand.orangeStrong : null),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Text(_planName(p['plan'] as String), style: text.titleMedium),
                            if (p['plan'] == 'PRO') ...[const SizedBox(width: 8), Tag(t('Popular', 'জনপ্রিয়'), color: const Color(0xFFFFE9C7), textColor: const Color(0xFF7A4A00))],
                          ]),
                          Text(p['videos'] == null ? t('Unlimited videos', 'আনলিমিটেড ভিডিও') : t('Up to ${p['videos']} videos', '${p['videos']}টি পর্যন্ত ভিডিও'), style: text.bodySmall),
                          const SizedBox(height: 4),
                          Text(
                            _yearly ? t('${taka(p['yearlyPaisa'] as int)} / year', '${taka(p['yearlyPaisa'] as int)} / বছর') : t('${taka(p['monthlyPaisa'] as int)} / month', '${taka(p['monthlyPaisa'] as int)} / মাস'),
                            style: text.titleSmall?.copyWith(color: Brand.orangeStrong),
                          ),
                        ]),
                      ),
                      FilledButton(
                        onPressed: _busy != null ? null : () => _buy(p['plan'] as String),
                        child: Text(_busy == p['plan'] ? '…' : current == p['plan'] ? t('Renew', 'রিনিউ') : t('Buy', 'কিনুন')),
                      ),
                    ]),
                  ),
                ),
          ]);
        },
      ),
    );
  }
}

/// Instructor's public profile: headline, bio, experience, expertise and hourly rate.
class TeacherProfileEditScreen extends ConsumerStatefulWidget {
  const TeacherProfileEditScreen({super.key});
  @override
  ConsumerState<TeacherProfileEditScreen> createState() => _TeacherProfileEditScreenState();
}

class _TeacherProfileEditScreenState extends ConsumerState<TeacherProfileEditScreen> {
  final _form = GlobalKey<FormState>();
  final _headline = TextEditingController();
  final _bio = TextEditingController();
  final _experience = TextEditingController();
  final _expertise = TextEditingController();
  final _rate = TextEditingController();
  bool _loaded = false;
  bool _busy = false;

  void _fill(Map<String, dynamic> p) {
    if (_loaded) return;
    _loaded = true;
    _headline.text = p['headline'] as String? ?? '';
    _bio.text = p['bio'] as String? ?? '';
    _experience.text = p['experience'] as String? ?? '';
    _expertise.text = ((p['expertise'] as List?)?.isNotEmpty == true ? p['expertise'] as List : (p['skills'] as List? ?? const [])).join(', ');
    final rate = p['hourlyRatePaisa'] as int?;
    _rate.text = rate == null ? '' : '${rate ~/ 100}';
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final tags = _expertise.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      await ref.read(apiProvider).patch('/teacher/profile', {
        'headline': _headline.text.trim(),
        'bio': _bio.text.trim(),
        'experience': _experience.text.trim(),
        'expertise': tags,
        'skills': tags,
        if (_rate.text.trim().isNotEmpty) 'hourlyRateBdt': int.parse(_rate.text.trim()),
      });
      ref.invalidate(teacherStatusProvider);
      if (mounted) {
        showMessage(context, t('Profile saved', 'প্রোফাইল সেভ হয়েছে'));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(teacherStatusProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Instructor profile', 'ইন্সট্রাক্টর প্রোফাইল'))),
      body: AsyncView(
        value: status,
        onRetry: () => ref.invalidate(teacherStatusProvider),
        data: (s) {
          _fill(s['profile'] as Map<String, dynamic>);
          return Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              TextFormField(
                controller: _headline,
                decoration: InputDecoration(labelText: t('Headline (e.g. Flutter developer, 5 years)', 'শিরোনাম (যেমন: ৫ বছরের Flutter ডেভেলপার)')),
                validator: (v) => (v ?? '').trim().length < 5 ? t('At least 5 characters', 'কমপক্ষে ৫ অক্ষর') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _bio,
                minLines: 4,
                maxLines: 8,
                decoration: InputDecoration(labelText: t('Bio', 'নিজের সম্পর্কে'), alignLabelWithHint: true),
                validator: (v) => (v ?? '').trim().length < 30 ? t('At least 30 characters', 'কমপক্ষে ৩০ অক্ষর') : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _experience,
                minLines: 3,
                maxLines: 6,
                decoration: InputDecoration(labelText: t('Experience (jobs, projects, years)', 'অভিজ্ঞতা (চাকরি, প্রজেক্ট, কত বছর)'), alignLabelWithHint: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _expertise,
                decoration: InputDecoration(labelText: t('Expertise (comma separated)', 'দক্ষতা (কমা দিয়ে আলাদা করুন)'), helperText: 'Flutter, Firebase, UI design'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rate,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t('1:1 price per hour (BDT)', '১:১ সেশনের ঘণ্টাপ্রতি দাম (টাকা)'),
                  helperText: t('A 30-minute session costs half, 90 minutes one and a half.', '৩০ মিনিটের সেশনে অর্ধেক, ৯০ মিনিটে দেড় গুণ।'),
                  prefixText: '৳ ',
                ),
                validator: (v) => (v ?? '').trim().isEmpty || int.tryParse(v!.trim()) != null ? null : t('Numbers only', 'শুধু সংখ্যা'),
              ),
              const SizedBox(height: 24),
              CtaButton(busy: _busy, label: t('Save', 'সেভ করুন'), onPressed: _save),
            ]),
          );
        },
      ),
    );
  }
}

/// Fee breakdown for one earning: price - platform fee - VAT = you get.
class FeeBreakdownTile extends StatelessWidget {
  const FeeBreakdownTile(this.entry, {super.key});
  final Map<String, dynamic> entry;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final date = DateFormat('d MMM y');
    final gross = entry['grossPaisa'] as int? ?? 0;
    final refund = entry['type'] == 'REFUND';
    final status = entry['status'] as String?;
    if (refund || gross == 0) {
      return ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: Text(refund ? t('Refund deduction', 'রিফান্ড কর্তন') : t('Sale', 'বিক্রি')),
        subtitle: Text(date.format(DateTime.parse(entry['createdAt'] as String).toLocal())),
        trailing: Text(taka(entry['amountPaisa'] as int)),
      );
    }
    Widget row(String label, String value, {bool strong = false, Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label, style: strong ? text.titleSmall : text.bodySmall)),
            Text(value, style: (strong ? text.titleSmall : text.bodySmall)?.copyWith(color: color)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Panel(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            Expanded(child: Text(date.format(DateTime.parse(entry['createdAt'] as String).toLocal()), style: text.labelMedium)),
            Tag(
              switch (status) {
                'AVAILABLE' => t('Available', 'উত্তোলনযোগ্য'),
                'PAID' => t('Paid out', 'পেয়েছেন'),
                'VOID' => t('Refunded', 'ফেরত গেছে'),
                _ => t('On hold', 'হোল্ডে'),
              },
              color: status == 'AVAILABLE' ? const Color(0xFFD7F5E6) : null,
              textColor: status == 'AVAILABLE' ? const Color(0xFF13633F) : null,
            ),
          ]),
          const SizedBox(height: 6),
          row(t('Student paid', 'শিক্ষার্থী দিয়েছে'), taka(gross)),
          row(t('Platform fee (${bps(entry['commissionBps'])})', 'প্ল্যাটফর্ম ফি (${bps(entry['commissionBps'])})'), '− ${taka(entry['commissionPaisa'] as int)}', color: Brand.muted),
          row(t('VAT', 'ভ্যাট'), '− ${taka(entry['vatPaisa'] as int)}', color: Brand.muted),
          const Divider(height: 12),
          row(t('You get', 'আপনি পাবেন'), taka(entry['amountPaisa'] as int), strong: true, color: Brand.success),
        ]),
      ),
    );
  }
}

/// The instructor rules, shown on the application screen with an "I agree" box.
class InstructorRulesCard extends ConsumerWidget {
  const InstructorRulesCard({super.key, required this.accepted, required this.onChanged});
  final bool accepted;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rules = ref.watch(instructorRulesProvider);
    final text = Theme.of(context).textTheme;
    return rules.when(
      loading: () => const Skeleton(height: 160),
      error: (e, _) => Text(e.toString()),
      data: (r) {
        final plans = (r['plans'] as List).map((p) => '${_planName(p['plan'] as String)} ${taka(p['monthlyPaisa'] as int)}').join(' · ');
        final items = [
          (Icons.payments_outlined, t('Students pay the platform first. Your money is held safely and released to you ${r['holdDays']} days after the sale or session.',
              'শিক্ষার্থী প্রথমে প্ল্যাটফর্মে টাকা দেয়। টাকা নিরাপদে জমা থাকে, বিক্রি বা সেশনের ${r['holdDays']} দিন পর আপনার ব্যালান্সে আসে।')),
          (Icons.event_available_outlined, t('1:1 sessions: ${bps(r['sessionCommissionBps'])} platform fee + ${bps(r['vatBps'])} VAT per booking. Accept or decline each request within ${r['bookingResponseHours']} hours; declined requests are refunded.',
              '১:১ সেশন: প্রতি বুকিংয়ে ${bps(r['sessionCommissionBps'])} প্ল্যাটফর্ম ফি + ${bps(r['vatBps'])} ভ্যাট। প্রতিটা রিকোয়েস্ট ${r['bookingResponseHours']} ঘণ্টার মধ্যে গ্রহণ বা বাতিল করবেন; বাতিল হলে টাকা ফেরত যায়।')),
          (Icons.ondemand_video_outlined, t('Recorded courses: ${bps(r['courseCommissionBps'])} platform fee + ${bps(r['vatBps'])} VAT per sale. Silver (${r['silverSales']} sales) pays ${bps(r['silverCourseCommissionBps'])}, Gold (${r['goldSales']} sales) pays ${bps(r['goldCourseCommissionBps'])}.',
              'রেকর্ডেড কোর্স: প্রতি বিক্রিতে ${bps(r['courseCommissionBps'])} প্ল্যাটফর্ম ফি + ${bps(r['vatBps'])} ভ্যাট। সিলভার (${r['silverSales']} বিক্রি) হলে ${bps(r['silverCourseCommissionBps'])}, গোল্ড (${r['goldSales']} বিক্রি) হলে ${bps(r['goldCourseCommissionBps'])}।')),
          (Icons.verified_outlined, t('Your first ${r['freeCoursesRequired']} courses are free. After ${compact(r['viewsRequired'] as int)} views and ${compact(r['watchMinutesRequired'] as int)} minutes of watch time you get the blue tick and can sell courses.',
              'প্রথম ${r['freeCoursesRequired']}টি কোর্স ফ্রি দিতে হবে। ${compact(r['viewsRequired'] as int)} ভিউ আর ${compact(r['watchMinutesRequired'] as int)} মিনিট দেখার সময় হলে ব্লু টিক পাবেন, তখন কোর্স বিক্রি করতে পারবেন।')),
          (Icons.cloud_upload_outlined, t('${r['freeVideoLimit']} videos are free. More needs a storage plan: $plans per month.', '${r['freeVideoLimit']}টি ভিডিও ফ্রি। এর বেশি হলে স্টোরেজ প্ল্যান লাগবে: মাসে $plans।')),
        ];
        return Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('Instructor rules', 'ইন্সট্রাক্টর নিয়মাবলি'), style: text.titleMedium),
            const SizedBox(height: 8),
            for (final (icon, line) in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 20, color: Brand.orangeStrong),
                  const SizedBox(width: 10),
                  Expanded(child: Text(line)),
                ]),
              ),
            const Divider(),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: accepted,
              onChanged: (v) => onChanged(v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(t('I have read and agree to these rules', 'আমি নিয়মগুলো পড়েছি এবং রাজি আছি'), style: text.titleSmall),
            ),
          ]),
        );
      },
    );
  }
}
