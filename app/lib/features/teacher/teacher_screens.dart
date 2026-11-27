import 'dart:async';

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/i18n.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/api.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'package:video_player/video_player.dart';
import '../home/home_screen.dart';
import 'instructor_screens.dart';

Map<String, String> get _statusText => {
  'PENDING': t('In review', 'রিভিউতে আছে'),
  'CHANGES_REQUESTED': t('Changes needed', 'সংশোধন দরকার'),
  'APPROVED': t('Approved', 'অনুমোদিত'),
  'REJECTED': t('Not approved', 'অনুমোদিত হয়নি'),
  'DRAFT': t('Draft', 'ড্রাফট'),
  'IN_REVIEW': t('In review', 'রিভিউতে আছে'),
  'PUBLISHED': t('Live', 'লাইভ'),
};

final myApplicationProvider = FutureProvider.autoDispose<Map<String, dynamic>?>(
    (ref) => ref.read(apiProvider).get('/teacher-applications/mine'));

/// Portfolio + application form. Shows the current status and admin note when one exists.
class TeacherApplyScreen extends ConsumerStatefulWidget {
  const TeacherApplyScreen({super.key});
  @override
  ConsumerState<TeacherApplyScreen> createState() => _TeacherApplyScreenState();
}

class _TeacherApplyScreenState extends ConsumerState<TeacherApplyScreen> {
  final _form = GlobalKey<FormState>();
  final _headline = TextEditingController();
  final _bio = TextEditingController();
  final _skills = TextEditingController();
  final _experience = TextEditingController();
  final _demo = TextEditingController();
  final _links = <(TextEditingController, TextEditingController)>[(TextEditingController(), TextEditingController())];
  bool _busy = false;
  bool _prefilled = false;
  bool _accepted = false;

  void _prefill(Map<String, dynamic>? app) {
    if (_prefilled || app == null) return;
    _prefilled = true;
    _headline.text = app['headline'] as String;
    _bio.text = app['bio'] as String;
    _skills.text = (app['skills'] as List).join(', ');
    _experience.text = app['experience'] as String;
    _demo.text = app['demoVideoUrl'] as String? ?? '';
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    if (!_accepted) {
      showMessage(context, t('Please read and accept the instructor rules first.', 'আগে ইনস্ট্রাক্টরের নিয়মগুলো পড়ে সম্মতি দিন।'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/teacher-applications', {
        'acceptRules': true,
        'headline': _headline.text.trim(),
        'bio': _bio.text.trim(),
        'skills': _skills.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        'experience': _experience.text.trim(),
        if (_demo.text.trim().isNotEmpty) 'demoVideoUrl': _demo.text.trim(),
        'portfolio': [
          for (final (title, url) in _links)
            if (url.text.trim().isNotEmpty) {'type': 'LINK', 'title': title.text.trim().isEmpty ? 'Portfolio' : title.text.trim(), 'url': url.text.trim()},
        ],
      });
      ref.invalidate(myApplicationProvider);
      if (mounted) showSuccess(context, t('Application submitted. The admin will review it and let you know.', 'আবেদন জমা হয়েছে। অ্যাডমিন রিভিউ করে জানাবেন।'));
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(myApplicationProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Apply to teach', 'টিচার হিসেবে আবেদন'))),
      body: AsyncView(
        value: app,
        data: (a) {
          _prefill(a);
          final status = a?['status'] as String?;
          if (status == 'PENDING') {
            return EmptyState(t('Your application is in review. You\'ll get a notification when it\'s approved.', 'আপনার আবেদন রিভিউতে আছে। অনুমোদন হলে নোটিফিকেশন পাবেন।'), icon: Icons.hourglass_top);
          }
          return Form(
            key: _form,
            child: ListView(padding: const EdgeInsets.all(16), children: [
              if (status != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.info_outline),
                    title: Text(_statusText[status] ?? status),
                    subtitle: a?['adminNote'] != null ? Text(a!['adminNote'] as String) : null,
                  ),
                ),
              const SizedBox(height: 16),
              Text(t('Teach your skills and earn. Build a portfolio and submit it; the admin will review it.', 'আপনার স্কিল দিয়ে শেখান এবং আয় করুন। একটি পোর্টফোলিও বানিয়ে জমা দিন, অ্যাডমিন রিভিউ করবেন।')),
              const SizedBox(height: 16),
              TextFormField(controller: _headline, decoration: InputDecoration(labelText: t('Headline (e.g. Flutter developer, 5 years)', 'শিরোনাম (যেমন: ৫ বছরের Flutter ডেভেলপার)')),
                  validator: (v) => (v ?? '').trim().length < 5 ? t('At least 5 characters', 'কমপক্ষে ৫ অক্ষর') : null),
              const SizedBox(height: 12),
              TextFormField(controller: _bio, maxLines: 4, decoration: InputDecoration(labelText: t('About you', 'নিজের সম্পর্কে')),
                  validator: (v) => (v ?? '').trim().length < 30 ? t('Write at least 30 characters', 'কমপক্ষে ৩০ অক্ষর লিখুন') : null),
              const SizedBox(height: 12),
              TextFormField(controller: _skills, decoration: InputDecoration(labelText: t('Skills (separate with commas)', 'স্কিল (কমা দিয়ে আলাদা করুন)')),
                  validator: (v) => (v ?? '').trim().isEmpty ? t('At least one skill', 'অন্তত একটি স্কিল') : null),
              const SizedBox(height: 12),
              TextFormField(controller: _experience, maxLines: 3, decoration: InputDecoration(labelText: t('Experience', 'অভিজ্ঞতা')),
                  validator: (v) => (v ?? '').trim().length < 10 ? t('Describe your experience', 'অভিজ্ঞতা লিখুন') : null),
              const SizedBox(height: 12),
              TextFormField(controller: _demo, decoration: InputDecoration(labelText: t('Demo video link (optional)', 'ডেমো ভিডিও লিংক (ঐচ্ছিক)'))),
              const SizedBox(height: 24),
              Text(t('Portfolio links', 'পোর্টফোলিও লিংক'), style: Theme.of(context).textTheme.titleMedium),
              for (final (i, (title, url)) in _links.indexed) ...[
                const SizedBox(height: 12),
                TextFormField(controller: title, decoration: InputDecoration(labelText: t('Name of link ${i + 1}', 'লিংক ${i + 1} এর নাম'))),
                const SizedBox(height: 8),
                TextFormField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'https://...'),
                    validator: (v) => i == 0 && (v ?? '').trim().isEmpty ? t('Add at least one link', 'অন্তত একটি লিংক দিন') : null),
              ],
              TextButton.icon(
                onPressed: () => setState(() => _links.add((TextEditingController(), TextEditingController()))),
                icon: const Icon(Icons.add),
                label: Text(t('Add another link', 'আরেকটি লিংক')),
              ),
              const SizedBox(height: 16),
              InstructorRulesCard(accepted: _accepted, onChanged: (v) => setState(() => _accepted = v)),
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy || !_accepted ? null : _submit, child: Text(t('Accept rules and submit', 'নিয়ম মেনে আবেদন জমা দিন'))),
            ]),
          );
        },
      ),
    );
  }
}

final myCoursesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/teacher/courses'));

class TeacherDashboard extends ConsumerWidget {
  const TeacherDashboard({super.key, this.customTitle});
  final String? customTitle;
  String get title => customTitle ?? t('Teacher dashboard', 'টিচার ড্যাশবোর্ড');

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final c = await Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => const CourseDetailsForm()));
    if (c == null) return;
    ref.invalidate(myCoursesProvider);
    if (context.mounted) context.push('/teacher/courses/${c['id']}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(myCoursesProvider);
    final me = ref.watch(authProvider).me;
    final isTeacher = (me?.isTeacher ?? false) && customTitle == null;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(title), actions: [if (customTitle == null) const Padding(padding: EdgeInsets.only(right: 12), child: LangToggle())]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(t('New course', 'নতুন কোর্স')),
      ),
      body: AsyncView(
        value: courses,
        onRetry: () => ref.invalidate(myCoursesProvider),
        data: (list) {
          final students = list.fold<int>(0, (n, c) => n + (c['_count']['enrollments'] as int));
          final live = list.where((c) => c['status'] == 'PUBLISHED').length;
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
            Row(children: [
              Expanded(child: _MiniStat(Icons.video_library_outlined, '${list.length}', t('Courses', 'কোর্স'))),
              const SizedBox(width: 10),
              Expanded(child: _MiniStat(Icons.public_rounded, '$live', t('Live', 'লাইভ'))),
              const SizedBox(width: 10),
              Expanded(child: _MiniStat(Icons.groups_2_outlined, '$students', t('Students', 'শিক্ষার্থী'))),
            ]),
            if (isTeacher) ...[
              const SizedBox(height: 12),
              const InstructorStatusCards(),
              const BookingRequestsCard(),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: Panel(
                    onTap: () => context.push('/teacher/sessions'),
                    child: Row(children: [
                      const IconBadge(Icons.event_note_outlined, size: 36),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t('1:1 sessions', '১:১ সেশন'), style: text.titleSmall)),
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Panel(
                    onTap: () => context.push('/teacher/earnings'),
                    child: Row(children: [
                      const IconBadge(Icons.account_balance_wallet_outlined, size: 36, color: Brand.orangeStrong),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t('Earnings', 'আয়'), style: text.titleSmall)),
                    ]),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Row(children: [
                Expanded(
                  child: Panel(
                    onTap: () => context.push('/teacher/profile'),
                    child: Row(children: [
                      const IconBadge(Icons.badge_outlined, size: 36),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t('Bio & expertise', 'বায়ো ও দক্ষতা'), style: text.titleSmall)),
                    ]),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Panel(
                    onTap: () => context.push('/teacher/availability'),
                    child: Row(children: [
                      const IconBadge(Icons.schedule_rounded, size: 36, color: Brand.orangeStrong),
                      const SizedBox(width: 10),
                      Expanded(child: Text(t('Schedule', 'সময়সূচি'), style: text.titleSmall)),
                    ]),
                  ),
                ),
              ]),
            ],
            SectionHeader(t('Your courses', 'আপনার কোর্স'), padding: const EdgeInsets.fromLTRB(0, 20, 0, 10)),
            if (list.isEmpty)
              Panel(
                child: Column(children: [
                  const IconBadge(Icons.video_call_outlined, size: 56),
                  const SizedBox(height: 10),
                  Text(t('Create your first course', 'প্রথম কোর্সটি তৈরি করুন'), style: text.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    t('Add sections, upload your recorded videos and publish. It only takes a few minutes to start.',
                        'সেকশন যোগ করুন, রেকর্ড করা ভিডিও আপলোড করুন আর পাবলিশ করুন। শুরু করতে কয়েক মিনিট লাগে।'),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            for (final c in list) ...[
              Card(
                child: InkWell(
                  onTap: () => context.push('/teacher/courses/${c['id']}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      SizedBox(width: 104, child: CourseThumb(c as Map<String, dynamic>, radius: 10, showTitle: false)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(c['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                          const SizedBox(height: 4),
                          Text(t('${plural(c['_count']['enrollments'], 'student')} · ${price(c)}', '${c['_count']['enrollments']} শিক্ষার্থী · ${price(c)}'), style: text.bodySmall),
                          const SizedBox(height: 6),
                          _StatusChip(c['status'] as String),
                        ]),
                      ),
                      const Icon(Icons.chevron_right_rounded),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
          ]);
        },
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;
  @override
  Widget build(BuildContext context) => Panel(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 6),
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ]),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) => switch (status) {
        'PUBLISHED' => Tag(_statusText[status]!, color: const Color(0xFFD7F5E6), textColor: const Color(0xFF13633F), icon: Icons.public_rounded),
        'IN_REVIEW' => Tag(_statusText[status]!, color: const Color(0xFFFFE9C7), textColor: const Color(0xFF7A4A00), icon: Icons.hourglass_top_rounded),
        'REJECTED' => Tag(t('Changes needed', 'সংশোধন দরকার'), color: const Color(0xFFFFDAD6), textColor: const Color(0xFF8C1D18), icon: Icons.edit_note_rounded),
        _ => Tag(_statusText[status] ?? status, icon: Icons.edit_outlined),
      };
}

final editCourseProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.read(apiProvider).get('/teacher/courses/$id'));

/// Upload progress per lesson id (0..1), so the tile can show a bar while a video uploads.
final uploadProgressProvider = NotifierProvider<UploadProgress, Map<String, double>>(UploadProgress.new);

class UploadProgress extends Notifier<Map<String, double>> {
  @override
  Map<String, double> build() => {};
  void set(String id, double? v) => state = {...state}..removeWhere((k, _) => k == id)..addAll({id: ?v});
}

/// Course builder: details, sections, lessons and recorded video uploads, then publish/submit.
class CourseEditorScreen extends ConsumerWidget {
  const CourseEditorScreen(this.id, {super.key});
  final String id;

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() fn, [String? done]) async {
    try {
      await fn();
      ref.invalidate(editCourseProvider(id));
      ref.invalidate(myCoursesProvider);
      if (done != null && context.mounted) showSuccess(context, done);
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  Future<Map<String, String>?> _lessonDialog(BuildContext context, {Map<String, dynamic>? lesson}) async {
    final title = TextEditingController(text: lesson?['title'] as String?);
    final minutes = TextEditingController(text: lesson == null ? '' : '${((lesson['durationSec'] as int) / 60).round()}');
    final link = TextEditingController(text: lesson?['videoLink'] as String?);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(lesson == null ? t('New lesson', 'নতুন লেসন') : t('Edit lesson', 'লেসন এডিট')),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, autofocus: true, decoration: InputDecoration(labelText: t('Lesson title', 'লেসনের নাম'))),
            const SizedBox(height: 12),
            TextField(
              controller: minutes,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: t('Length in minutes (filled in automatically after upload)', 'সময় মিনিটে (আপলোডের পর নিজে থেকেই বসবে)')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: link,
              decoration: InputDecoration(
                labelText: t('Or a video link (optional)', 'অথবা ভিডিও লিংক (ঐচ্ছিক)'),
                helperText: t('YouTube/Vimeo/MP4 link. Uploading a file is better.', 'YouTube/Vimeo/MP4 লিংক। ফাইল আপলোড করা ভালো।'),
                helperMaxLines: 2,
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel', 'বাতিল'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Save', 'সেভ'))),
        ],
      ),
    );
    if (ok != true || title.text.trim().isEmpty) return null;
    return {'title': title.text.trim(), 'minutes': minutes.text.trim(), 'link': link.text.trim()};
  }

  /// Picks a video file and uploads it with a progress bar; then reads its real length.
  Future<void> _uploadVideo(BuildContext context, WidgetRef ref, String lessonId) async {
    final file = await FilePicker.pickFile(type: FileType.video);
    if (file == null) return;
    final size = await file.length() ?? 0;
    final progress = ref.read(uploadProgressProvider.notifier);
    final api = ref.read(apiProvider);
    progress.set(lessonId, 0);
    try {
      final form = FormData.fromMap({'file': MultipartFile.fromStream(file.readAsByteStream, size, filename: file.name)});
      await api.dio.post(
        '/teacher/lessons/$lessonId/video',
        data: form,
        options: Options(sendTimeout: const Duration(hours: 2), receiveTimeout: const Duration(minutes: 10)),
        onSendProgress: (sent, total) => progress.set(lessonId, total > 0 ? sent / total : 0),
      );
      ref.invalidate(editCourseProvider(id));
      if (context.mounted) showSuccess(context, t('Video uploaded ✓', 'ভিডিও আপলোড হয়েছে ✓'));
      unawaited(_detectLength(ref, lessonId));
    } on DioException catch (e) {
      final err = ApiError.from(e);
      if (err.body?['code'] == 'STORAGE_LIMIT' && context.mounted) {
        final go = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            icon: const Icon(Icons.cloud_upload_outlined),
            title: Text(t('Storage is full', 'স্টোরেজ ভরে গেছে')),
            content: Text(t('Your plan\'s video limit is reached. Get a storage plan to upload more videos.', 'আপনার প্ল্যানের ভিডিও সীমা শেষ। আরও ভিডিও আপলোড করতে স্টোরেজ প্ল্যান নিন।')),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Later', 'পরে'))),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('See plans', 'প্ল্যান দেখুন'))),
            ],
          ),
        );
        if (go == true && context.mounted) unawaited(context.push('/teacher/storage'));
      } else if (context.mounted) {
        showMessage(context, err);
      }
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    } finally {
      progress.set(lessonId, null);
    }
  }

  /// Opens the uploaded video just long enough to read its duration and save it on the lesson.
  Future<void> _detectLength(WidgetRef ref, String lessonId) async {
    try {
      final api = ref.read(apiProvider);
      final l = await api.get<Map<String, dynamic>>('/lessons/$lessonId');
      final url = l['mediaUrl'] as String?;
      if (url == null) return;
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      await c.initialize().timeout(const Duration(seconds: 20));
      final sec = c.value.duration.inSeconds;
      await c.dispose();
      if (sec > 0) {
        await api.patch('/teacher/lessons/$lessonId', {'durationSec': sec});
        ref.invalidate(editCourseProvider(id));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(editCourseProvider(id));
    final uploads = ref.watch(uploadProgressProvider);
    final api = ref.read(apiProvider);
    final me = ref.watch(authProvider).me;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    // The admin's own courses publish directly, without review.
    final official = (me?.isAdmin ?? false) && course.value?['teacherId'] == me?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(course.value?['title'] as String? ?? t('Course', 'কোর্স'), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(tooltip: t('Preview as student', 'শিক্ষার্থী হিসেবে দেখুন'), onPressed: () => context.push('/courses/$id'), icon: const Icon(Icons.visibility_outlined)),
        ],
      ),
      body: AsyncView(
        value: course,
        onRetry: () => ref.invalidate(editCourseProvider(id)),
        data: (c) {
          final sections = c['sections'] as List;
          final lessons = sections.expand((s) => s['lessons'] as List).toList();
          final withVideo = lessons.where((l) => l['hasVideo'] == true).length;
          final checklist = [
            (t('Title, description and price', 'নাম, বিবরণ ও দাম'), true),
            (t('"What you\'ll learn" points', '"যা শিখবেন" পয়েন্ট'), (c['outcomes'] as List? ?? const []).isNotEmpty),
            (t('At least one lesson', 'অন্তত একটি লেসন'), lessons.isNotEmpty),
            (t('Videos for every lesson ($withVideo/${lessons.length})', 'সব লেসনে ভিডিও ($withVideo/${lessons.length})'), lessons.isNotEmpty && withVideo == lessons.length),
            (t('One free preview lesson', 'একটি ফ্রি প্রিভিউ লেসন'), lessons.any((l) => l['isPreview'] == true)),
          ];
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  _StatusChip(c['status'] as String),
                  const Spacer(),
                  // A teacher's live course updates in place; only drafts/rejected ones go to review.
                  if (c['status'] != 'IN_REVIEW' && (official || c['status'] != 'PUBLISHED'))
                    FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: scheme.secondary),
                      onPressed: () => _run(context, ref, () => api.post('/teacher/courses/$id/submit'),
                          official ? t('Course published', 'কোর্স পাবলিশ হয়েছে') : t('Submitted for review', 'রিভিউয়ের জন্য জমা হয়েছে')),
                      icon: const Icon(Icons.rocket_launch_rounded, size: 18),
                      label: Text(official
                          ? (c['status'] == 'PUBLISHED' ? t('Publish update', 'আপডেট পাবলিশ') : t('Publish', 'পাবলিশ করুন'))
                          : t('Send for review', 'রিভিউতে পাঠান')),
                    ),
                ]),
                if (c['adminNote'] != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: const Color(0xFFFFF4E5), borderRadius: BorderRadius.circular(10)),
                    child: Text(t('Admin note: ${c['adminNote']}', 'অ্যাডমিনের মন্তব্য: ${c['adminNote']}')),
                  ),
                ],
                const SizedBox(height: 12),
                Text(t('Before you publish', 'পাবলিশের আগে'), style: text.titleSmall),
                const SizedBox(height: 6),
                for (final (label, ok) in checklist)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(children: [
                      Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 18, color: ok ? Brand.success : scheme.outline),
                      const SizedBox(width: 8),
                      Expanded(child: Text(label, style: text.bodySmall)),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 12),
            Panel(
              onTap: () async {
                final saved = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => CourseDetailsForm(course: c)));
                if (saved != null) {
                  ref.invalidate(editCourseProvider(id));
                  ref.invalidate(myCoursesProvider);
                }
              },
              child: Row(children: [
                SizedBox(width: 96, child: CourseThumb(c, radius: 8, showTitle: false)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('Course details', 'কোর্সের তথ্য'), style: text.titleSmall),
                    Text(t('Title, image, price, what you\'ll learn…', 'নাম, ছবি, দাম, যা শিখবেন…'), style: text.bodySmall),
                    const SizedBox(height: 4),
                    Text(price(c), style: text.labelLarge),
                  ]),
                ),
                const Icon(Icons.edit_outlined),
              ]),
            ),
            SectionHeader(
              t('Curriculum', 'কারিকুলাম'),
              subtitle: t('${plural(sections.length, 'section')} · ${plural(lessons.length, 'lesson')}', '${sections.length}টি সেকশন · ${lessons.length}টি লেসন'),
              padding: const EdgeInsets.fromLTRB(0, 20, 0, 10),
            ),
            for (final s in sections) ...[
              Card(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Container(
                    color: scheme.surfaceContainerLow,
                    padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                    child: Row(children: [
                      Expanded(child: Text(s['title'] as String, style: text.titleSmall)),
                      PopupMenuButton<String>(
                        onSelected: (v) async {
                          if (v == 'rename') {
                            final name = await _askName(context, t('Section title', 'সেকশনের নাম'), s['title'] as String);
                            if (name == null || !context.mounted) return;
                            await _run(context, ref, () => api.patch('/teacher/sections/${s['id']}', {'title': name}));
                          } else {
                            final ok = await confirmAction(
                              context,
                              title: t('Delete "${s['title']}"?', '"${s['title']}" মুছবেন?'),
                              message: t('All lessons and videos in this section will be deleted too.', 'এই সেকশনের সব লেসন আর ভিডিও-ও মুছে যাবে।'),
                              confirm: t('Delete', 'মুছুন'),
                            );
                            if (!ok || !context.mounted) return;
                            await _run(context, ref, () => api.delete('/teacher/sections/${s['id']}'), t('Section deleted', 'সেকশন মুছে ফেলা হয়েছে'));
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'rename', child: Text(t('Rename', 'নাম বদলান'))),
                          PopupMenuItem(value: 'delete', child: Text(t('Delete section', 'সেকশন মুছুন'))),
                        ],
                      ),
                    ]),
                  ),
                  for (final l in s['lessons'] as List) ...[
                    ListTile(
                      leading: Icon(
                        l['hasVideo'] == true ? Icons.ondemand_video_rounded : Icons.videocam_off_outlined,
                        color: l['hasVideo'] == true ? Brand.success : scheme.outline,
                      ),
                      title: Text(l['title'] as String),
                      subtitle: Text([
                        duration(l['durationSec'] as int),
                        switch (l['videoSource']) {
                          'upload' => t('Video uploaded', 'ভিডিও আপলোড করা'),
                          'link' => t('Video link', 'ভিডিও লিংক'),
                          'cdn' => t('CDN video', 'CDN ভিডিও'),
                          _ => t('No video yet', 'এখনো ভিডিও নেই'),
                        },
                        if (l['isPreview'] == true) t('Free preview', 'ফ্রি প্রিভিউ'),
                      ].join(' · ')),
                      trailing: PopupMenuButton<String>(
                        onSelected: (v) async {
                          final lid = l['id'] as String;
                          switch (v) {
                            case 'upload':
                              await _uploadVideo(context, ref, lid);
                            case 'edit':
                              final r = await _lessonDialog(context, lesson: l as Map<String, dynamic>);
                              if (r == null || !context.mounted) return;
                              await _run(context, ref, () => api.patch('/teacher/lessons/$lid', {
                                    'title': r['title'],
                                    if (int.tryParse(r['minutes']!) != null) 'durationSec': int.parse(r['minutes']!) * 60,
                                    if (r['link']!.isNotEmpty) 'mediaKey': r['link'],
                                  }));
                            case 'preview':
                              await _run(context, ref, () => api.patch('/teacher/lessons/$lid', {'isPreview': l['isPreview'] != true}));
                            case 'removeVideo':
                              if (!await confirmAction(context, title: t('Remove this video?', 'ভিডিওটা সরাবেন?'), confirm: t('Remove', 'সরান')) || !context.mounted) return;
                              await _run(context, ref, () => api.delete('/teacher/lessons/$lid/video'), t('Video removed', 'ভিডিও সরানো হয়েছে'));
                            case 'watch':
                              context.push('/lessons/$lid');
                            case 'delete':
                              final ok = await confirmAction(
                                context,
                                title: t('Delete "${l['title']}"?', '"${l['title']}" মুছবেন?'),
                                message: t('The lesson and its video will be deleted.', 'লেসন আর এর ভিডিও মুছে যাবে।'),
                                confirm: t('Delete', 'মুছুন'),
                              );
                              if (!ok || !context.mounted) return;
                              await _run(context, ref, () => api.delete('/teacher/lessons/$lid'), t('Lesson deleted', 'লেসন মুছে ফেলা হয়েছে'));
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(
                            value: 'upload',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.upload_rounded),
                              title: Text(l['hasVideo'] == true ? t('Replace video', 'ভিডিও বদলান') : t('Upload video', 'ভিডিও আপলোড')),
                            ),
                          ),
                          PopupMenuItem(value: 'edit', child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.edit_outlined), title: Text(t('Edit', 'এডিট')))),
                          PopupMenuItem(
                            value: 'preview',
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: const Icon(Icons.lock_open_rounded),
                              title: Text(l['isPreview'] == true ? t('Make paid-only', 'শুধু এনরোলড') : t('Make free preview', 'ফ্রি প্রিভিউ করুন')),
                            ),
                          ),
                          if (l['hasVideo'] == true) ...[
                            PopupMenuItem(value: 'watch', child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.play_arrow_rounded), title: Text(t('Watch', 'দেখুন')))),
                            PopupMenuItem(
                              value: 'removeVideo',
                              child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.videocam_off_outlined), title: Text(t('Remove video', 'ভিডিও সরান'))),
                            ),
                          ],
                          PopupMenuItem(value: 'delete', child: ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.delete_outline_rounded), title: Text(t('Delete lesson', 'লেসন মুছুন')))),
                        ],
                      ),
                    ),
                    if (uploads[l['id']] != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          LinearProgressIndicator(value: uploads[l['id']]),
                          const SizedBox(height: 4),
                          Text(t('Uploading… ${(uploads[l['id']]! * 100).round()}% — keep this screen open', 'আপলোড হচ্ছে… ${(uploads[l['id']]! * 100).round()}% — স্ক্রিনটি খোলা রাখুন'),
                              style: text.bodySmall),
                        ]),
                      ),
                    if (l['hasVideo'] != true && uploads[l['id']] == null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(56, 0, 16, 10),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: OutlinedButton.icon(
                            onPressed: () => _uploadVideo(context, ref, l['id'] as String),
                            icon: const Icon(Icons.upload_rounded, size: 18),
                            label: Text(t('Upload video', 'ভিডিও আপলোড')),
                          ),
                        ),
                      ),
                    const Divider(indent: 16),
                  ],
                  TextButton.icon(
                    onPressed: () async {
                      final r = await _lessonDialog(context);
                      if (r == null || !context.mounted) return;
                      await _run(context, ref, () => api.post('/teacher/sections/${s['id']}/lessons', {
                            'title': r['title'],
                            if (r['link']!.isNotEmpty) 'mediaKey': r['link'],
                            'durationSec': (int.tryParse(r['minutes']!) ?? 0) * 60,
                          }));
                    },
                    icon: const Icon(Icons.add_rounded),
                    label: Text(t('Add lesson', 'লেসন যোগ করুন')),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton.icon(
              onPressed: () async {
                final name = await _askName(context, t('New section', 'নতুন সেকশন'), '');
                if (name == null || !context.mounted) return;
                await _run(context, ref, () => api.post('/teacher/courses/$id/sections', {'title': name}));
              },
              icon: const Icon(Icons.playlist_add_rounded),
              label: Text(t('Add section', 'সেকশন যোগ করুন')),
            ),
            const SizedBox(height: 8),
            Text(
              t('Tip: MP4 (H.264) at 720p or 1080p works on every phone. Up to 2 GB per video.',
                  'টিপ: 720p বা 1080p MP4 (H.264) সব ফোনে চলে। প্রতি ভিডিও সর্বোচ্চ ২ GB।'),
              style: text.bodySmall,
            ),
          ]);
        },
      ),
    );
  }
}

Future<String?> _askName(BuildContext context, String title, String initial) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, autofocus: true),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel', 'বাতিল'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim().isEmpty ? null : ctl.text.trim()), child: Text(t('Save', 'সেভ'))),
      ],
    ),
  );
}

/// Full form for a course's public page: everything the Udemy-style detail screen shows.
class CourseDetailsForm extends ConsumerStatefulWidget {
  const CourseDetailsForm({super.key, this.course});
  final Map<String, dynamic>? course;
  @override
  ConsumerState<CourseDetailsForm> createState() => _CourseDetailsFormState();
}

class _CourseDetailsFormState extends ConsumerState<CourseDetailsForm> {
  final _form = GlobalKey<FormState>();
  late final Map<String, dynamic> c = widget.course ?? {};
  late final _title = TextEditingController(text: c['title'] as String?);
  late final _subtitle = TextEditingController(text: c['subtitle'] as String?);
  late final _desc = TextEditingController(text: c['description'] as String?);
  late final _price = TextEditingController(text: '${((c['pricePaisa'] as int?) ?? 0) ~/ 100}');
  late final _was = TextEditingController(text: c['originalPricePaisa'] == null ? '' : '${(c['originalPricePaisa'] as int) ~/ 100}');
  late final _outcomes = TextEditingController(text: (c['outcomes'] as List? ?? const []).join('\n'));
  late final _requirements = TextEditingController(text: (c['requirements'] as List? ?? const []).join('\n'));
  late final _audience = TextEditingController(text: (c['audience'] as List? ?? const []).join('\n'));
  late String? _category = c['categoryId'] as String?;
  late String _level = c['level'] as String? ?? 'ALL';
  late String _language = c['language'] as String? ?? 'bn';
  late String? _thumb = c['thumbnailUrl'] as String?;
  bool _busy = false;
  bool _uploading = false;

  List<String> _lines(TextEditingController ctl) => ctl.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  Future<void> _pickImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file == null) return;
    setState(() => _uploading = true);
    try {
      final bytes = await file.readAsBytes();
      final ext = (file.extension ?? 'jpg').toLowerCase();
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: file.name, contentType: DioMediaType('image', ext == 'jpg' ? 'jpeg' : ext)),
      });
      final res = await ref.read(apiProvider).dio.post('/uploads', data: form, queryParameters: {'kind': 'IMAGE'});
      setState(() => _thumb = (res.data as Map)['url'] as String);
    } on DioException catch (e) {
      if (mounted) showMessage(context, ApiError.from(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final body = {
      'title': _title.text.trim(),
      'subtitle': _subtitle.text.trim(),
      'description': _desc.text.trim(),
      'priceBdt': int.tryParse(_price.text.trim()) ?? 0,
      'originalPriceBdt': int.tryParse(_was.text.trim()),
      'outcomes': _lines(_outcomes),
      'requirements': _lines(_requirements),
      'audience': _lines(_audience),
      'categoryId': ?_category,
      'level': _level,
      'language': _language,
      'thumbnailUrl': ?_thumb,
    };
    try {
      final api = ref.read(apiProvider);
      final saved = widget.course == null
          ? await api.post<Map<String, dynamic>>('/teacher/courses', body)
          : await api.patch<Map<String, dynamic>>('/teacher/courses/${c['id']}', body);
      if (mounted) Navigator.pop(context, saved);
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).value ?? const [];
    final text = Theme.of(context).textTheme;
    final isAdmin = ref.watch(authProvider).me?.isAdmin ?? false;
    final status = isAdmin ? null : ref.watch(teacherStatusProvider).value;
    final canSell = isAdmin || status == null || status['verification']['canSellPaid'] == true;
    Widget gap() => const SizedBox(height: 14);
    return Scaffold(
      appBar: AppBar(title: Text(widget.course == null ? t('New course', 'নতুন কোর্স') : t('Course details', 'কোর্সের তথ্য'))),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: CtaButton(busy: _busy, label: widget.course == null ? t('Create course', 'কোর্স তৈরি করুন') : t('Save changes', 'সেভ করুন'), onPressed: _save),
        ),
      ),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text(t('Course image', 'কোর্সের ছবি'), style: text.titleSmall),
          const SizedBox(height: 8),
          Stack(children: [
            CourseThumb({...c, 'title': _title.text, 'thumbnailUrl': _thumb, 'category': cats.cast<Map<String, dynamic>>().where((x) => x['id'] == _category).firstOrNull}),
            Positioned(
              right: 8,
              bottom: 8,
              child: FilledButton.tonalIcon(
                onPressed: _uploading ? null : _pickImage,
                icon: _uploading ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.image_outlined),
                label: Text(_thumb == null ? t('Upload image', 'ছবি দিন') : t('Change', 'বদলান')),
              ),
            ),
          ]),
          Text(t('16:9, at least 1280×720. Without an image a branded cover is used.', '১৬:৯, কমপক্ষে ১২৮০×৭২০। ছবি না দিলে ব্র্যান্ডেড কভার দেখাবে।'), style: text.bodySmall),
          gap(),
          TextFormField(
            controller: _title,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: t('Course title', 'কোর্সের নাম')),
            validator: (v) => (v ?? '').trim().length < 5 ? t('At least 5 characters', 'কমপক্ষে ৫ অক্ষর') : null,
          ),
          gap(),
          TextFormField(controller: _subtitle, decoration: InputDecoration(labelText: t('Subtitle (one line that sells it)', 'সাবটাইটেল (এক লাইনে কোর্সের মূল কথা)'))),
          gap(),
          TextFormField(
            controller: _desc,
            maxLines: 6,
            decoration: InputDecoration(labelText: t('Description', 'বিবরণ'), alignLabelWithHint: true),
            validator: (v) => (v ?? '').trim().length < 20 ? t('At least 20 characters', 'কমপক্ষে ২০ অক্ষর') : null,
          ),
          gap(),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: InputDecoration(labelText: t('Category', 'ক্যাটাগরি')),
            items: [for (final x in cats) DropdownMenuItem(value: x['id'] as String, child: Text(x['name'] as String))],
            onChanged: (v) => setState(() => _category = v),
          ),
          gap(),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _level,
                decoration: InputDecoration(labelText: t('Level', 'লেভেল')),
                items: [for (final l in ['BEGINNER', 'INTERMEDIATE', 'ADVANCED', 'ALL']) DropdownMenuItem(value: l, child: Text(levelLabel(l)))],
                onChanged: (v) => setState(() => _level = v!),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _language,
                decoration: InputDecoration(labelText: t('Language', 'ভাষা')),
                items: const [DropdownMenuItem(value: 'bn', child: Text('বাংলা')), DropdownMenuItem(value: 'en', child: Text('English'))],
                onChanged: (v) => setState(() => _language = v!),
              ),
            ),
          ]),
          gap(),
          if (!canSell)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Panel(
                onTap: () => context.push('/teacher'),
                child: Row(children: [
                  const BlueTick(size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(t('New instructors start with free courses. Paid pricing opens when you get the blue tick.', 'নতুন ইনস্ট্রাক্টররা ফ্রি কোর্স দিয়ে শুরু করেন। ব্লু টিক পেলে কোর্সে দাম বসাতে পারবেন।')),
                  ),
                ]),
              ),
            ),
          Row(children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                enabled: canSell,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t('Price (৳, 0 = free)', 'দাম (৳, ০ = ফ্রি)')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _was,
                enabled: canSell,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: t('Was price (optional)', 'আগের দাম (ঐচ্ছিক)')),
              ),
            ),
          ]),
          gap(),
          TextFormField(
            controller: _outcomes,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: t('What students will learn', 'শিক্ষার্থীরা যা শিখবে'),
              helperText: t('One point per line', 'প্রতি লাইনে একটি পয়েন্ট'),
              alignLabelWithHint: true,
            ),
          ),
          gap(),
          TextFormField(
            controller: _requirements,
            maxLines: 3,
            decoration: InputDecoration(labelText: t('Requirements', 'যা লাগবে'), helperText: t('One per line', 'প্রতি লাইনে একটি'), alignLabelWithHint: true),
          ),
          gap(),
          TextFormField(
            controller: _audience,
            maxLines: 3,
            decoration: InputDecoration(labelText: t('Who this course is for', 'কোর্সটি কাদের জন্য'), helperText: t('One per line', 'প্রতি লাইনে একটি'), alignLabelWithHint: true),
          ),
          const SizedBox(height: 24),
        ]),
      ),
    );
  }
}
