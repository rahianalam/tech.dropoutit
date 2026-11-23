import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/auth.dart';
import '../../core/widgets.dart';
import 'jobs_common.dart';

final employerProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final body = await ref.read(apiProvider).get<dynamic>('/employer/profile');
  return body is Map<String, dynamic> ? body : null;
});
final myJobsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/employer/jobs'));
final applicantsProvider = FutureProvider.autoDispose.family<List<dynamic>, String>((ref, jobId) => ref.read(apiProvider).get('/employer/jobs/$jobId/applications'));

/// Company profile. Saving it the first time makes the user an employer.
class EmployerSetupScreen extends ConsumerStatefulWidget {
  const EmployerSetupScreen({super.key});
  @override
  ConsumerState<EmployerSetupScreen> createState() => _EmployerSetupScreenState();
}

class _EmployerSetupScreenState extends ConsumerState<EmployerSetupScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _website = TextEditingController();
  final _location = TextEditingController();
  final _about = TextEditingController();
  bool _busy = false;
  bool _existing = false;

  @override
  void initState() {
    super.initState();
    ref.read(employerProfileProvider.future).then((p) {
      if (p == null || !mounted) return;
      setState(() {
        _existing = true;
        _name.text = p['companyName'] as String;
        _website.text = p['website'] as String? ?? '';
        _location.text = p['location'] as String? ?? '';
        _about.text = p['about'] as String? ?? '';
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    for (final c in [_name, _website, _location, _about]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put('/employer/profile', {
        'companyName': _name.text.trim(),
        'website': ?_opt(_website),
        'location': ?_opt(_location),
        'about': ?_opt(_about),
      });
      ref.invalidate(employerProfileProvider);
      await ref.read(authProvider.notifier).reload();
      if (mounted) _existing ? context.pop() : context.pushReplacement('/employer');
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(_existing ? 'কোম্পানি প্রোফাইল' : 'কোম্পানি হিসেবে জব পোস্ট করুন')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            if (!_existing) ...[
              const Text('কোম্পানির তথ্য দিন। প্রথম দিকের জব পোস্ট অ্যাডমিন দেখে লাইভ করবেন, কোম্পানি ভেরিফায়েড হলে সরাসরি লাইভ হবে।'),
              const SizedBox(height: 16),
            ],
            TextFormField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'কোম্পানির নাম', border: OutlineInputBorder()),
              validator: (v) => (v ?? '').trim().length < 2 ? 'নাম দিন' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _website,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'ওয়েবসাইট বা ফেসবুক পেজ (ঐচ্ছিক)', hintText: 'https://', border: OutlineInputBorder()),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                final u = Uri.tryParse(t);
                return u == null || !u.scheme.startsWith('http') || u.host.isEmpty ? 'https:// দিয়ে পুরো লিংক দিন' : null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'ঠিকানা/এলাকা (ঐচ্ছিক)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextFormField(
              controller: _about,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'কোম্পানি সম্পর্কে (ঐচ্ছিক)', border: OutlineInputBorder(), alignLabelWithHint: true),
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _busy ? null : _save, child: const Padding(padding: EdgeInsets.all(12), child: Text('সেভ করুন'))),
          ]),
        ),
      );
}

class EmployerDashboard extends ConsumerWidget {
  const EmployerDashboard({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(employerProfileProvider);
    final jobs = ref.watch(myJobsProvider);
    final company = profile.value;
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          Flexible(child: Text(company?['companyName'] as String? ?? 'আমার কোম্পানি')),
          if (company?['verified'] == true) ...[
            const SizedBox(width: 6),
            Icon(Icons.verified, size: 20, color: Theme.of(context).colorScheme.primary),
          ],
        ]),
        actions: [IconButton(tooltip: 'কোম্পানি প্রোফাইল', icon: const Icon(Icons.edit_outlined), onPressed: () => context.push('/employer/setup'))],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/employer/jobs/new');
          ref.invalidate(myJobsProvider);
        },
        icon: const Icon(Icons.add),
        label: const Text('নতুন জব'),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myJobsProvider.future),
        child: AsyncView(
          value: jobs,
          onRetry: () => ref.invalidate(myJobsProvider),
          data: (list) => list.isEmpty
              ? ListView(children: const [SizedBox(height: 80), EmptyState('এখনো কোনো জব পোস্ট করেননি। "নতুন জব" চাপুন।', icon: Icons.post_add)])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) => _MyJobTile(list[i] as Map<String, dynamic>),
                ),
        ),
      ),
    );
  }
}

class _MyJobTile extends ConsumerWidget {
  const _MyJobTile(this.job);
  final Map<String, dynamic> job;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = job['status'] as String;
    final count = job['_count']['applications'] as int;
    final fresh = job['newApplications'] as int;
    final scheme = Theme.of(context).colorScheme;
    final color = switch (status) { 'LIVE' => Colors.green.shade700, 'REJECTED' => scheme.error, 'CLOSED' => scheme.outline, _ => Colors.orange.shade800 };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(job['title'] as String, style: Theme.of(context).textTheme.titleMedium)),
            StatusPill(jobStatuses[status] ?? status, color: color),
          ]),
          if (status == 'REJECTED' && job['rejectReason'] != null)
            Padding(padding: const EdgeInsets.only(top: 6), child: Text('কারণ: ${job['rejectReason']}', style: TextStyle(color: scheme.error))),
          Row(children: [
            Badge(
              isLabelVisible: fresh > 0,
              label: Text('$fresh নতুন'),
              child: TextButton.icon(
                icon: const Icon(Icons.people_outline),
                label: Text('$countটা আবেদন'),
                onPressed: () => context.push('/employer/jobs/${job['id']}/applicants?title=${Uri.encodeComponent(job['title'] as String)}'),
              ),
            ),
            const Spacer(),
            if (status != 'CLOSED')
              IconButton(
                tooltip: 'এডিট',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () async {
                  await context.push('/employer/jobs/${job['id']}/edit', extra: job);
                  ref.invalidate(myJobsProvider);
                },
              ),
            if (status == 'LIVE' || status == 'PENDING')
              IconButton(
                tooltip: 'জব বন্ধ করুন',
                icon: const Icon(Icons.block),
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('জবটি বন্ধ করবেন?'),
                      content: const Text('বন্ধ করলে আর নতুন আবেদন আসবে না। আগের আবেদনগুলো থাকবে।'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('না')),
                        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('বন্ধ করুন')),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  try {
                    await ref.read(apiProvider).post('/employer/jobs/${job['id']}/close');
                    ref.invalidate(myJobsProvider);
                  } catch (e) {
                    if (context.mounted) showMessage(context, e);
                  }
                },
              ),
          ]),
        ]),
      ),
    );
  }
}

class JobEditorScreen extends ConsumerStatefulWidget {
  const JobEditorScreen({super.key, this.job});
  final Map<String, dynamic>? job;
  @override
  ConsumerState<JobEditorScreen> createState() => _JobEditorScreenState();
}

class _JobEditorScreenState extends ConsumerState<JobEditorScreen> {
  final _form = GlobalKey<FormState>();
  late final _title = TextEditingController(text: widget.job?['title'] as String?);
  late final _desc = TextEditingController(text: widget.job?['description'] as String?);
  late final _skills = TextEditingController(text: (widget.job?['skills'] as List?)?.join(', '));
  late final _location = TextEditingController(text: widget.job?['location'] as String?);
  late final _min = TextEditingController(text: widget.job?['salaryMin']?.toString());
  late final _max = TextEditingController(text: widget.job?['salaryMax']?.toString());
  late String _type = widget.job?['type'] as String? ?? 'FULL_TIME';
  late DateTime? _deadline = widget.job?['deadline'] == null ? null : DateTime.parse(widget.job!['deadline'] as String).toLocal();
  bool _busy = false;

  @override
  void dispose() {
    for (final c in [_title, _desc, _skills, _location, _min, _max]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    final lo = int.tryParse(_min.text.trim());
    final hi = int.tryParse(_max.text.trim());
    final body = {
      'title': _title.text.trim(),
      'description': _desc.text.trim(),
      'skills': splitSkills(_skills.text),
      'type': _type,
      if (_location.text.trim().isNotEmpty) 'location': _location.text.trim(),
      'salaryMin': ?lo,
      'salaryMax': ?hi,
      // end of the chosen day, so the job stays open all of that day
      if (_deadline != null) 'deadline': DateTime(_deadline!.year, _deadline!.month, _deadline!.day, 23, 59, 59).toUtc().toIso8601String(),
    };
    try {
      final api = ref.read(apiProvider);
      final saved = widget.job == null
          ? await api.post<Map<String, dynamic>>('/employer/jobs', body)
          : await api.put<Map<String, dynamic>>('/employer/jobs/${widget.job!['id']}', body);
      if (mounted) {
        showMessage(context, saved['status'] == 'LIVE' ? 'জব লাইভ হয়েছে!' : 'জমা হয়েছে। অ্যাডমিন দেখে লাইভ করবেন, নোটিফিকেশন পাবেন।');
        context.pop();
      }
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.job == null ? 'নতুন জব পোস্ট' : 'জব এডিট')),
        body: Form(
          key: _form,
          child: ListView(padding: const EdgeInsets.all(16), children: [
            TextFormField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'পদের নাম', hintText: 'যেমন: Junior Flutter Developer', border: OutlineInputBorder()),
              validator: (v) => (v ?? '').trim().length < 5 ? 'কমপক্ষে ৫ অক্ষর' : null,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'ধরন', border: OutlineInputBorder()),
              items: [for (final e in jobTypes.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _skills,
              decoration: const InputDecoration(labelText: 'দরকারি স্কিল (কমা দিয়ে)', hintText: 'Flutter, Dart, REST API', border: OutlineInputBorder()),
              validator: (v) => splitSkills(v ?? '').isEmpty ? 'অন্তত একটা স্কিল দিন' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _desc,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'কাজের বিবরণ, দায়িত্ব, সুবিধা', border: OutlineInputBorder(), alignLabelWithHint: true),
              validator: (v) => (v ?? '').trim().length < 50 ? 'কমপক্ষে ৫০ অক্ষর লিখুন' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(controller: _location, decoration: const InputDecoration(labelText: 'কাজের জায়গা (ঐচ্ছিক)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _min,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'বেতন থেকে (৳/মাস)', border: OutlineInputBorder()),
                  validator: (v) => (v ?? '').trim().isNotEmpty && int.tryParse(v!.trim()) == null ? 'শুধু সংখ্যা' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'পর্যন্ত (৳/মাস)', border: OutlineInputBorder()),
                  validator: (v) {
                    if ((v ?? '').trim().isEmpty) return null;
                    final hi = int.tryParse(v!.trim());
                    final lo = int.tryParse(_min.text.trim());
                    if (hi == null) return 'শুধু সংখ্যা';
                    return lo != null && lo > hi ? 'কম বেতনের চেয়ে বেশি দিন' : null;
                  },
                ),
              ),
            ]),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_outlined),
              title: Text(_deadline == null ? 'আবেদনের শেষ তারিখ নেই' : 'শেষ তারিখ ${deadlineFormat.format(_deadline!)}'),
              trailing: _deadline == null ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _deadline = null)),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(context: context, firstDate: now, lastDate: now.add(const Duration(days: 180)), initialDate: _deadline ?? now.add(const Duration(days: 14)));
                if (d != null) setState(() => _deadline = d);
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Padding(padding: const EdgeInsets.all(12), child: Text(widget.job == null ? 'পোস্ট করুন' : 'সেভ করুন')),
            ),
          ]),
        ),
      );
}

class ApplicantsScreen extends ConsumerWidget {
  const ApplicantsScreen(this.jobId, {super.key, this.title});
  final String jobId;
  final String? title;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(applicantsProvider(jobId));
    return Scaffold(
      appBar: AppBar(title: Text(title ?? 'আবেদনকারী')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(applicantsProvider(jobId).future),
        child: AsyncView(
          value: list,
          onRetry: () => ref.invalidate(applicantsProvider(jobId)),
          data: (items) => items.isEmpty
              ? ListView(children: const [SizedBox(height: 80), EmptyState('এখনো কেউ আবেদন করেনি।', icon: Icons.hourglass_empty)])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _ApplicantCard(jobId, items[i] as Map<String, dynamic>),
                ),
        ),
      ),
    );
  }
}

class _ApplicantCard extends ConsumerWidget {
  const _ApplicantCard(this.jobId, this.app);
  final String jobId;
  final Map<String, dynamic> app;

  Future<void> _update(BuildContext context, WidgetRef ref, Map<String, dynamic> body) async {
    try {
      await ref.read(apiProvider).patch('/employer/applications/${app['id']}', body);
      ref.invalidate(applicantsProvider(jobId));
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final seeker = app['seeker'] as Map<String, dynamic>;
    final profile = seeker['seekerProfile'] as Map<String, dynamic>?;
    final courses = seeker['completedCourses'] as List;
    final portfolio = seeker['portfolioItems'] as List;
    final stage = app['stage'] as String;
    final contact = seeker['email'] as String? ?? seeker['phone'] as String?;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(child: Text((seeker['name'] as String).characters.first)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(seeker['name'] as String, style: text.titleMedium),
                if (profile != null) Text(profile['headline'] as String, style: text.bodySmall),
              ]),
            ),
            if ((app['match'] as int) > 0) StatusPill('${app['match']}টা স্কিল মিলেছে', color: Colors.green.shade700),
          ]),
          if (profile != null && (profile['skills'] as List).isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [for (final s in profile['skills'] as List) Chip(label: Text(s as String), visualDensity: VisualDensity.compact)]),
          ],
          if (courses.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Tech.Dropout-এ শেষ করেছেন: ${courses.map((c) => c['title']).join(', ')}', style: text.bodySmall),
          ],
          if (app['coverLetter'] != null) ...[
            const SizedBox(height: 8),
            Text('"${app['coverLetter']}"', style: text.bodyMedium?.copyWith(fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (app['cvUrl'] != null)
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('CV দেখুন'),
                onPressed: () => launchUrl(Uri.parse(app['cvUrl'] as String), mode: LaunchMode.externalApplication),
              ),
            for (final p in portfolio.take(3))
              TextButton.icon(
                icon: const Icon(Icons.link),
                label: Text(p['title'] as String),
                onPressed: () => launchUrl(Uri.parse(p['url'] as String), mode: LaunchMode.externalApplication),
              ),
          ]),
          if (contact != null) Text('যোগাযোগ: $contact', style: text.bodySmall),
          const Divider(height: 24),
          Row(children: [
            const Text('ধাপ: '),
            DropdownButton<String>(
              value: stage,
              underline: const SizedBox(),
              items: [for (final e in stages.entries) DropdownMenuItem(value: e.key, child: Text(e.value, style: TextStyle(color: stageColor(context, e.key))))],
              onChanged: (v) => v == null || v == stage ? null : _update(context, ref, {'stage': v}),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'নিজের নোট',
              icon: Icon(app['note'] == null ? Icons.note_add_outlined : Icons.sticky_note_2_outlined),
              onPressed: () async {
                final c = TextEditingController(text: app['note'] as String?);
                final note = await showDialog<String>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('নিজের নোট'),
                    content: TextField(controller: c, maxLines: 4, decoration: const InputDecoration(hintText: 'শুধু আপনি দেখবেন')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('সেভ')),
                    ],
                  ),
                );
                if (note != null && context.mounted) await _update(context, ref, {'note': note});
              },
            ),
          ]),
          if (app['note'] != null && (app['note'] as String).isNotEmpty) Text('নোট: ${app['note']}', style: text.bodySmall),
        ]),
      ),
    );
  }
}

/// Admin: approve or reject pending jobs, and verify companies.
class AdminJobsScreen extends ConsumerWidget {
  const AdminJobsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => DefaultTabController(
        length: 2,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('জবস'),
            bottom: const TabBar(tabs: [Tab(text: 'রিভিউ'), Tab(text: 'কোম্পানি')]),
          ),
          body: const TabBarView(children: [_PendingJobs(), _Employers()]),
        ),
      );
}

final _pendingJobsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/admin/jobs'));
final _employersProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/admin/employers'));

class _PendingJobs extends ConsumerWidget {
  const _PendingJobs();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_pendingJobsProvider);
    Future<void> act(Future<void> Function() fn, String done) async {
      try {
        await fn();
        ref.invalidate(_pendingJobsProvider);
        if (context.mounted) showMessage(context, done);
      } catch (e) {
        if (context.mounted) showMessage(context, e);
      }
    }

    return AsyncView(
      value: list,
      onRetry: () => ref.invalidate(_pendingJobsProvider),
      data: (items) => items.isEmpty
          ? const EmptyState('রিভিউয়ের জন্য কোনো জব নেই', icon: Icons.task_alt)
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final j = items[i] as Map<String, dynamic>;
                final api = ref.read(apiProvider);
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(j['title'] as String, style: Theme.of(context).textTheme.titleMedium),
                      Text('${j['employer']['companyName']} · ${jobTypes[j['type']]}'),
                      const SizedBox(height: 6),
                      Text(j['description'] as String, maxLines: 4, overflow: TextOverflow.ellipsis),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        TextButton(onPressed: () => context.push('/jobs/${j['id']}'), child: const Text('পুরোটা দেখুন')),
                        TextButton(
                          onPressed: () async {
                            final c = TextEditingController();
                            final reason = await showDialog<String>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('কেন অনুমোদন দিচ্ছেন না?'),
                                content: TextField(controller: c, maxLines: 3, decoration: const InputDecoration(hintText: 'কোম্পানি এই কারণ দেখবে')),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('বাতিল')),
                                  FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('বাতিল করুন')),
                                ],
                              ),
                            );
                            if (reason == null) return;
                            if (reason.length < 5) {
                              if (context.mounted) showMessage(context, 'কারণ একটু বিস্তারিত লিখুন');
                              return;
                            }
                            await act(() => api.post('/admin/jobs/${j['id']}/reject', {'reason': reason}), 'কোম্পানিকে জানানো হয়েছে');
                          },
                          child: const Text('বাতিল'),
                        ),
                        FilledButton(onPressed: () => act(() => api.post('/admin/jobs/${j['id']}/approve'), 'জব লাইভ হয়েছে'), child: const Text('অনুমোদন')),
                      ]),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}

class _Employers extends ConsumerWidget {
  const _Employers();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_employersProvider);
    return AsyncView(
      value: list,
      onRetry: () => ref.invalidate(_employersProvider),
      data: (items) => items.isEmpty
          ? const EmptyState('এখনো কোনো কোম্পানি নেই', icon: Icons.business_outlined)
          : ListView(children: [
              for (final e in items)
                SwitchListTile(
                  title: Text(e['companyName'] as String),
                  subtitle: Text('${e['user']['name']} · ${e['user']['email'] ?? e['user']['phone'] ?? ''} · ${e['_count']['jobs']}টা জব'),
                  secondary: const Icon(Icons.verified_outlined),
                  value: e['verified'] as bool,
                  onChanged: (v) async {
                    try {
                      await ref.read(apiProvider).patch('/admin/employers/${e['userId']}', {'verified': v});
                      ref.invalidate(_employersProvider);
                    } catch (err) {
                      if (context.mounted) showMessage(context, err);
                    }
                  },
                ),
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('ভেরিফায়েড কোম্পানির জব রিভিউ ছাড়াই সরাসরি লাইভ হয়। কোম্পানির ওয়েবসাইট/ট্রেড লাইসেন্স দেখে তবেই চালু করুন।'),
              ),
            ]),
    );
  }
}

