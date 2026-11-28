import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../core/auth.dart';
import '../../core/checkout.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../learning/my_learning_screen.dart';
import '../teacher/instructor_screens.dart';

final courseProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.read(apiProvider).get('/courses/$id'));

final courseReviewsProvider = FutureProvider.autoDispose.family<List<dynamic>, String>((ref, id) => ref.read(apiProvider).get('/courses/$id/reviews'));

/// Lessons I've finished in a course (empty when signed out or not enrolled).
final courseProgressProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) async {
  if (!ref.read(authProvider).loggedIn) return {'enrolled': false, 'progressPct': 0, 'lessons': []};
  return ref.read(apiProvider).get('/me/courses/$id/progress');
});

Set<String> completedIds(Map<String, dynamic>? progress) => {
      for (final l in (progress?['lessons'] as List? ?? const []))
        if (l['completed'] == true) l['lessonId'] as String,
    };

List<Map<String, dynamic>> allLessons(Map<String, dynamic> course) => [
      for (final s in course['sections'] as List)
        for (final l in s['lessons'] as List) {...l as Map<String, dynamic>, 'sectionTitle': s['title']},
    ];

// ---------------------------------------------------------------------------
// Course detail
// ---------------------------------------------------------------------------

class CourseDetailScreen extends ConsumerStatefulWidget {
  const CourseDetailScreen(this.id, {super.key});
  final String id;
  @override
  ConsumerState<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends ConsumerState<CourseDetailScreen> with WidgetsBindingObserver {
  String get id => widget.id;
  String? _pendingOrder;
  bool _busy = false;
  bool _fullDescription = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When the user comes back from the payment page, check the order a few times.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingOrder != null) _checkOrder();
  }

  void _refreshAll() {
    ref.invalidate(courseProvider(id));
    ref.invalidate(courseProgressProvider(id));
    ref.invalidate(myEnrollmentsProvider);
  }

  Future<void> _checkOrder() async {
    final orderId = _pendingOrder;
    if (orderId == null) return;
    for (var i = 0; i < 6; i++) {
      final o = await ref.read(apiProvider).get<Map<String, dynamic>>('/orders/$orderId');
      if (o['status'] == 'PAID') {
        _pendingOrder = null;
        _refreshAll();
        if (mounted) showSuccess(context, t('Payment successful! Start learning.', 'পেমেন্ট সফল! কোর্স শুরু করুন।'));
        return;
      }
      if (o['status'] != 'PENDING') break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (mounted) {
      showMessage(
        context,
        t('Payment is not confirmed yet. If money was taken it will update in a few minutes.',
            'পেমেন্ট এখনো নিশ্চিত হয়নি। টাকা কেটে থাকলে কিছুক্ষণের মধ্যে আপডেট হবে।'),
      );
    }
  }

  Future<void> _enroll(Map<String, dynamic> course) async {
    if (!ref.read(authProvider).loggedIn) {
      context.push('/login');
      return;
    }
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      final pass = course['isFree'] != true && (ref.read(authProvider).me?.hasFreePass ?? false);
      if (course['isFree'] == true || pass) {
        await api.post('/courses/$id/enroll');
        _refreshAll();
        if (mounted) showSuccess(context, t('You\'re in! Start your first lesson.', 'এনরোল সম্পন্ন! প্রথম লেসন শুরু করুন।'));
      } else {
        // Paid: open the SSLCommerz page (bKash, Nagad, card…). Enrollment happens
        // on the server once the gateway confirms the payment.
        final checkout = await api.post<Map<String, dynamic>>(Uri(path: '/checkout/course/$id', queryParameters: {'ref': ?affiliateRef}).toString());
        _pendingOrder = checkout['orderId'] as String;
        await launchUrl(Uri.parse(checkout['gatewayUrl'] as String), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rate() async {
    final r = await askReview(context);
    if (r == null || !mounted) return;
    try {
      await ref.read(apiProvider).post('/courses/$id/reviews', {'rating': r.$1, if (r.$2.isNotEmpty) 'comment': r.$2});
      ref.invalidate(courseReviewsProvider(id));
      ref.invalidate(courseProvider(id));
      if (mounted) showSuccess(context, t('Thanks for your review!', 'রিভিউয়ের জন্য ধন্যবাদ!'));
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseProvider(id));
    final progress = ref.watch(courseProgressProvider(id)).value;
    return Scaffold(
      body: AsyncView(
        value: course,
        onRetry: () => ref.invalidate(courseProvider(id)),
        data: (c) => _body(context, c, progress),
      ),
      bottomNavigationBar: course.value == null ? null : _bottomBar(context, course.value!, progress),
    );
  }

  bool _locked(Map<String, dynamic> c) => storeBuild && c['enrolled'] != true && c['isFree'] != true && !(ref.read(authProvider).me?.hasFreePass ?? false);

  Map<String, dynamic>? _resumeLesson(Map<String, dynamic> c, Map<String, dynamic>? progress) {
    final lessons = allLessons(c);
    if (lessons.isEmpty) return null;
    final done = completedIds(progress);
    return lessons.firstWhere((l) => !done.contains(l['id']), orElse: () => lessons.first);
  }

  Widget? _bottomBar(BuildContext context, Map<String, dynamic> c, Map<String, dynamic>? progress) {
    final enrolled = c['enrolled'] == true;
    if (_locked(c)) return null;
    final scheme = Theme.of(context).colorScheme;
    final resume = _resumeLesson(c, progress);
    return DecoratedBox(
      decoration: BoxDecoration(color: scheme.surface, border: Border(top: BorderSide(color: scheme.outlineVariant))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            if (!enrolled) ...[
              Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                PriceTag(c, size: 20),
                if (discountPct(c) != null)
                  Text(t('${discountPct(c)}% off', '${discountPct(c)}% ছাড়'), style: const TextStyle(color: Brand.orangeStrong, fontWeight: FontWeight.w600, fontSize: 12)),
              ]),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: CtaButton(
                busy: _busy,
                icon: enrolled ? Icons.play_arrow_rounded : null,
                label: enrolled
                    ? t('Continue learning', 'শেখা চালিয়ে যান')
                    : c['isFree'] == true
                        ? t('Enroll for free', 'ফ্রি এনরোল করুন')
                        : (ref.watch(authProvider).me?.hasFreePass ?? false)
                            ? t('Enroll with free pass', 'ফ্রি পাস দিয়ে এনরোল')
                            : t('Buy now', 'এখনই কিনুন'),
                onPressed: enrolled ? (resume == null ? null : () => context.push('/lessons/${resume['id']}')) : () => _enroll(c),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, Map<String, dynamic> c, Map<String, dynamic>? progress) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final enrolled = c['enrolled'] == true;
    final lessons = allLessons(c);
    final preview = lessons.where((l) => l['isPreview'] == true).firstOrNull;
    final rating = (c['ratingAvg'] as num).toDouble();
    final outcomes = (c['outcomes'] as List? ?? const []).cast<String>();
    final requirements = (c['requirements'] as List? ?? const []).cast<String>();
    final audience = (c['audience'] as List? ?? const []).cast<String>();
    final teacher = c['teacher'] as Map<String, dynamic>;
    final cat = c['category'] as Map<String, dynamic>?;
    final updated = DateTime.tryParse(c['updatedAt'] as String? ?? '');
    final pct = progress?['progressPct'] as int? ?? 0;
    final resume = _resumeLesson(c, progress);

    return CustomScrollView(slivers: [
      SliverAppBar(
        pinned: true,
        expandedHeight: 230,
        backgroundColor: Brand.tealDeep,
        foregroundColor: Colors.white,
        flexibleSpace: FlexibleSpaceBar(
          background: Stack(fit: StackFit.expand, children: [
            CourseThumb(c, radius: 0, showTitle: false),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66000000), Color(0x22000000), Color(0xCC000000)]),
              ),
            ),
            if (preview != null || (enrolled && resume != null))
              Center(
                child: InkWell(
                  borderRadius: BorderRadius.circular(40),
                  onTap: () => context.push('/lessons/${(enrolled ? resume : preview)!['id']}'),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.play_arrow_rounded, size: 40, color: Brand.teal),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      enrolled ? t('Resume', 'চালিয়ে যান') : t('Preview this course', 'কোর্সের প্রিভিউ দেখুন'),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ]),
                ),
              ),
          ]),
        ),
      ),
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        sliver: SliverList.list(children: [
          if (cat != null)
            Align(
              alignment: Alignment.centerLeft,
              child: InkWell(
                onTap: () => context.go('/search?category=${cat['slug']}'),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(categoryIcon(cat['icon'] as String?), size: 16, color: hexColor(cat['color'] as String?)),
                  const SizedBox(width: 6),
                  Text(cat['name'] as String, style: TextStyle(color: hexColor(cat['color'] as String?), fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          const SizedBox(height: 8),
          Text(c['title'] as String, style: text.headlineSmall?.copyWith(height: 1.2)),
          if (c['subtitle'] != null) ...[
            const SizedBox(height: 8),
            Text(c['subtitle'] as String, style: text.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            ...courseTags(c),
            if ((c['ratingCount'] as int) > 0) Stars(rating, count: c['ratingCount'] as int),
            Text(t(c['_count']['enrollments'] == 1 ? '1 student' : '${compact(c['_count']['enrollments'] as int)} students', '${compact(c['_count']['enrollments'] as int)} শিক্ষার্থী'),
                style: text.bodySmall),
          ]),
          const SizedBox(height: 10),
          InkWell(
            onTap: () => context.push('/teachers/${teacher['id']}'),
            child: Text.rich(TextSpan(children: [
              TextSpan(text: t('Created by ', 'তৈরি করেছেন ')),
              TextSpan(text: teacher['name'] as String, style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
            ])),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 16, runSpacing: 6, children: [
            if (updated != null) _Meta(Icons.update_rounded, t('Updated ${DateFormat.yMMM().format(updated)}', 'আপডেট ${DateFormat.yMMM().format(updated)}')),
            _Meta(Icons.language_rounded, languageLabel(c['language'] as String?)),
            _Meta(Icons.signal_cellular_alt_rounded, levelLabel(c['level'] as String?)),
          ]),
          const SizedBox(height: 18),
          if (_locked(c))
            Panel(
              child: Row(children: [
                const IconBadge(Icons.workspace_premium_rounded, color: Brand.orangeStrong),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(t('This is a premium course. It can\'t be bought in the app; if it\'s in your account, you can learn it here.',
                      'এটি একটি প্রিমিয়াম কোর্স। অ্যাপ থেকে কেনা যায় না; আপনার অ্যাকাউন্টে থাকলে এখানেই শিখতে পারবেন।')),
                ),
              ]),
            )
          else if (enrolled)
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('Your progress', 'আপনার অগ্রগতি'), style: text.titleSmall),
                const SizedBox(height: 8),
                ProgressLine(pct),
                if (resume != null) ...[
                  const SizedBox(height: 10),
                  Text(t('Next: ${resume['title']}', 'পরের লেসন: ${resume['title']}'), style: text.bodySmall),
                ],
                const SizedBox(height: 8),
                TextButton.icon(onPressed: _rate, icon: const Icon(Icons.star_outline_rounded), label: Text(t('Rate this course', 'কোর্সটি রেট করুন'))),
              ]),
            )
          else
            Row(children: [
              PriceTag(c, size: 26),
              const SizedBox(width: 10),
              if (discountPct(c) != null)
                Tag(t('${discountPct(c)}% off', '${discountPct(c)}% ছাড়'), color: const Color(0xFFFFE3D2), textColor: const Color(0xFF8A3A10)),
            ]),
          if (outcomes.isNotEmpty) ...[
            const SizedBox(height: 20),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t('What you\'ll learn', 'যা শিখবেন'), style: text.titleLarge),
                const SizedBox(height: 12),
                for (final o in outcomes) _Bullet(o, icon: Icons.check_rounded, color: Brand.success),
              ]),
            ),
          ],
          const SizedBox(height: 20),
          Text(t('This course includes', 'এই কোর্সে যা আছে'), style: text.titleLarge),
          const SizedBox(height: 10),
          _Include(Icons.ondemand_video_rounded, t('${hours(c['totalSec'] as int? ?? 0)} of on-demand video', '${hours(c['totalSec'] as int? ?? 0)} ভিডিও')),
          _Include(Icons.play_lesson_outlined, t(plural(c['lessonCount'] ?? lessons.length, 'lesson'), '${c['lessonCount'] ?? lessons.length}টি লেসন')),
          _Include(Icons.phone_iphone_rounded, t('Learn on your phone, anytime', 'যেকোনো সময় ফোনে শিখুন')),
          _Include(Icons.all_inclusive_rounded, t('Full lifetime access', 'আজীবন অ্যাক্সেস')),
          _Include(Icons.support_agent_rounded, t('Book 1:1 help from the instructor', 'ইন্সট্রাক্টরের সাথে ১:১ সেশন বুক করা যাবে')),
          const SizedBox(height: 20),
          _Curriculum(course: c, done: completedIds(progress), enrolled: enrolled),
          if (requirements.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(t('Requirements', 'যা লাগবে'), style: text.titleLarge),
            const SizedBox(height: 8),
            for (final r in requirements) _Bullet(r),
          ],
          const SizedBox(height: 20),
          Text(t('Description', 'বিবরণ'), style: text.titleLarge),
          const SizedBox(height: 8),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: _fullDescription ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: Text(c['description'] as String, maxLines: 5, overflow: TextOverflow.fade),
            secondChild: Text(c['description'] as String),
          ),
          TextButton(
            onPressed: () => setState(() => _fullDescription = !_fullDescription),
            child: Text(_fullDescription ? t('Show less', 'কম দেখান') : t('Show more', 'আরও দেখুন')),
          ),
          if (audience.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(t('Who this course is for', 'কোর্সটি কাদের জন্য'), style: text.titleLarge),
            const SizedBox(height: 8),
            for (final a in audience) _Bullet(a),
          ],
          const SizedBox(height: 20),
          _InstructorCard(c),
          const SizedBox(height: 20),
          _Reviews(courseId: id, rating: rating, count: c['ratingCount'] as int),
        ]),
      ),
    ]);
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ]);
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text, {this.icon = Icons.circle, this.color});
  final String text;
  final IconData icon;
  final Color? color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: EdgeInsets.only(top: icon == Icons.circle ? 8 : 2, right: 10),
            child: Icon(icon, size: icon == Icons.circle ? 6 : 18, color: color ?? Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Expanded(child: Text(text)),
        ]),
      );
}

class _Include extends StatelessWidget {
  const _Include(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
        ]),
      );
}

class _Curriculum extends StatelessWidget {
  const _Curriculum({required this.course, required this.done, required this.enrolled});
  final Map<String, dynamic> course;
  final Set<String> done;
  final bool enrolled;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final sections = course['sections'] as List;
    final lessonCount = sections.fold<int>(0, (n, s) => n + (s['lessons'] as List).length);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('Course content', 'কোর্স কন্টেন্ট'), style: text.titleLarge),
      const SizedBox(height: 4),
      Text(
        t('${plural(sections.length, 'section')} · ${plural(lessonCount, 'lesson')} · ${duration(course['totalSec'] as int? ?? 0)} total',
            '${sections.length}টি সেকশন · $lessonCountটি লেসন · মোট ${duration(course['totalSec'] as int? ?? 0)}'),
        style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      const SizedBox(height: 10),
      Card(
        child: Column(children: [
          for (var i = 0; i < sections.length; i++) ...[
            if (i > 0) const Divider(),
            Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: i == 0,
                backgroundColor: scheme.surfaceContainerLow,
                title: Text(sections[i]['title'] as String, style: text.titleSmall),
                subtitle: Text(
                  t('${plural((sections[i]['lessons'] as List).length, 'lesson')} · ${duration((sections[i]['lessons'] as List).fold<int>(0, (n, l) => n + (l['durationSec'] as int)))}',
                      '${(sections[i]['lessons'] as List).length}টি লেসন · ${duration((sections[i]['lessons'] as List).fold<int>(0, (n, l) => n + (l['durationSec'] as int)))}'),
                  style: text.bodySmall,
                ),
                children: [
                  for (final l in sections[i]['lessons'] as List)
                    ListTile(
                      dense: true,
                      leading: Icon(
                        done.contains(l['id'])
                            ? Icons.check_circle_rounded
                            : enrolled || l['isPreview'] == true
                                ? Icons.play_circle_outline_rounded
                                : Icons.lock_outline_rounded,
                        color: done.contains(l['id']) ? Brand.success : scheme.onSurfaceVariant,
                      ),
                      title: Text(l['title'] as String, style: text.bodyMedium),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        if (l['isPreview'] == true && !enrolled)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(t('Preview', 'প্রিভিউ'), style: TextStyle(color: scheme.primary, fontWeight: FontWeight.w700, fontSize: 12)),
                          ),
                        Text(duration(l['durationSec'] as int), style: text.bodySmall),
                      ]),
                      onTap: enrolled || l['isPreview'] == true ? () => context.push('/lessons/${l['id']}') : null,
                    ),
                ],
              ),
            ),
          ],
        ]),
      ),
    ]);
  }
}

class _InstructorCard extends StatelessWidget {
  const _InstructorCard(this.course);
  final Map<String, dynamic> course;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final teacher = course['teacher'] as Map<String, dynamic>;
    final profile = teacher['teacherProfile'] as Map<String, dynamic>?;
    final stats = course['teacherStats'] as Map<String, dynamic>?;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('Instructor', 'ইন্সট্রাক্টর'), style: text.titleLarge),
      const SizedBox(height: 10),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Avatar(teacher['name'] as String, url: teacher['avatarUrl'] as String?, radius: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(teacher['name'] as String, style: text.titleMedium),
                if (profile?['headline'] != null) Text(profile!['headline'] as String, style: text.bodySmall),
              ]),
            ),
          ]),
          if (stats != null) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 16, children: [
              _Meta(Icons.groups_2_outlined, t(plural(stats['students'], 'student'), '${stats['students']} শিক্ষার্থী')),
              _Meta(Icons.play_circle_outline_rounded, t(plural(stats['courses'], 'course'), '${stats['courses']} কোর্স')),
            ]),
          ],
          if ((profile?['bio'] as String?)?.isNotEmpty ?? false) ...[
            const SizedBox(height: 10),
            Text(profile!['bio'] as String, maxLines: 4, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(onPressed: () => context.push('/teachers/${teacher['id']}'), child: Text(t('View profile', 'প্রোফাইল দেখুন'))),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => context.push(Uri(path: '/teachers/${teacher['id']}/book', queryParameters: {'name': teacher['name'] as String}).toString()),
                child: Text(t('Book 1:1', '১:১ বুক করুন')),
              ),
            ),
          ]),
        ]),
      ),
    ]);
  }
}

class _Reviews extends ConsumerWidget {
  const _Reviews({required this.courseId, required this.rating, required this.count});
  final String courseId;
  final double rating;
  final int count;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final reviews = ref.watch(courseReviewsProvider(courseId)).value ?? const [];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(t('Student reviews', 'শিক্ষার্থীদের রিভিউ'), style: text.titleLarge),
      const SizedBox(height: 10),
      if (count == 0)
        Text(t('No reviews yet. Be the first after you enroll!', 'এখনো কোনো রিভিউ নেই। এনরোল করে প্রথম রিভিউ দিন!'))
      else ...[
        Row(children: [
          Text(rating.toStringAsFixed(1), style: text.displaySmall?.copyWith(color: const Color(0xFFB4690E))),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Stars(rating, showNumber: false, size: 18),
            Text(t('Course rating · $count ratings', 'কোর্স রেটিং · $countটি রেটিং'), style: text.bodySmall),
          ]),
        ]),
        const SizedBox(height: 12),
        for (final r in reviews.take(8))
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Panel(
              padding: const EdgeInsets.all(14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Avatar(r['user']['name'] as String, url: r['user']['avatarUrl'] as String?, radius: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(r['user']['name'] as String, style: text.titleSmall),
                      Row(children: [
                        Stars((r['rating'] as int).toDouble(), showNumber: false, size: 12),
                        const SizedBox(width: 6),
                        Text(DateFormat.yMMMd().format(DateTime.parse(r['createdAt'] as String)), style: text.bodySmall),
                      ]),
                    ]),
                  ),
                ]),
                if ((r['comment'] as String?)?.isNotEmpty ?? false) ...[const SizedBox(height: 8), Text(r['comment'] as String)],
              ]),
            ),
          ),
      ],
    ]);
  }
}

/// Bottom sheet asking for 1–5 stars and an optional comment.
Future<(int, String)?> askReview(BuildContext context) {
  var stars = 5;
  final comment = TextEditingController();
  return showModalBottomSheet<(int, String)>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, set) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(t('How is this course?', 'কোর্সটি কেমন লাগছে?'), style: Theme.of(ctx).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                iconSize: 40,
                onPressed: () => set(() => stars = i),
                icon: Icon(i <= stars ? Icons.star_rounded : Icons.star_outline_rounded, color: Brand.amber),
              ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: comment,
            maxLines: 3,
            decoration: InputDecoration(hintText: t('Tell others what you liked (optional)', 'কী ভালো লাগল লিখুন (ঐচ্ছিক)')),
          ),
          const SizedBox(height: 16),
          CtaButton(label: t('Submit review', 'রিভিউ দিন'), onPressed: () => Navigator.pop(ctx, (stars, comment.text.trim()))),
        ]),
      ),
    ),
  );
}

// ---------------------------------------------------------------------------
// Lesson player
// ---------------------------------------------------------------------------

final lessonProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.read(apiProvider).get('/lessons/$id'));

bool _isYoutube(String url) => url.contains('youtube.com') || url.contains('youtu.be') || url.contains('vimeo.com');

class LessonScreen extends ConsumerStatefulWidget {
  const LessonScreen(this.id, {super.key});
  final String id;
  @override
  ConsumerState<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends ConsumerState<LessonScreen> {
  bool _marking = false;

  void _report(String lessonId, String courseId, int sec, bool done) {
    if (!ref.read(authProvider).loggedIn) return;
    ref.read(apiProvider).post('/lessons/$lessonId/progress', {'watchedSec': sec, if (done) 'completed': true}).then((_) {
      if (done) {
        ref.invalidate(courseProgressProvider(courseId));
        ref.invalidate(myEnrollmentsProvider);
      }
    }).ignore();
  }

  Future<void> _markDone(Map<String, dynamic> l, List<Map<String, dynamic>> lessons) async {
    setState(() => _marking = true);
    try {
      await ref.read(apiProvider).post('/lessons/${l['id']}/progress', {'watchedSec': l['durationSec'], 'completed': true});
      ref.invalidate(courseProgressProvider(l['courseId'] as String));
      ref.invalidate(myEnrollmentsProvider);
      final i = lessons.indexWhere((x) => x['id'] == l['id']);
      if (!mounted) return;
      if (i >= 0 && i < lessons.length - 1) {
        context.pushReplacement('/lessons/${lessons[i + 1]['id']}');
      } else {
        showMessage(context, t('🎉 You finished the course! Great job.', '🎉 কোর্স শেষ করেছেন! দারুণ!'));
      }
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _marking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lesson = ref.watch(lessonProvider(widget.id));
    final courseId = lesson.value?['courseId'] as String?;
    final course = courseId == null ? null : ref.watch(courseProvider(courseId)).value;
    final progress = courseId == null ? null : ref.watch(courseProgressProvider(courseId)).value;
    final lessons = course == null ? <Map<String, dynamic>>[] : allLessons(course);
    final done = completedIds(progress);
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final enrolled = course?['enrolled'] == true;

    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: Brand.tealDeep,
        foregroundColor: Colors.white,
        title: Text(course?['title'] as String? ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16, color: Colors.white)),
      ),
      body: AsyncView(
        value: lesson,
        onRetry: () => ref.invalidate(lessonProvider(widget.id)),
        data: (l) {
          final i = lessons.indexWhere((x) => x['id'] == l['id']);
          final prev = i > 0 ? lessons[i - 1] : null;
          final next = i >= 0 && i < lessons.length - 1 ? lessons[i + 1] : null;
          bool canOpen(Map<String, dynamic> x) => enrolled || x['isPreview'] == true;
          final url = l['mediaUrl'] as String?;
          return ListView(padding: EdgeInsets.zero, children: [
            if (url != null && l['type'] == 'VIDEO' && !_isYoutube(url))
              LessonPlayer(
                key: ValueKey(l['id']),
                url: url,
                onProgress: (sec, isDone) => _report(l['id'] as String, l['courseId'] as String, sec, isDone),
              )
            else if (url != null)
              Container(
                color: Colors.black,
                height: 210,
                alignment: Alignment.center,
                child: FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(t('Open video', 'ভিডিও খুলুন')),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (i >= 0)
                  Text(
                    t('Lesson ${i + 1} of ${lessons.length} · ${lessons[i]['sectionTitle']}', 'লেসন ${i + 1}/${lessons.length} · ${lessons[i]['sectionTitle']}'),
                    style: text.labelMedium?.copyWith(color: scheme.primary),
                  ),
                const SizedBox(height: 4),
                Text(l['title'] as String, style: text.titleLarge),
                const SizedBox(height: 4),
                Text(duration(l['durationSec'] as int), style: text.bodySmall),
                if (l['content'] != null && (l['content'] as String).isNotEmpty) ...[const SizedBox(height: 12), Text(l['content'] as String)],
                if (url == null && (l['content'] == null || (l['content'] as String).isEmpty))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(t('This lesson\'s content will be added soon.', 'এই লেসনের কনটেন্ট শীঘ্রই যোগ হবে।')),
                  ),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: prev != null && canOpen(prev) ? () => context.pushReplacement('/lessons/${prev['id']}') : null,
                      icon: const Icon(Icons.skip_previous_rounded),
                      label: Text(t('Previous', 'আগের')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: next != null && canOpen(next) ? () => context.pushReplacement('/lessons/${next['id']}') : null,
                      icon: const Icon(Icons.skip_next_rounded),
                      label: Text(t('Next', 'পরের')),
                    ),
                  ),
                ]),
                if (enrolled) ...[
                  const SizedBox(height: 10),
                  CtaButton(
                    busy: _marking,
                    icon: done.contains(l['id']) ? Icons.check_circle_rounded : Icons.check_rounded,
                    label: done.contains(l['id'])
                        ? (next == null ? t('Completed', 'সম্পন্ন') : t('Completed · Next lesson', 'সম্পন্ন · পরের লেসন'))
                        : t('Mark as complete', 'সম্পন্ন হিসেবে চিহ্নিত করুন'),
                    onPressed: () => _markDone(l, lessons),
                  ),
                ] else if (course != null) ...[
                  const SizedBox(height: 12),
                  Panel(
                    onTap: () => context.push('/courses/${course['id']}'),
                    child: Row(children: [
                      const IconBadge(Icons.lock_open_rounded, color: Brand.orangeStrong),
                      const SizedBox(width: 12),
                      Expanded(child: Text(t('Enjoying the preview? Enroll to unlock every lesson.', 'প্রিভিউ ভালো লাগছে? সব লেসন খুলতে এনরোল করুন।'))),
                      const Icon(Icons.chevron_right_rounded),
                    ]),
                  ),
                ],
                if (progress != null && enrolled) ...[
                  const SizedBox(height: 16),
                  ProgressLine(progress['progressPct'] as int? ?? 0),
                ],
                const SizedBox(height: 20),
                Text(t('Course content', 'কোর্স কন্টেন্ট'), style: text.titleMedium),
                const SizedBox(height: 4),
              ]),
            ),
            for (final (k, x) in lessons.indexed)
              ListTile(
                selected: x['id'] == l['id'],
                selectedTileColor: scheme.primaryContainer.withValues(alpha: 0.5),
                leading: done.contains(x['id'])
                    ? const Icon(Icons.check_circle_rounded, color: Brand.success)
                    : canOpen(x)
                        ? CircleAvatar(radius: 12, backgroundColor: scheme.surfaceContainerHighest, child: Text('${k + 1}', style: const TextStyle(fontSize: 11)))
                        : const Icon(Icons.lock_outline_rounded),
                title: Text(x['title'] as String, style: text.bodyMedium),
                subtitle: Text('${x['sectionTitle']} · ${duration(x['durationSec'] as int)}', style: text.bodySmall),
                onTap: canOpen(x) && x['id'] != l['id'] ? () => context.pushReplacement('/lessons/${x['id']}') : null,
              ),
            const SizedBox(height: 24),
          ]);
        },
      ),
    );
  }
}

/// Video player with tap-to-show controls, seek bar, ±10s and playback speed.
class LessonPlayer extends StatefulWidget {
  const LessonPlayer({super.key, required this.url, required this.onProgress});
  final String url;
  final void Function(int seconds, bool done) onProgress;
  @override
  State<LessonPlayer> createState() => _LessonPlayerState();
}

class _LessonPlayerState extends State<LessonPlayer> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  int _lastReported = 0;
  bool _controls = true;
  bool _failed = false;
  Timer? _hide;
  static const _speeds = [0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) {
      if (mounted) setState(() {});
      _c.play();
      _scheduleHide();
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
    _c.addListener(_tick);
  }

  /// Reports progress every 15 seconds of playback and once at the end.
  void _tick() {
    final pos = _c.value.position.inSeconds;
    final done = _c.value.duration.inSeconds > 0 && pos >= _c.value.duration.inSeconds - 1;
    if (pos - _lastReported >= 15 || (done && _lastReported != pos)) {
      _lastReported = pos;
      widget.onProgress(pos, done);
    }
    if (mounted) setState(() {});
  }

  void _scheduleHide() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted && _c.value.isPlaying) setState(() => _controls = false);
    });
  }

  void _seek(int sec) {
    final to = _c.value.position + Duration(seconds: sec);
    _c.seekTo(to < Duration.zero ? Duration.zero : to);
    _scheduleHide();
  }

  String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _hide?.cancel();
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v = _c.value;
    return AspectRatio(
      aspectRatio: v.isInitialized ? v.aspectRatio : 16 / 9,
      child: ColoredBox(
        color: Colors.black,
        child: _failed
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(t('This video can\'t play here.', 'ভিডিওটি এখানে চলছে না।'), style: const TextStyle(color: Colors.white)),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    onPressed: () => launchUrl(Uri.parse(widget.url), mode: LaunchMode.externalApplication),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(t('Open in browser', 'ব্রাউজারে খুলুন')),
                  ),
                ]),
              )
            : !v.isInitialized
                ? const Center(child: CircularProgressIndicator(color: Brand.cyan))
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() => _controls = !_controls);
                      _scheduleHide();
                    },
                    child: Stack(fit: StackFit.expand, children: [
                      VideoPlayer(_c),
                      AnimatedOpacity(
                        opacity: _controls ? 1 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: IgnorePointer(
                          ignoring: !_controls,
                          child: Container(
                            color: Colors.black38,
                            child: Stack(children: [
                              Center(
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  IconButton(iconSize: 34, color: Colors.white, onPressed: () => _seek(-10), icon: const Icon(Icons.replay_10_rounded)),
                                  const SizedBox(width: 18),
                                  IconButton(
                                    iconSize: 56,
                                    color: Colors.white,
                                    onPressed: () {
                                      v.isPlaying ? _c.pause() : _c.play();
                                      _scheduleHide();
                                    },
                                    icon: Icon(v.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded),
                                  ),
                                  const SizedBox(width: 18),
                                  IconButton(iconSize: 34, color: Colors.white, onPressed: () => _seek(10), icon: const Icon(Icons.forward_10_rounded)),
                                ]),
                              ),
                              Positioned(
                                left: 12,
                                right: 4,
                                bottom: 4,
                                child: Row(children: [
                                  Text('${_fmt(v.position)} / ${_fmt(v.duration)}', style: const TextStyle(color: Colors.white, fontSize: 12)),
                                  const Spacer(),
                                  PopupMenuButton<double>(
                                    tooltip: t('Speed', 'গতি'),
                                    initialValue: v.playbackSpeed,
                                    onSelected: _c.setPlaybackSpeed,
                                    itemBuilder: (_) => [for (final s in _speeds) PopupMenuItem(value: s, child: Text('${s}x'))],
                                    child: Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Text('${v.playbackSpeed}x', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                                    ),
                                  ),
                                ]),
                              ),
                            ]),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: VideoProgressIndicator(
                          _c,
                          allowScrubbing: true,
                          padding: const EdgeInsets.only(top: 6),
                          colors: const VideoProgressColors(playedColor: Brand.orange, bufferedColor: Colors.white38, backgroundColor: Colors.white12),
                        ),
                      ),
                    ]),
                  ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Instructor profile
// ---------------------------------------------------------------------------

final teacherProfileProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.read(apiProvider).get('/teachers/$id'));

class TeacherProfileScreen extends ConsumerWidget {
  const TeacherProfileScreen(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(teacherProfileProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(t('Instructor', 'ইন্সট্রাক্টর'))),
      body: AsyncView(
        value: profile,
        onRetry: () => ref.invalidate(teacherProfileProvider(id)),
        data: (p) {
          final user = p['user'] as Map<String, dynamic>;
          final stats = p['stats'] as Map<String, dynamic>?;
          final text = Theme.of(context).textTheme;
          final courses = user['courses'] as List;
          return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                Avatar(user['name'] as String, url: user['avatarUrl'] as String?, radius: 40),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Flexible(child: Text(user['name'] as String, style: text.headlineSmall)),
                      if (p['verified'] == true) const Padding(padding: EdgeInsets.only(left: 6), child: BlueTick(size: 22)),
                    ]),
                    Text(p['headline'] as String, style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    if (p['tier'] != null && p['tier'] != 'NEW') Padding(padding: const EdgeInsets.only(top: 6), child: TierBadge(p['tier'] as String)),
                  ]),
                ),
              ]),
            ),
            if (stats != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(child: _StatBox('${stats['students']}', t('Students', 'শিক্ষার্থী'))),
                  const SizedBox(width: 10),
                  Expanded(child: _StatBox('${stats['courses']}', t('Courses', 'কোর্স'))),
                ]),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: CtaButton(
                icon: Icons.event_available_rounded,
                label: p['hourlyRatePaisa'] == null
                    ? t('Book a 1:1 session', '১:১ সেশন বুক করুন')
                    : t('Book a 1:1 session · ${taka(p['hourlyRatePaisa'] as int)}/hour', '১:১ সেশন বুক করুন · ঘণ্টা ${taka(p['hourlyRatePaisa'] as int)}'),
                onPressed: () => context.push(Uri(path: '/teachers/$id/book', queryParameters: {'name': user['name'] as String}).toString()),
              ),
            ),
            if ([...?(p['expertise'] as List?), ...(p['skills'] as List)].isNotEmpty) ...[
              SectionHeader(t('Expertise', 'দক্ষতা'), padding: const EdgeInsets.fromLTRB(16, 4, 16, 8)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in {...?(p['expertise'] as List?), ...(p['skills'] as List)}) Chip(label: Text(s as String)),
                ]),
              ),
            ],
            if ((p['experience'] as String? ?? '').isNotEmpty) ...[
              SectionHeader(t('Experience', 'অভিজ্ঞতা'), padding: const EdgeInsets.fromLTRB(16, 20, 16, 8)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(p['experience'] as String)),
            ],
            if ((p['bio'] as String).isNotEmpty) ...[
              SectionHeader(t('About me', 'আমার সম্পর্কে'), padding: const EdgeInsets.fromLTRB(16, 20, 16, 8)),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(p['bio'] as String)),
            ],
            if ((user['portfolioItems'] as List).isNotEmpty) ...[
              SectionHeader(t('Portfolio', 'পোর্টফোলিও'), padding: const EdgeInsets.fromLTRB(16, 20, 16, 8)),
              for (final item in user['portfolioItems'] as List)
                ListTile(
                  leading: const IconBadge(Icons.link_rounded, size: 36),
                  title: Text(item['title'] as String),
                  subtitle: Text(item['url'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => launchUrl(Uri.parse(item['url'] as String), mode: LaunchMode.externalApplication),
                ),
            ],
            if (courses.isNotEmpty) ...[
              SectionHeader(t('Courses (${courses.length})', 'কোর্স (${courses.length})'), padding: const EdgeInsets.fromLTRB(16, 20, 16, 4)),
              for (final c in courses) CourseTile(c as Map<String, dynamic>),
            ],
          ]);
        },
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox(this.value, this.label);
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}
