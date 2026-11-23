import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/i18n.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/widgets.dart';
import 'jobs_common.dart';

typedef JobQuery = ({String q, String? type});

final jobsProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, JobQuery>((ref, q) {
  ref.watch(authProvider.select((a) => a.me?.id)); // re-rank when the user changes
  return ref.read(apiProvider).get('/jobs', query: {if (q.q.isNotEmpty) 'q': q.q, 'type': ?q.type});
});
final jobProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.read(apiProvider).get('/jobs/$id'));
final seekerProfileProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  final body = await ref.read(apiProvider).get<dynamic>('/seeker/profile');
  return body is Map<String, dynamic> ? body : null;
});
final myApplicationsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/me/applications'));

/// Jobs tab: everyone can browse; signed-in seekers see matching jobs first.
class JobsScreen extends ConsumerStatefulWidget {
  const JobsScreen({super.key});
  @override
  ConsumerState<JobsScreen> createState() => _JobsScreenState();
}

class _JobsScreenState extends ConsumerState<JobsScreen> {
  final _search = TextEditingController();
  JobQuery _query = (q: '', type: null);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(authProvider).me;
    final jobs = ref.watch(jobsProvider(_query));
    return Scaffold(
      appBar: AppBar(title: Text(t('Jobs', 'জবস')), actions: [
        if (me != null)
          IconButton(tooltip: t('My applications', 'আমার আবেদন'), icon: Icon(Icons.assignment_ind_outlined), onPressed: () => context.push('/jobs/applications')),
        TextButton.icon(
          icon: const Icon(Icons.business_center_outlined),
          label: Text(me?.isEmployer ?? false ? t('My company', 'আমার কোম্পানি') : t('Post a job', 'জব পোস্ট')),
          onPressed: () => context.push(me == null ? '/login' : (me.isEmployer ? '/employer' : '/employer/setup')),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(jobsProvider(_query).future),
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
          TextField(
            controller: _search,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(prefixIcon: Icon(Icons.search), hintText: t('Search by role, skill or company', 'পদ, স্কিল বা কোম্পানি খুঁজুন'), border: OutlineInputBorder()),
            onSubmitted: (v) => setState(() => _query = (q: v.trim(), type: _query.type)),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final e in {null: t('All', 'সব'), ...jobTypes}.entries)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(e.value),
                    selected: _query.type == e.key,
                    onSelected: (_) => setState(() => _query = (q: _query.q, type: e.key)),
                  ),
                ),
            ]),
          ),
          if (me != null && !me.isSeeker && !me.isEmployer)
            Card(
              margin: const EdgeInsets.only(top: 12),
              child: ListTile(
                leading: const Icon(Icons.badge_outlined),
                title: Text(t('Create your job profile', 'জব প্রোফাইল তৈরি করুন')),
                subtitle: Text(t('Add your CV and see jobs that match your skills first', 'CV দিন, আপনার স্কিলের সাথে মেলে এমন জব আগে দেখবেন')),
                onTap: () => context.push('/jobs/profile'),
              ),
            ),
          const SizedBox(height: 12),
          AsyncView(
            value: jobs,
            onRetry: () => ref.invalidate(jobsProvider(_query)),
            data: (page) {
              final items = page['items'] as List;
              if (items.isEmpty) return EmptyState(t('No jobs right now. Check back soon.', 'এই মুহূর্তে কোনো জব নেই। পরে আবার দেখুন।'), icon: Icons.work_off_outlined);
              return Column(children: [for (final j in items) JobCard(j as Map<String, dynamic>)]);
            },
          ),
        ]),
      ),
    );
  }
}

class JobCard extends StatelessWidget {
  const JobCard(this.job, {super.key});
  final Map<String, dynamic> job;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final employer = job['employer'] as Map<String, dynamic>;
    final pay = salary(job);
    final match = job['match'] as int? ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.push('/jobs/${job['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(job['title'] as String, style: text.titleMedium),
            const SizedBox(height: 4),
            Row(children: [
              Flexible(child: Text(employer['companyName'] as String, style: text.bodyMedium)),
              if (employer['verified'] == true) ...[
                const SizedBox(width: 4),
                Icon(Icons.verified, size: 16, color: Theme.of(context).colorScheme.primary),
              ],
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
              StatusPill(jobTypes[job['type']] ?? job['type'] as String),
              if (job['location'] != null) Text('📍 ${job['location']}', style: text.bodySmall),
              if (pay != null) Text(pay, style: text.bodySmall),
              if (match > 0) StatusPill(t('$match skills match', '$matchটা স্কিল মিলেছে'), color: Colors.green.shade700),
            ]),
          ]),
        ),
      ),
    );
  }
}

class JobDetailScreen extends ConsumerStatefulWidget {
  const JobDetailScreen(this.id, {super.key});
  final String id;
  @override
  ConsumerState<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends ConsumerState<JobDetailScreen> {
  bool _busy = false;

  Future<void> _apply() async {
    if (!ref.read(authProvider).loggedIn) return context.go('/login');
    setState(() => _busy = true);
    try {
      final profile = await ref.read(seekerProfileProvider.future);
      if (!mounted) return;
      if (profile == null || profile['cvUrl'] == null) {
        showMessage(context, t('Add your job profile and CV before applying', 'আবেদনের আগে জব প্রোফাইল আর CV যোগ করুন'));
        await context.push('/jobs/profile');
        return;
      }
      final letter = TextEditingController();
      final send = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('Apply', 'আবেদন করুন'), style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(t('The company will see your profile, CV (${profile['cvUpload']?['originalName'] ?? 'link'}) and portfolio.', 'আপনার প্রোফাইল, CV (${profile['cvUpload']?['originalName'] ?? 'লিংক'}) আর পোর্টফোলিও কোম্পানি দেখতে পাবে।')),
            const SizedBox(height: 12),
            TextField(
              controller: letter,
              maxLines: 5,
              maxLength: 3000,
              decoration: InputDecoration(labelText: t('Cover letter (optional)', 'কভার লেটার (ঐচ্ছিক)'), border: OutlineInputBorder(), alignLabelWithHint: true),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Padding(padding: EdgeInsets.all(12), child: Text(t('Send application', 'আবেদন পাঠান')))),
          ]),
        ),
      );
      if (send != true) return;
      await ref.read(apiProvider).post('/jobs/${widget.id}/apply', {if (letter.text.trim().isNotEmpty) 'coverLetter': letter.text.trim()});
      ref.invalidate(jobProvider(widget.id));
      ref.invalidate(myApplicationsProvider);
      if (mounted) showMessage(context, t('Application sent! Track it in "My applications".', 'আবেদন পাঠানো হয়েছে! অগ্রগতি "আমার আবেদন"-এ দেখবেন।'));
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(jobProvider(widget.id));
    final me = ref.watch(authProvider).me;
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView(
        value: job,
        onRetry: () => ref.invalidate(jobProvider(widget.id)),
        data: (j) {
          final text = Theme.of(context).textTheme;
          final employer = j['employer'] as Map<String, dynamic>;
          final applied = j['applied'] as Map<String, dynamic>?;
          final own = me?.id == j['employerId'];
          final pay = salary(j);
          final due = deadline(j);
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(j['title'] as String, style: text.headlineSmall),
            const SizedBox(height: 4),
            Row(children: [
              Flexible(child: Text(employer['companyName'] as String, style: text.titleMedium)),
              if (employer['verified'] == true) ...[
                const SizedBox(width: 4),
                Tooltip(message: t('Verified company', 'ভেরিফায়েড কোম্পানি'), child: Icon(Icons.verified, size: 18, color: Theme.of(context).colorScheme.primary)),
              ],
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              StatusPill(jobTypes[j['type']] ?? j['type'] as String),
              if (j['status'] != 'LIVE') StatusPill(jobStatuses[j['status']] ?? j['status'] as String, color: Theme.of(context).colorScheme.error),
            ]),
            const SizedBox(height: 12),
            if (j['location'] != null) ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: Icon(Icons.place_outlined), title: Text(j['location'] as String)),
            if (pay != null) ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: Icon(Icons.payments_outlined), title: Text(pay)),
            if (due != null) ListTile(contentPadding: EdgeInsets.zero, dense: true, leading: Icon(Icons.event_outlined), title: Text(due)),
            const SizedBox(height: 8),
            if (own)
              OutlinedButton.icon(
                icon: const Icon(Icons.people_outline),
                label: Text(t('View applicants (${j['_count']['applications']})', 'আবেদনকারী দেখুন (${j['_count']['applications']})')),
                onPressed: () => context.push('/employer/jobs/${j['id']}/applicants?title=${Uri.encodeComponent(j['title'] as String)}'),
              )
            else if (applied != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(t('You have applied', 'আপনি আবেদন করেছেন')),
                  trailing: StatusPill(stages[applied['stage']]!, color: stageColor(context, applied['stage'] as String)),
                ),
              )
            else
              FilledButton(
                onPressed: j['open'] == true && !_busy ? _apply : null,
                child: Padding(padding: EdgeInsets.all(12), child: Text(j['open'] == true ? t('Apply', 'আবেদন করুন') : t('Applications closed', 'আবেদন বন্ধ'))),
              ),
            const SizedBox(height: 24),
            Text(t('Required skills', 'দরকারি স্কিল'), style: text.titleMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [for (final s in j['skills'] as List) Chip(label: Text(s as String))]),
            const SizedBox(height: 24),
            Text(t('Job description', 'কাজের বিবরণ'), style: text.titleMedium),
            const SizedBox(height: 8),
            Text(j['description'] as String),
            if (employer['about'] != null) ...[
              const SizedBox(height: 24),
              Text(t('About the company', 'কোম্পানি সম্পর্কে'), style: text.titleMedium),
              const SizedBox(height: 8),
              Text(employer['about'] as String),
            ],
            if (employer['website'] != null)
              TextButton.icon(
                style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
                icon: const Icon(Icons.language),
                label: Text(employer['website'] as String),
                onPressed: () => launchUrl(Uri.parse(employer['website'] as String), mode: LaunchMode.externalApplication),
              ),
          ]);
        },
      ),
    );
  }
}

/// Job seeker profile: headline, skills, CV (PDF upload or link).
class SeekerProfileScreen extends ConsumerStatefulWidget {
  const SeekerProfileScreen({super.key});
  @override
  ConsumerState<SeekerProfileScreen> createState() => _SeekerProfileScreenState();
}

class _SeekerProfileScreenState extends ConsumerState<SeekerProfileScreen> {
  final _form = GlobalKey<FormState>();
  final _headline = TextEditingController();
  final _skills = TextEditingController();
  final _location = TextEditingController();
  final _about = TextEditingController();
  final _cvLink = TextEditingController();
  String? _cvUploadId;
  String? _cvName;
  String? _cvUrl;
  bool _openToWork = true;
  bool _loaded = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ref.read(seekerProfileProvider.future).then((p) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        if (p == null) return;
        _headline.text = p['headline'] as String;
        _skills.text = (p['skills'] as List).join(', ');
        _location.text = p['location'] as String? ?? '';
        _about.text = p['about'] as String? ?? '';
        _cvLink.text = p['cvLink'] as String? ?? '';
        _cvUploadId = p['cvUploadId'] as String?;
        _cvName = p['cvUpload']?['originalName'] as String?;
        _cvUrl = p['cvUrl'] as String?;
        _openToWork = p['openToWork'] as bool? ?? true;
      });
    }, onError: (_) => setState(() => _loaded = true));
  }

  @override
  void dispose() {
    for (final c in [_headline, _skills, _location, _about, _cvLink]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickCv() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['pdf']);
    if (file == null) return;
    final size = await file.length() ?? 0;
    if (size > 5 * 1024 * 1024) {
      if (mounted) showMessage(context, t('CV must be smaller than 5 MB', 'CV ৫ MB-এর কম হতে হবে'));
      return;
    }
    setState(() => _busy = true);
    try {
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(await file.readAsBytes(), filename: file.name, contentType: DioMediaType('application', 'pdf')),
      });
      final res = await ref.read(apiProvider).dio.post('/uploads', data: form, queryParameters: {'kind': 'CV'});
      final body = res.data as Map<String, dynamic>;
      setState(() {
        _cvUploadId = body['id'] as String;
        _cvName = body['originalName'] as String;
        _cvUrl = body['url'] as String;
      });
    } on DioException catch (e) {
      if (mounted) showMessage(context, ApiError.from(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_cvUploadId == null && _cvLink.text.trim().isEmpty) {
      showMessage(context, t('Upload a CV or give a link', 'CV আপলোড করুন বা একটা লিংক দিন'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).put('/seeker/profile', {
        'headline': _headline.text.trim(),
        'skills': splitSkills(_skills.text),
        'location': _location.text.trim().isEmpty ? null : _location.text.trim(),
        'about': _about.text.trim().isEmpty ? null : _about.text.trim(),
        'cvUploadId': _cvUploadId,
        'cvLink': _cvLink.text.trim(),
        'openToWork': _openToWork,
      });
      ref.invalidate(seekerProfileProvider);
      await ref.read(authProvider.notifier).reload();
      if (mounted) {
        showMessage(context, t('Job profile saved', 'জব প্রোফাইল সেভ হয়েছে'));
        context.pop();
      }
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(t('Job profile', 'জব প্রোফাইল'))),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _form,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                TextFormField(
                  controller: _headline,
                  decoration: InputDecoration(labelText: t('What do you do?', 'আপনি কী করেন?'), hintText: t('e.g. Junior Flutter Developer', 'যেমন: জুনিয়র Flutter ডেভেলপার'), border: OutlineInputBorder()),
                  validator: (v) => (v ?? '').trim().length < 3 ? t('Write at least 3 characters', 'কমপক্ষে ৩ অক্ষর লিখুন') : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _skills,
                  decoration: InputDecoration(labelText: t('Skills (separate with commas)', 'স্কিল (কমা দিয়ে আলাদা করুন)'), hintText: 'Flutter, Dart, Firebase', border: OutlineInputBorder()),
                  validator: (v) => splitSkills(v ?? '').isEmpty ? t('Add at least one skill', 'অন্তত একটা স্কিল দিন') : null,
                ),
                const SizedBox(height: 12),
                TextFormField(controller: _location, decoration: InputDecoration(labelText: t('Area (optional)', 'এলাকা (ঐচ্ছিক)'), border: OutlineInputBorder())),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _about,
                  maxLines: 4,
                  decoration: InputDecoration(labelText: t('About you (optional)', 'নিজের সম্পর্কে (ঐচ্ছিক)'), border: OutlineInputBorder(), alignLabelWithHint: true),
                ),
                const SizedBox(height: 20),
                Text('CV', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.picture_as_pdf_outlined),
                    title: Text(_cvName ?? (_cvUploadId != null ? t('CV uploaded', 'CV আপলোড করা আছে') : t('No CV uploaded', 'কোনো CV আপলোড করা নেই'))),
                    subtitle: Text(t('PDF only, up to 5 MB', 'শুধু PDF, ৫ MB পর্যন্ত')),
                    onTap: _cvUrl != null && _cvUploadId != null ? () => launchUrl(Uri.parse(_cvUrl!), mode: LaunchMode.externalApplication) : null,
                    trailing: TextButton(onPressed: _busy ? null : _pickCv, child: Text(_cvUploadId == null ? t('Upload', 'আপলোড') : t('Change', 'বদলান'))),
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _cvLink,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(labelText: t('Or a link to your CV (Google Drive etc.)', 'অথবা CV-এর লিংক (Google Drive ইত্যাদি)'), border: OutlineInputBorder()),
                  validator: (v) {
                    final t = (v ?? '').trim();
                    if (t.isEmpty) return null;
                    final u = Uri.tryParse(t);
                    return u == null || !u.hasScheme || !u.scheme.startsWith('http') ? tr('Enter a link starting with https://', 'https:// দিয়ে শুরু হওয়া লিংক দিন') : null;
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t('Open to work', 'কাজ খুঁজছি')),
                  subtitle: Text(t('Companies can find you', 'কোম্পানিগুলো আপনাকে খুঁজে পাবে')),
                  value: _openToWork,
                  onChanged: (v) => setState(() => _openToWork = v),
                ),
                const SizedBox(height: 4),
                Text(t('Companies also see your portfolio links and the courses you finished on Tech.Dropout.', 'আপনার পোর্টফোলিও লিংক আর Tech.Dropout-এ শেষ করা কোর্সগুলোও আবেদনের সাথে কোম্পানি দেখতে পাবে।'), style: Theme.of(context).textTheme.bodySmall),
                const SizedBox(height: 16),
                FilledButton(onPressed: _busy ? null : _save, child: Padding(padding: EdgeInsets.all(12), child: Text(t('Save', 'সেভ করুন')))),
              ]),
            ),
    );
  }
}

class MyApplicationsScreen extends ConsumerWidget {
  const MyApplicationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myApplicationsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('My applications', 'আমার আবেদন')), actions: [
        TextButton.icon(onPressed: () => context.push('/jobs/profile'), icon: Icon(Icons.badge_outlined), label: Text(t('Job profile', 'জব প্রোফাইল'))),
      ]),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myApplicationsProvider.future),
        child: AsyncView(
          value: list,
          onRetry: () => ref.invalidate(myApplicationsProvider),
          data: (items) => items.isEmpty
              ? ListView(children: [SizedBox(height: 80), EmptyState(t('You haven\'t applied to any jobs yet.', 'এখনো কোনো জবে আবেদন করেননি।'), icon: Icons.work_outline)])
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final a = items[i] as Map<String, dynamic>;
                    final job = a['job'] as Map<String, dynamic>;
                    final stage = a['stage'] as String;
                    return Card(
                      child: ListTile(
                        title: Text(job['title'] as String),
                        subtitle: Text(t('${job['employer']['companyName']}${job['status'] == 'CLOSED' ? ' · Job closed' : ''}', '${job['employer']['companyName']}${job['status'] == 'CLOSED' ? ' · জব বন্ধ' : ''}')),
                        trailing: StatusPill(stages[stage]!, color: stageColor(context, stage)),
                        onTap: () => context.push('/jobs/${job['id']}'),
                        onLongPress: stage != 'APPLIED'
                            ? null
                            : () async {
                                final ok = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(t('Withdraw application?', 'আবেদন তুলে নেবেন?')),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('No', 'না'))),
                                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Withdraw', 'তুলে নিন'))),
                                    ],
                                  ),
                                );
                                if (ok != true) return;
                                try {
                                  await ref.read(apiProvider).delete('/me/applications/${a['id']}');
                                  ref.invalidate(myApplicationsProvider);
                                } catch (e) {
                                  if (context.mounted) showMessage(context, e);
                                }
                              },
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
