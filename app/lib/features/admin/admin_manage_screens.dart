import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../home/home_screen.dart';
import 'admin_screens.dart';

Map<String, String> get courseStatusText => {
      'DRAFT': t('Draft', 'ড্রাফট'),
      'IN_REVIEW': t('In review', 'রিভিউতে'),
      'PUBLISHED': t('Live', 'লাইভ'),
      'REJECTED': t('Changes needed', 'সংশোধন দরকার'),
    };

Tag statusTag(String status) => switch (status) {
      'PUBLISHED' => Tag(courseStatusText[status]!, color: const Color(0xFFD7F5E6), textColor: const Color(0xFF13633F)),
      'IN_REVIEW' => Tag(courseStatusText[status]!, color: const Color(0xFFFFE9C7), textColor: const Color(0xFF7A4A00)),
      'REJECTED' => Tag(courseStatusText[status]!, color: const Color(0xFFFFDAD6), textColor: const Color(0xFF8C1D18)),
      _ => Tag(courseStatusText[status] ?? status),
    };

Future<String?> askText(BuildContext context, {required String title, String? hint, String? initial, int lines = 3}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(controller: ctl, maxLines: lines, autofocus: true, decoration: InputDecoration(hintText: hint)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(t('Cancel', 'বাতিল'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: Text(t('OK', 'ঠিক আছে'))),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// All courses
// ---------------------------------------------------------------------------

final adminCoursesProvider = FutureProvider.autoDispose.family<List<dynamic>, (String, String?)>(
  (ref, f) => ref.read(apiProvider).get('/admin/courses', query: {if (f.$1.isNotEmpty) 'q': f.$1, 'status': ?f.$2}),
);

class AdminCoursesScreen extends ConsumerStatefulWidget {
  const AdminCoursesScreen({super.key});
  @override
  ConsumerState<AdminCoursesScreen> createState() => _AdminCoursesScreenState();
}

class _AdminCoursesScreenState extends ConsumerState<AdminCoursesScreen> {
  var _q = '';
  String? _status;

  Future<void> _act(Future<void> Function() fn, String done) async {
    try {
      await fn();
      ref.invalidate(adminCoursesProvider);
      ref.invalidate(adminStatsProvider);
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminCoursesProvider((_q, _status)));
    final api = ref.read(apiProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('All courses', 'সব কোর্স'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(hintText: t('Search title or teacher', 'নাম বা টিচার দিয়ে খুঁজুন'), prefixIcon: const Icon(Icons.search_rounded)),
            onSubmitted: (v) => setState(() => _q = v.trim()),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
            for (final s in [null, 'PUBLISHED', 'IN_REVIEW', 'DRAFT', 'REJECTED'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(s == null ? t('All', 'সব') : courseStatusText[s]!),
                  selected: _status == s,
                  onSelected: (_) => setState(() => _status = s),
                ),
              ),
          ]),
        ),
        Expanded(
          child: AsyncView(
            value: list,
            onRetry: () => ref.invalidate(adminCoursesProvider),
            data: (items) => items.isEmpty
                ? EmptyState(t('No courses match.', 'কোনো কোর্স মেলেনি।'), icon: Icons.video_library_outlined)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (_, i) {
                      final c = items[i] as Map<String, dynamic>;
                      final id = c['id'] as String;
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              SizedBox(width: 96, child: CourseThumb(c, radius: 8, showTitle: false)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleSmall),
                                  Text(
                                    '${c['teacher']['name']} · ${price(c)} · ${t(plural(c['_count']['enrollments'], 'student'), '${c['_count']['enrollments']} শিক্ষার্থী')}',
                                    style: Theme.of(context).textTheme.bodySmall,
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(spacing: 6, children: [statusTag(c['status'] as String), if (c['isFeatured'] == true) Tag.bestseller()]),
                                ]),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (v) async {
                                  switch (v) {
                                    case 'view':
                                      context.push('/courses/$id');
                                    case 'edit':
                                      context.push('/teacher/courses/$id');
                                    case 'feature':
                                      final on = c['isFeatured'] != true;
                                      await _act(() => api.post('/admin/courses/$id/featured/$on'),
                                          on ? t('Marked as bestseller', 'বেস্টসেলার করা হয়েছে') : t('Removed from bestsellers', 'বেস্টসেলার থেকে সরানো হয়েছে'));
                                    case 'publish':
                                      await _act(() => api.post('/admin/courses/$id/status', {'status': 'PUBLISHED'}), t('Course is live', 'কোর্স লাইভ হয়েছে'));
                                    case 'down':
                                      final note = await askText(context, title: t('Why take it down?', 'কেন বন্ধ করছেন?'), hint: t('The teacher will see this', 'টিচার এটা দেখবেন'));
                                      if (note == null) return;
                                      await _act(
                                        () => api.post('/admin/courses/$id/status', {'status': 'DRAFT', if (note.isNotEmpty) 'note': note}),
                                        t('Course taken down', 'কোর্স বন্ধ করা হয়েছে'),
                                      );
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(value: 'view', child: Text(t('View as student', 'শিক্ষার্থী হিসেবে দেখুন'))),
                                  PopupMenuItem(value: 'edit', child: Text(t('Edit curriculum & videos', 'কারিকুলাম ও ভিডিও এডিট'))),
                                  if (c['status'] == 'PUBLISHED')
                                    PopupMenuItem(
                                      value: 'feature',
                                      child: Text(c['isFeatured'] == true ? t('Remove bestseller badge', 'বেস্টসেলার ব্যাজ সরান') : t('Mark as bestseller', 'বেস্টসেলার করুন')),
                                    ),
                                  if (c['status'] != 'PUBLISHED') PopupMenuItem(value: 'publish', child: Text(t('Publish now', 'এখনই পাবলিশ'))),
                                  if (c['status'] == 'PUBLISHED') PopupMenuItem(value: 'down', child: Text(t('Take down', 'বন্ধ করুন'))),
                                ],
                              ),
                            ]),
                            if (c['adminNote'] != null) ...[
                              const SizedBox(height: 6),
                              Text(t('Note: ${c['adminNote']}', 'নোট: ${c['adminNote']}'), style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ]),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Categories
// ---------------------------------------------------------------------------

const _palette = ['#355457', '#2F6F8F', '#1F7A8C', '#3E8E6A', '#E07A45', '#B5508A', '#6B5BD2', '#8C6D1F', '#C6362B', '#445A64'];

class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, [Map<String, dynamic>? cat]) async {
    final name = TextEditingController(text: cat?['name'] as String?);
    final slug = TextEditingController(text: cat?['slug'] as String?);
    final position = TextEditingController(text: '${cat?['position'] ?? 0}');
    var icon = cat?['icon'] as String? ?? 'school';
    var color = cat?['color'] as String? ?? _palette.first;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(cat == null ? t('New category', 'নতুন ক্যাটাগরি') : t('Edit category', 'ক্যাটাগরি এডিট'), style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: name,
                decoration: InputDecoration(labelText: t('Name', 'নাম')),
                onChanged: (v) {
                  if (cat == null) slug.text = v.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9]+'), '-').replaceAll(RegExp(r'^-|-$'), '');
                },
              ),
              const SizedBox(height: 12),
              TextField(controller: slug, decoration: InputDecoration(labelText: t('Link name (a-z, 0-9, -)', 'লিংক নাম (a-z, 0-9, -)'))),
              const SizedBox(height: 12),
              TextField(controller: position, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Order (0 shows first)', 'ক্রম (০ সবার আগে)'))),
              const SizedBox(height: 16),
              Text(t('Icon', 'আইকন'), style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final i in categoryIconNames)
                  ChoiceChip(label: Icon(categoryIcon(i), size: 20), selected: icon == i, onSelected: (_) => set(() => icon = i)),
              ]),
              const SizedBox(height: 16),
              Text(t('Colour', 'রং'), style: Theme.of(ctx).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final c in _palette)
                  GestureDetector(
                    onTap: () => set(() => color = c),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: hexColor(c),
                      child: color == c ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                    ),
                  ),
              ]),
              const SizedBox(height: 20),
              CtaButton(label: t('Save', 'সেভ'), onPressed: () => Navigator.pop(ctx, true)),
            ]),
          ),
        ),
      ),
    );
    if (saved != true) return;
    final body = {'name': name.text.trim(), 'slug': slug.text.trim(), 'icon': icon, 'color': color, 'position': int.tryParse(position.text) ?? 0};
    try {
      final api = ref.read(apiProvider);
      cat == null ? await api.post('/admin/categories', body) : await api.patch('/admin/categories/${cat['id']}', body);
      ref.invalidate(categoriesProvider);
      if (context.mounted) showMessage(context, t('Category saved', 'ক্যাটাগরি সেভ হয়েছে'));
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, Map<String, dynamic> cat) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t('Delete "${cat['name']}"?', '"${cat['name']}" ডিলিট করবেন?')),
        content: Text(t('Its courses stay, without a category.', 'এর কোর্সগুলো থাকবে, শুধু ক্যাটাগরি ছাড়া।')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel', 'বাতিল'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Delete', 'ডিলিট'))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).delete('/admin/categories/${cat['id']}');
      ref.invalidate(categoriesProvider);
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Categories', 'ক্যাটাগরি'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: Text(t('New category', 'নতুন ক্যাটাগরি')),
      ),
      body: AsyncView(
        value: cats,
        onRetry: () => ref.invalidate(categoriesProvider),
        data: (list) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          itemCount: list.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final c = list[i] as Map<String, dynamic>;
            return Card(
              child: ListTile(
                leading: IconBadge(categoryIcon(c['icon'] as String?), color: hexColor(c['color'] as String?)),
                title: Text(c['name'] as String),
                subtitle: Text('/${c['slug']} · ${t(c['courseCount'] == 1 ? '1 live course' : '${c['courseCount'] ?? 0} live courses', '${c['courseCount'] ?? 0}টি লাইভ কোর্স')} · #${c['position']}'),
                onTap: () => _edit(context, ref, c),
                trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _delete(context, ref, c)),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Users
// ---------------------------------------------------------------------------

final adminUsersProvider = FutureProvider.autoDispose.family<List<dynamic>, (String, String?)>(
  (ref, f) => ref.read(apiProvider).get('/admin/users', query: {if (f.$1.isNotEmpty) 'q': f.$1, 'role': ?f.$2}),
);

Map<String, String> get roleText => {
      'ADMIN': t('Admin', 'অ্যাডমিন'),
      'TEACHER': t('Teacher', 'টিচার'),
      'STUDENT': t('Student', 'স্টুডেন্ট'),
      'EMPLOYER': t('Employer', 'নিয়োগদাতা'),
      'AFFILIATE': t('Affiliate', 'অ্যাফিলিয়েট'),
      'JOB_SEEKER': t('Job seeker', 'চাকরিপ্রার্থী'),
    };

class UsersScreen extends ConsumerStatefulWidget {
  const UsersScreen({super.key});
  @override
  ConsumerState<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends ConsumerState<UsersScreen> {
  var _q = '';
  String? _role;

  Future<void> _act(Future<void> Function() fn, String done) async {
    try {
      await fn();
      ref.invalidate(adminUsersProvider);
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final users = ref.watch(adminUsersProvider((_q, _role)));
    final myId = ref.watch(authProvider).me?.id;
    final api = ref.read(apiProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Users', 'ইউজার'))),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(hintText: t('Search name, email or phone', 'নাম, ইমেইল বা মোবাইল'), prefixIcon: const Icon(Icons.search_rounded)),
            onSubmitted: (v) => setState(() => _q = v.trim()),
          ),
        ),
        SizedBox(
          height: 52,
          child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), children: [
            for (final r in [null, 'TEACHER', 'STUDENT', 'AFFILIATE', 'EMPLOYER', 'ADMIN'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(r == null ? t('All', 'সব') : roleText[r]!), selected: _role == r, onSelected: (_) => setState(() => _role = r)),
              ),
          ]),
        ),
        Expanded(
          child: AsyncView(
            value: users,
            onRetry: () => ref.invalidate(adminUsersProvider),
            data: (list) => list.isEmpty
                ? EmptyState(t('No users found.', 'কোনো ইউজার পাওয়া যায়নি।'), icon: Icons.person_search_outlined)
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final u = list[i] as Map<String, dynamic>;
                      final id = u['id'] as String;
                      final roles = [for (final r in u['roles'] as List) r['role'] as String];
                      final blocked = u['status'] == 'BLOCKED';
                      return Card(
                        child: ListTile(
                          leading: Avatar(u['name'] as String, radius: 20),
                          title: Text(u['name'] as String),
                          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text([u['email'], u['phone']].whereType<String>().join(' · ')),
                            const SizedBox(height: 4),
                            Wrap(spacing: 4, runSpacing: 4, children: [
                              for (final r in roles) Tag(roleText[r] ?? r),
                              if (blocked) Tag(t('Blocked', 'ব্লকড'), color: const Color(0xFFFFDAD6), textColor: const Color(0xFF8C1D18)),
                              if (u['status'] == 'DELETED') Tag(t('Deleted', 'ডিলিটেড')),
                            ]),
                          ]),
                          isThreeLine: true,
                          trailing: id == myId || u['status'] == 'DELETED'
                              ? null
                              : PopupMenuButton<String>(
                                  onSelected: (v) => switch (v) {
                                    'teacher+' => _act(() => api.patch('/admin/users/$id/roles', {'add': ['TEACHER']}), t('Now a teacher', 'এখন টিচার')),
                                    'teacher-' => _act(() => api.patch('/admin/users/$id/roles', {'remove': ['TEACHER']}), t('Teacher role removed', 'টিচার রোল সরানো হয়েছে')),
                                    'tick+' => _act(() => api.post('/admin/teachers/$id/verify', {'verified': true}), t('Blue tick given', 'ব্লু টিক দেওয়া হয়েছে')),
                                    'tick-' => _act(() => api.post('/admin/teachers/$id/verify', {'verified': false}), t('Blue tick removed', 'ব্লু টিক সরানো হয়েছে')),
                                    'admin+' => _act(() => api.patch('/admin/users/$id/roles', {'add': ['ADMIN']}), t('Now an admin', 'এখন অ্যাডমিন')),
                                    'admin-' => _act(() => api.patch('/admin/users/$id/roles', {'remove': ['ADMIN']}), t('Admin role removed', 'অ্যাডমিন রোল সরানো হয়েছে')),
                                    'block' => _act(() => api.patch('/admin/users/$id/status', {'status': 'BLOCKED'}), t('User blocked', 'ইউজার ব্লক হয়েছে')),
                                    _ => _act(() => api.patch('/admin/users/$id/status', {'status': 'ACTIVE'}), t('User unblocked', 'আনব্লক হয়েছে')),
                                  },
                                  itemBuilder: (_) => [
                                    roles.contains('TEACHER')
                                        ? PopupMenuItem(value: 'teacher-', child: Text(t('Remove teacher role', 'টিচার রোল সরান')))
                                        : PopupMenuItem(value: 'teacher+', child: Text(t('Make teacher', 'টিচার বানান'))),
                                    if (roles.contains('TEACHER'))
                                      u['teacherProfile']?['verifiedAt'] != null
                                          ? PopupMenuItem(value: 'tick-', child: Text(t('Remove blue tick', 'ব্লু টিক সরান')))
                                          : PopupMenuItem(value: 'tick+', child: Text(t('Give blue tick (can sell paid)', 'ব্লু টিক দিন (পেইড বিক্রি করতে পারবে)'))),
                                    roles.contains('ADMIN')
                                        ? PopupMenuItem(value: 'admin-', child: Text(t('Remove admin role', 'অ্যাডমিন রোল সরান')))
                                        : PopupMenuItem(value: 'admin+', child: Text(t('Make admin', 'অ্যাডমিন বানান'))),
                                    blocked
                                        ? PopupMenuItem(value: 'unblock', child: Text(t('Unblock', 'আনব্লক')))
                                        : PopupMenuItem(value: 'block', child: Text(t('Block', 'ব্লক'))),
                                  ],
                                ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Audit log
// ---------------------------------------------------------------------------

final auditProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/admin/audit'));

class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(auditProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Activity log', 'অ্যাক্টিভিটি লগ'))),
      body: AsyncView(
        value: list,
        onRetry: () => ref.invalidate(auditProvider),
        data: (items) => items.isEmpty
            ? EmptyState(t('Nothing yet.', 'এখনো কিছু নেই।'), icon: Icons.history_rounded)
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const Divider(),
                itemBuilder: (_, i) {
                  final a = items[i];
                  return ListTile(
                    leading: const Icon(Icons.history_rounded, color: Brand.teal),
                    title: Text(a['action'] as String),
                    subtitle: Text('${DateFormat.yMMMd().add_jm().format(DateTime.parse(a['createdAt'] as String).toLocal())} · ${a['target']}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  );
                },
              ),
      ),
    );
  }
}
