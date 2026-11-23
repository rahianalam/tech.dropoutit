import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/i18n.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

final adminStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(apiProvider).get('/admin/stats'));

class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(adminStatsProvider);
    final name = ref.watch(authProvider).me?.name.split(' ').first ?? '';
    return Scaffold(
      appBar: AppBar(
        title: Text(t('Admin panel', 'অ্যাডমিন প্যানেল')),
        actions: [
          const LangToggle(),
          IconButton(tooltip: t('Notifications', 'নোটিফিকেশন'), onPressed: () => context.push('/notifications'), icon: const Icon(Icons.notifications_none_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminStatsProvider.future),
        child: AsyncView(
          value: stats,
          onRetry: () => ref.invalidate(adminStatsProvider),
          data: (s) {
            int n(String k) => (s[k] as num?)?.toInt() ?? 0;
            final todo = n('pendingApplications') + n('coursesInReview') + n('jobsInReview');
            return ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(20)),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t('Welcome back, $name', 'স্বাগতম, $name'), style: const TextStyle(color: Brand.cyan, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 6),
                        Text(t('Revenue (30 days)', 'আয় (৩০ দিন)'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                        Text(taka(n('revenue30Paisa')), style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: Colors.white)),
                        Text(t('All time ${taka(n('revenueAllPaisa'))}', 'সর্বমোট ${taka(n('revenueAllPaisa'))}'), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                      ]),
                    ),
                    const BrandMark(size: 64, color: Brand.cyan),
                  ]),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.1,
                  children: [
                    _Stat(Icons.people_alt_outlined, t('Users', 'ইউজার'), n('users'), t('+${n('newUsers30')} this month', 'এই মাসে +${n('newUsers30')}'), onTap: () => context.push('/admin/users')),
                    _Stat(Icons.school_outlined, t('Enrollments', 'এনরোলমেন্ট'), n('enrollments'), null),
                    _Stat(Icons.video_library_outlined, t('Live courses', 'লাইভ কোর্স'), n('publishedCourses'), null, onTap: () => context.push('/admin/all-courses')),
                    _Stat(Icons.cast_for_education_outlined, t('Teachers', 'টিচার'), n('teachers'), null),
                    _Stat(Icons.event_available_outlined, t('Sessions (30d)', 'সেশন (৩০ দিন)'), n('bookings30'), null),
                    _Stat(Icons.work_outline_rounded, t('Live jobs', 'লাইভ জব'), n('liveJobs'), null, onTap: () => context.push('/admin/jobs')),
                  ],
                ),
              ),
              if (todo > 0) ...[
                SectionHeader(t('Needs your attention', 'আপনার সিদ্ধান্ত দরকার'), padding: const EdgeInsets.fromLTRB(16, 20, 16, 8)),
                MenuGroup(items: [
                  if (n('pendingApplications') > 0)
                    MenuItem(icon: Icons.person_search_outlined, color: Brand.orangeStrong, title: t('Teacher applications', 'টিচার আবেদন'),
                        trailing: _Count(n('pendingApplications')), onTap: () => context.push('/admin/applications')),
                  if (n('coursesInReview') > 0)
                    MenuItem(icon: Icons.fact_check_outlined, color: Brand.orangeStrong, title: t('Courses waiting for review', 'রিভিউয়ের অপেক্ষায় কোর্স'),
                        trailing: _Count(n('coursesInReview')), onTap: () => context.push('/admin/course-reviews')),
                  if (n('jobsInReview') > 0)
                    MenuItem(icon: Icons.work_history_outlined, color: Brand.orangeStrong, title: t('Jobs waiting for review', 'রিভিউয়ের অপেক্ষায় জব'),
                        trailing: _Count(n('jobsInReview')), onTap: () => context.push('/admin/jobs')),
                ]),
              ],
              MenuGroup(title: t('Content', 'কনটেন্ট'), items: [
                MenuItem(icon: Icons.video_library_outlined, title: t('All courses', 'সব কোর্স'), subtitle: t('Publish, take down, bestseller badge', 'পাবলিশ, বন্ধ, বেস্টসেলার ব্যাজ'),
                    onTap: () => context.push('/admin/all-courses')),
                MenuItem(icon: Icons.upload_file_rounded, title: t('My recorded courses', 'আমার রেকর্ডেড কোর্স'),
                    subtitle: t('Create courses and upload videos', 'কোর্স বানান ও ভিডিও আপলোড করুন'), onTap: () => context.push('/admin/courses')),
                MenuItem(icon: Icons.category_outlined, title: t('Categories', 'ক্যাটাগরি'), onTap: () => context.push('/admin/categories')),
                MenuItem(icon: Icons.fact_check_outlined, title: t('Course review', 'কোর্স রিভিউ'), trailing: _Count(n('coursesInReview')),
                    onTap: () => context.push('/admin/course-reviews')),
              ]),
              MenuGroup(title: t('People', 'মানুষ'), items: [
                MenuItem(icon: Icons.people_alt_outlined, title: t('Users & roles', 'ইউজার ও রোল'), subtitle: t('Block, make teacher or admin', 'ব্লক, টিচার বা অ্যাডমিন বানান'),
                    onTap: () => context.push('/admin/users')),
                MenuItem(icon: Icons.person_search_outlined, title: t('Teacher applications', 'টিচার আবেদন'), trailing: _Count(n('pendingApplications')),
                    onTap: () => context.push('/admin/applications')),
                MenuItem(icon: Icons.work_outline_rounded, title: t('Jobs & companies', 'জব ও কোম্পানি'), trailing: _Count(n('jobsInReview')),
                    onTap: () => context.push('/admin/jobs')),
              ]),
              MenuGroup(title: t('Money', 'টাকা-পয়সা'), items: [
                MenuItem(icon: Icons.receipt_long_outlined, title: t('Orders & refunds', 'অর্ডার ও রিফান্ড'), onTap: () => context.push('/admin/orders')),
                MenuItem(icon: Icons.account_balance_outlined, title: t('Teacher payouts & income', 'টিচার পেআউট ও আয়ের হিসাব'), onTap: () => context.push('/admin/payouts')),
                MenuItem(icon: Icons.tune_rounded, title: t('Commission & payout settings', 'কমিশন ও পেআউট সেটিংস'), onTap: () => context.push('/admin/settings')),
              ]),
              MenuGroup(title: t('System', 'সিস্টেম'), items: [
                MenuItem(icon: Icons.lock_outline_rounded, title: t('Admin login & password', 'অ্যাডমিন লগইন ও পাসওয়ার্ড'),
                    subtitle: t('Change your admin email, phone or password', 'অ্যাডমিন ইমেইল, মোবাইল বা পাসওয়ার্ড বদলান'), onTap: () => context.push('/account/security')),
                MenuItem(icon: Icons.history_rounded, title: t('Activity log', 'অ্যাক্টিভিটি লগ'), onTap: () => context.push('/admin/audit')),
              ]),
            ]);
          },
        ),
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n);
  final int n;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (n > 0) Badge(label: Text('$n'), backgroundColor: Brand.orangeStrong),
        const Icon(Icons.chevron_right_rounded),
      ]);
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.label, this.value, this.hint, {this.onTap});
  final IconData icon;
  final String label;
  final int value;
  final String? hint;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              IconBadge(icon, size: 38),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(compact(value), style: Theme.of(context).textTheme.titleLarge),
                  Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
                  if (hint != null) Text(hint!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: Brand.success, fontWeight: FontWeight.w600)),
                ]),
              ),
            ]),
          ),
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
      appBar: AppBar(title: Text(t('Teacher applications', 'টিচার আবেদন'))),
      body: AsyncView(
        value: apps,
        data: (list) => list.isEmpty
            ? EmptyState(t('No new applications', 'নতুন কোনো আবেদন নেই'), icon: Icons.done_all)
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
        showMessage(context, t('Decision saved', 'সিদ্ধান্ত সেভ হয়েছে'));
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
      appBar: AppBar(title: Text(t('Review application', 'আবেদন রিভিউ'))),
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
          Text(t('About you', 'নিজের সম্পর্কে'), style: text.titleSmall),
          Text(a['bio'] as String),
          const SizedBox(height: 12),
          Text(t('Experience', 'অভিজ্ঞতা'), style: text.titleSmall),
          Text(a['experience'] as String),
          if (a['demoVideoUrl'] != null) ...[SizedBox(height: 12), Text(t('Demo video: ${a['demoVideoUrl']}', 'ডেমো ভিডিও: ${a['demoVideoUrl']}'))],
          const SizedBox(height: 12),
          Text(t('Portfolio', 'পোর্টফোলিও'), style: text.titleSmall),
          for (final p in a['user']['portfolioItems'] as List)
            ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.link), title: Text(p['title'] as String), subtitle: Text(p['url'] as String)),
          const SizedBox(height: 16),
          TextField(controller: _note, maxLines: 3, decoration: InputDecoration(labelText: t('Note (needed for changes or rejection)', 'মন্তব্য (সংশোধন বা রিজেক্টে দরকার)'))),
          const SizedBox(height: 16),
          FilledButton(onPressed: () => _decide('APPROVED'), child: Text(t('Approve', 'অনুমোদন দিন'))),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => _decide('CHANGES_REQUESTED'), child: Text(t('Request changes', 'সংশোধন চাই'))),
          const SizedBox(height: 8),
          TextButton(onPressed: () => _decide('REJECTED'), child: Text(t('Reject', 'রিজেক্ট'))),
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
          title: Text(t('What needs to change?', 'কী সংশোধন দরকার?')),
          content: TextField(controller: ctl, maxLines: 3),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Send', 'পাঠান')))],
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
      appBar: AppBar(title: Text(t('Course review', 'কোর্স রিভিউ'))),
      body: AsyncView(
        value: queue,
        data: (list) => list.isEmpty
            ? EmptyState(t('No courses waiting for review', 'রিভিউয়ের জন্য কোনো কোর্স নেই'), icon: Icons.done_all)
            : ListView(children: [
                for (final c in list)
                  Card(
                    margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Column(children: [
                      ListTile(
                        title: Text(c['title'] as String),
                        subtitle: Text(t('${c['teacher']['name']} · ${price(c)} · ${plural(c['_count']['sections'], 'section')}', '${c['teacher']['name']} · ${price(c as Map<String, dynamic>)} · ${c['_count']['sections']} সেকশন')),
                        onTap: () => context.push('/courses/${c['id']}'),
                      ),
                      OverflowBar(children: [
                        TextButton(onPressed: () => _decide(context, ref, c['id'] as String, 'REJECTED'), child: Text(t('Request changes', 'সংশোধন চাই'))),
                        FilledButton(onPressed: () => _decide(context, ref, c['id'] as String, 'PUBLISHED'), child: Text(t('Publish', 'পাবলিশ'))),
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
      if (mounted) showMessage(context, t('Settings saved', 'সেটিংস সেভ হয়েছে'));
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
      appBar: AppBar(title: Text(t('Commission & payouts', 'কমিশন ও পেআউট'))),
      body: AsyncView(
        value: s,
        data: (data) {
          _load(data);
          return ListView(padding: const EdgeInsets.all(16), children: [
            field(_course, t('Platform commission on course sales (%)', 'কোর্স বিক্রিতে প্ল্যাটফর্ম কমিশন (%)')),
            field(_session, t('Platform commission on session bookings (%)', 'সেশন বুকিংয়ে প্ল্যাটফর্ম কমিশন (%)')),
            field(_hold, t('Hold period (days, for refunds)', 'হোল্ড পিরিয়ড (দিন, রিফান্ডের সময়)')),
            DropdownButtonFormField<String>(
              initialValue: _schedule,
              decoration: InputDecoration(labelText: t('Payout schedule', 'পেআউট শিডিউল')),
              items: [
                DropdownMenuItem(value: 'WEEKLY', child: Text(t('Weekly', 'সাপ্তাহিক'))),
                DropdownMenuItem(value: 'MONTHLY', child: Text(t('Monthly', 'মাসিক'))),
                DropdownMenuItem(value: 'MANUAL', child: Text(t('Manual', 'ম্যানুয়াল'))),
              ],
              onChanged: (v) => setState(() => _schedule = v!),
            ),
            const SizedBox(height: 12),
            if (_schedule == 'MONTHLY') field(_day, t('Payout day of the month (1–28)', 'মাসের কত তারিখে পেআউট (১–২৮)')),
            field(_min, t('Minimum payout (BDT)', 'সর্বনিম্ন পেআউট (টাকা)')),
            FilledButton(onPressed: _save, child: Padding(padding: EdgeInsets.all(12), child: Text(t('Save', 'সেভ করুন')))),
          ]);
        },
      ),
    );
  }
}
