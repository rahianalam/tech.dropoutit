import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

const _statusText = {
  'PENDING': 'রিভিউতে আছে',
  'CHANGES_REQUESTED': 'সংশোধন দরকার',
  'APPROVED': 'অনুমোদিত',
  'REJECTED': 'অনুমোদিত হয়নি',
  'DRAFT': 'ড্রাফট',
  'IN_REVIEW': 'রিভিউতে আছে',
  'PUBLISHED': 'লাইভ',
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
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).post('/teacher-applications', {
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
      if (mounted) showMessage(context, 'আবেদন জমা হয়েছে। অ্যাডমিন রিভিউ করে জানাবেন।');
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
      appBar: AppBar(title: const Text('টিচার হিসেবে আবেদন')),
      body: AsyncView(
        value: app,
        data: (a) {
          _prefill(a);
          final status = a?['status'] as String?;
          if (status == 'PENDING') {
            return const EmptyState('আপনার আবেদন রিভিউতে আছে। অনুমোদন হলে নোটিফিকেশন পাবেন।', icon: Icons.hourglass_top);
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
              const Text('আপনার স্কিল দিয়ে শেখান এবং আয় করুন। একটি পোর্টফোলিও বানিয়ে জমা দিন, অ্যাডমিন রিভিউ করবেন।'),
              const SizedBox(height: 16),
              TextFormField(controller: _headline, decoration: const InputDecoration(labelText: 'শিরোনাম (যেমন: ৫ বছরের Flutter ডেভেলপার)'),
                  validator: (v) => (v ?? '').trim().length < 5 ? 'কমপক্ষে ৫ অক্ষর' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _bio, maxLines: 4, decoration: const InputDecoration(labelText: 'নিজের সম্পর্কে'),
                  validator: (v) => (v ?? '').trim().length < 30 ? 'কমপক্ষে ৩০ অক্ষর লিখুন' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _skills, decoration: const InputDecoration(labelText: 'স্কিল (কমা দিয়ে আলাদা করুন)'),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'অন্তত একটি স্কিল' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _experience, maxLines: 3, decoration: const InputDecoration(labelText: 'অভিজ্ঞতা'),
                  validator: (v) => (v ?? '').trim().length < 10 ? 'অভিজ্ঞতা লিখুন' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _demo, decoration: const InputDecoration(labelText: 'ডেমো ভিডিও লিংক (ঐচ্ছিক)')),
              const SizedBox(height: 24),
              Text('পোর্টফোলিও লিংক', style: Theme.of(context).textTheme.titleMedium),
              for (final (i, (title, url)) in _links.indexed) ...[
                const SizedBox(height: 12),
                TextFormField(controller: title, decoration: InputDecoration(labelText: 'লিংক ${i + 1} এর নাম')),
                const SizedBox(height: 8),
                TextFormField(controller: url, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'https://...'),
                    validator: (v) => i == 0 && (v ?? '').trim().isEmpty ? 'অন্তত একটি লিংক দিন' : null),
              ],
              TextButton.icon(
                onPressed: () => setState(() => _links.add((TextEditingController(), TextEditingController()))),
                icon: const Icon(Icons.add),
                label: const Text('আরেকটি লিংক'),
              ),
              const SizedBox(height: 16),
              FilledButton(onPressed: _busy ? null : _submit, child: const Padding(padding: EdgeInsets.all(12), child: Text('আবেদন জমা দিন'))),
            ]),
          );
        },
      ),
    );
  }
}

final myCoursesProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/teacher/courses'));

class TeacherDashboard extends ConsumerWidget {
  const TeacherDashboard({super.key, this.title = 'টিচার ড্যাশবোর্ড'});
  final String title;

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final title = TextEditingController();
    final desc = TextEditingController();
    final priceCtl = TextEditingController(text: '0');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('নতুন কোর্স'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: title, decoration: const InputDecoration(labelText: 'কোর্সের নাম')),
            const SizedBox(height: 12),
            TextField(controller: desc, maxLines: 3, decoration: const InputDecoration(labelText: 'বিবরণ (কমপক্ষে ২০ অক্ষর)')),
            const SizedBox(height: 12),
            TextField(controller: priceCtl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'দাম (টাকা, ০ = ফ্রি)')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('তৈরি করুন')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final c = await ref.read(apiProvider).post<Map<String, dynamic>>('/teacher/courses', {
        'title': title.text.trim(),
        'description': desc.text.trim(),
        'priceBdt': int.tryParse(priceCtl.text.trim()) ?? 0,
      });
      ref.invalidate(myCoursesProvider);
      if (context.mounted) context.push('/teacher/courses/${c['id']}');
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(myCoursesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _create(context, ref),
        icon: const Icon(Icons.add),
        label: const Text('নতুন কোর্স'),
      ),
      body: AsyncView(
        value: courses,
        onRetry: () => ref.invalidate(myCoursesProvider),
        data: (list) => list.isEmpty
            ? const EmptyState('প্রথম কোর্সটি তৈরি করুন', icon: Icons.video_library_outlined)
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final c = list[i] as Map<String, dynamic>;
                  return Card(
                    child: ListTile(
                      title: Text(c['title'] as String),
                      subtitle: Text('${_statusText[c['status']]} · ${c['_count']['enrollments']} স্টুডেন্ট · ${price(c)}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => context.push('/teacher/courses/${c['id']}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

final editCourseProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
    (ref, id) => ref.read(apiProvider).get('/teacher/courses/$id'));

/// Curriculum editor: add sections and lessons, then submit for admin review.
class CourseEditorScreen extends ConsumerWidget {
  const CourseEditorScreen(this.id, {super.key});
  final String id;

  Future<Map<String, String>?> _ask(BuildContext context, String title, List<String> fields) async {
    final ctls = {for (final f in fields) f: TextEditingController()};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final f in fields) Padding(padding: const EdgeInsets.only(bottom: 12), child: TextField(controller: ctls[f], decoration: InputDecoration(labelText: f))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('যোগ করুন')),
        ],
      ),
    );
    return ok == true ? ctls.map((k, v) => MapEntry(k, v.text.trim())) : null;
  }

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() fn, [String? done]) async {
    try {
      await fn();
      ref.invalidate(editCourseProvider(id));
      if (done != null && context.mounted) showMessage(context, done);
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final course = ref.watch(editCourseProvider(id));
    final api = ref.read(apiProvider);
    final me = ref.watch(authProvider).me;
    // The admin's own courses publish directly, without review.
    final official = (me?.isAdmin ?? false) && course.value?['teacherId'] == me?.id;
    return Scaffold(
      appBar: AppBar(title: Text(course.value?['title'] as String? ?? 'কোর্স')),
      body: AsyncView(
        value: course,
        data: (c) => ListView(padding: const EdgeInsets.all(16), children: [
          Card(
            child: ListTile(
              title: Text('স্ট্যাটাস: ${_statusText[c['status']]}'),
              subtitle: c['adminNote'] != null ? Text('অ্যাডমিনের মন্তব্য: ${c['adminNote']}') : null,
              trailing: c['status'] == 'IN_REVIEW'
                  ? null
                  : FilledButton(
                      onPressed: () => _run(context, ref, () => api.post('/teacher/courses/$id/submit'),
                          official ? 'কোর্স পাবলিশ হয়েছে' : 'রিভিউয়ের জন্য জমা হয়েছে'),
                      child: Text(official ? (c['status'] == 'PUBLISHED' ? 'আপডেট পাবলিশ' : 'পাবলিশ করুন') : 'রিভিউতে পাঠান'),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          for (final s in c['sections'] as List) ...[
            Row(children: [
              Expanded(child: Text(s['title'] as String, style: Theme.of(context).textTheme.titleMedium)),
              IconButton(
                tooltip: 'লেসন যোগ করুন',
                icon: const Icon(Icons.add),
                onPressed: () async {
                  final v = await _ask(context, 'নতুন লেসন', ['লেসনের নাম', 'ভিডিও কী (স্টোরেজ পাথ)', 'সময় (মিনিট)']);
                  if (v == null || !context.mounted) return;
                  await _run(context, ref, () => api.post('/teacher/sections/${s['id']}/lessons', {
                        'title': v['লেসনের নাম'],
                        if (v['ভিডিও কী (স্টোরেজ পাথ)']!.isNotEmpty) 'mediaKey': v['ভিডিও কী (স্টোরেজ পাথ)'],
                        'durationSec': (int.tryParse(v['সময় (মিনিট)']!) ?? 0) * 60,
                      }));
                },
              ),
              IconButton(
                tooltip: 'সেকশন মুছুন',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _run(context, ref, () => api.delete('/teacher/sections/${s['id']}')),
              ),
            ]),
            for (final l in s['lessons'] as List)
              ListTile(
                leading: const Icon(Icons.play_circle_outline),
                title: Text(l['title'] as String),
                subtitle: Text(duration(l['durationSec'] as int)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('প্রিভিউ'),
                  Switch(
                    value: l['isPreview'] as bool,
                    onChanged: (v) => _run(context, ref, () => api.patch('/teacher/lessons/${l['id']}', {'isPreview': v})),
                  ),
                ]),
              ),
            const Divider(),
          ],
          OutlinedButton.icon(
            onPressed: () async {
              final v = await _ask(context, 'নতুন সেকশন', ['সেকশনের নাম']);
              if (v == null || !context.mounted) return;
              await _run(context, ref, () => api.post('/teacher/courses/$id/sections', {'title': v['সেকশনের নাম']}));
            },
            icon: const Icon(Icons.add),
            label: const Text('সেকশন যোগ করুন'),
          ),
        ]),
      ),
    );
  }
}
