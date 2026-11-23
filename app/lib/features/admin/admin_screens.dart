import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

final adminStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(apiProvider).get('/admin/stats'));

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('অ্যাডমিন প্যানেল')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminStatsProvider.future),
        child: AsyncView(
          value: stats,
          onRetry: () => ref.invalidate(adminStatsProvider),
          data: (s) => ListView(padding: const EdgeInsets.all(16), children: [
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.8,
              children: [
                _Stat('মোট ইউজার', s['users']),
                _Stat('টিচার', s['teachers']),
                _Stat('লাইভ কোর্স', s['publishedCourses']),
                _Stat('এনরোলমেন্ট', s['enrollments']),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              child: ListTile(
                leading: const Icon(Icons.video_library_outlined),
                title: const Text('আমার রেকর্ডেড কোর্স'),
                subtitle: const Text('Tech.Dropout-এর অফিসিয়াল কোর্স, রিভিউ ছাড়াই পাবলিশ'),
                onTap: () => context.push('/admin/courses'),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.person_search_outlined),
                title: const Text('টিচার আবেদন'),
                trailing: Badge(label: Text('${s['pendingApplications']}'), isLabelVisible: s['pendingApplications'] > 0),
                onTap: () => context.push('/admin/applications'),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('কোর্স রিভিউ'),
                trailing: Badge(label: Text('${s['coursesInReview']}'), isLabelVisible: s['coursesInReview'] > 0),
                onTap: () => context.push('/admin/course-reviews'),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.account_balance_outlined),
                title: const Text('টিচার পেআউট ও আয়ের হিসাব'),
                onTap: () => context.push('/admin/payouts'),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.receipt_long_outlined),
                title: const Text('অর্ডার ও রিফান্ড'),
                onTap: () => context.push('/admin/orders'),
              ),
            ),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: const Icon(Icons.payments_outlined),
                title: const Text('কমিশন ও পেআউট সেটিংস'),
                onTap: () => context.push('/admin/settings'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);
  final String label;
  final Object? value;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
            Text('$value', style: Theme.of(context).textTheme.headlineSmall),
            Text(label),
          ]),
        ),
      );
}

final pendingApplicationsProvider = FutureProvider.autoDispose<List<dynamic>>(
    (ref) => ref.read(apiProvider).get('/admin/teacher-applications', query: {'status': 'PENDING'}));

class ApplicationsScreen extends ConsumerWidget {
  const ApplicationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apps = ref.watch(pendingApplicationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('টিচার আবেদন')),
      body: AsyncView(
        value: apps,
        data: (list) => list.isEmpty
            ? const EmptyState('নতুন কোনো আবেদন নেই', icon: Icons.done_all)
            : ListView(children: [
                for (final a in list)
                  ListTile(
                    title: Text(a['user']['name'] as String),
                    subtitle: Text(a['headline'] as String),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/admin/applications/${a['id']}'),
                  ),
              ]),
      ),
    );
  }
}

final applicationProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
    (ref, id) => ref.read(apiProvider).get('/admin/teacher-applications/$id'));

class ApplicationReviewScreen extends ConsumerStatefulWidget {
  const ApplicationReviewScreen(this.id, {super.key});
  final String id;
  @override
  ConsumerState<ApplicationReviewScreen> createState() => _ApplicationReviewScreenState();
}

class _ApplicationReviewScreenState extends ConsumerState<ApplicationReviewScreen> {
  final _note = TextEditingController();

  Future<void> _decide(String decision) async {
    try {
      await ref.read(apiProvider).post('/admin/teacher-applications/${widget.id}/review', {
        'decision': decision,
        if (_note.text.trim().isNotEmpty) 'note': _note.text.trim(),
      });
      ref.invalidate(pendingApplicationsProvider);
      ref.invalidate(adminStatsProvider);
      if (mounted) {
        showMessage(context, 'সিদ্ধান্ত সেভ হয়েছে');
        context.pop();
      }
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(applicationProvider(widget.id));
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('আবেদন রিভিউ')),
      body: AsyncView(
        value: app,
        data: (a) => ListView(padding: const EdgeInsets.all(16), children: [
          Text(a['user']['name'] as String, style: text.headlineSmall),
          Text([a['user']['email'], a['user']['phone']].whereType<String>().join(' · ')),
          const SizedBox(height: 12),
          Text(a['headline'] as String, style: text.titleMedium),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [for (final s in a['skills'] as List) Chip(label: Text(s as String))]),
          const SizedBox(height: 12),
          Text('নিজের সম্পর্কে', style: text.titleSmall),
          Text(a['bio'] as String),
          const SizedBox(height: 12),
          Text('অভিজ্ঞতা', style: text.titleSmall),
          Text(a['experience'] as String),
          if (a['demoVideoUrl'] != null) ...[const SizedBox(height: 12), Text('ডেমো ভিডিও: ${a['demoVideoUrl']}')],
          const SizedBox(height: 12),
          Text('পোর্টফোলিও', style: text.titleSmall),
          for (final p in a['user']['portfolioItems'] as List)
            ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.link), title: Text(p['title'] as String), subtitle: Text(p['url'] as String)),
          const SizedBox(height: 16),
          TextField(controller: _note, maxLines: 3, decoration: const InputDecoration(labelText: 'মন্তব্য (সংশোধন বা রিজেক্টে দরকার)')),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => _decide('APPROVED'), child: const Text('অনুমোদন দিন')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => _decide('CHANGES_REQUESTED'), child: const Text('সংশোধন চাই')),
          const SizedBox(height: 8),
          TextButton(onPressed: () => _decide('REJECTED'), child: const Text('রিজেক্ট')),
        ]),
      ),
    );
  }
}

final reviewQueueProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/admin/courses/review-queue'));

class CourseReviewScreen extends ConsumerWidget {
  const CourseReviewScreen({super.key});

  Future<void> _decide(BuildContext context, WidgetRef ref, String id, String decision) async {
    String? note;
    if (decision == 'REJECTED') {
      final ctl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('কী সংশোধন দরকার?'),
          content: TextField(controller: ctl, maxLines: 3),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('পাঠান'))],
        ),
      );
      if (ok != true) return;
      note = ctl.text.trim();
    }
    try {
      await ref.read(apiProvider).post('/admin/courses/$id/review', {'decision': decision, 'note': ?note});
      ref.invalidate(reviewQueueProvider);
      ref.invalidate(adminStatsProvider);
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(reviewQueueProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('কোর্স রিভিউ')),
      body: AsyncView(
        value: queue,
        data: (list) => list.isEmpty
            ? const EmptyState('রিভিউয়ের জন্য কোনো কোর্স নেই', icon: Icons.done_all)
            : ListView(children: [
                for (final c in list)
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(children: [
                      ListTile(
                        title: Text(c['title'] as String),
                        subtitle: Text('${c['teacher']['name']} · ${price(c as Map<String, dynamic>)} · ${c['_count']['sections']} সেকশন'),
                        onTap: () => context.push('/courses/${c['id']}'),
                      ),
                      OverflowBar(children: [
                        TextButton(onPressed: () => _decide(context, ref, c['id'] as String, 'REJECTED'), child: const Text('সংশোধন চাই')),
                        FilledButton(onPressed: () => _decide(context, ref, c['id'] as String, 'PUBLISHED'), child: const Text('পাবলিশ')),
                      ]),
                    ]),
                  ),
              ]),
      ),
    );
  }
}

final settingsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(apiProvider).get('/admin/settings'));

/// Commission, hold period and payout timing — all admin-controlled.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _course = TextEditingController();
  final _session = TextEditingController();
  final _hold = TextEditingController();
  final _min = TextEditingController();
  final _day = TextEditingController();
  String _schedule = 'MONTHLY';
  bool _loaded = false;

  void _load(Map<String, dynamic> s) {
    if (_loaded) return;
    _loaded = true;
    _course.text = '${(s['courseCommissionBps'] as int) / 100}';
    _session.text = '${(s['sessionCommissionBps'] as int) / 100}';
    _hold.text = '${s['holdDays']}';
    _min.text = '${(s['minPayoutPaisa'] as int) ~/ 100}';
    _day.text = '${s['payoutDayOfMonth']}';
    _schedule = s['payoutSchedule'] as String;
  }

  Future<void> _save() async {
    int bps(String v) => ((double.tryParse(v) ?? 0) * 100).round();
    try {
      await ref.read(apiProvider).patch('/admin/settings', {
        'courseCommissionBps': bps(_course.text),
        'sessionCommissionBps': bps(_session.text),
        'holdDays': int.tryParse(_hold.text) ?? 7,
        'minPayoutPaisa': (int.tryParse(_min.text) ?? 0) * 100,
        'payoutDayOfMonth': int.tryParse(_day.text) ?? 1,
        'payoutSchedule': _schedule,
      });
      if (mounted) showMessage(context, 'সেটিংস সেভ হয়েছে');
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(settingsProvider);
    Widget field(TextEditingController c, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TextField(controller: c, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: label)),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('কমিশন ও পেআউট')),
      body: AsyncView(
        value: s,
        data: (data) {
          _load(data);
          return ListView(padding: const EdgeInsets.all(16), children: [
            field(_course, 'কোর্স বিক্রিতে প্ল্যাটফর্ম কমিশন (%)'),
            field(_session, 'সেশন বুকিংয়ে প্ল্যাটফর্ম কমিশন (%)'),
            field(_hold, 'হোল্ড পিরিয়ড (দিন, রিফান্ডের সময়)'),
            DropdownButtonFormField<String>(
              initialValue: _schedule,
              decoration: const InputDecoration(labelText: 'পেআউট শিডিউল'),
              items: const [
                DropdownMenuItem(value: 'WEEKLY', child: Text('সাপ্তাহিক')),
                DropdownMenuItem(value: 'MONTHLY', child: Text('মাসিক')),
                DropdownMenuItem(value: 'MANUAL', child: Text('ম্যানুয়াল')),
              ],
              onChanged: (v) => setState(() => _schedule = v!),
            ),
            const SizedBox(height: 12),
            if (_schedule == 'MONTHLY') field(_day, 'মাসের কত তারিখে পেআউট (১–২৮)'),
            field(_min, 'সর্বনিম্ন পেআউট (টাকা)'),
            FilledButton(onPressed: _save, child: const Padding(padding: EdgeInsets.all(12), child: Text('সেভ করুন'))),
          ]);
        },
      ),
    );
  }
}
