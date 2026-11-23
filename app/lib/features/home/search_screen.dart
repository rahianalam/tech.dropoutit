import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/widgets.dart';
import 'home_screen.dart';

/// Search with filters (category, free/paid, level) and sorting, like Udemy's search.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.initialQuery = '', this.initialCategory, this.initialFree, this.initialSort});
  final String initialQuery;
  final String? initialCategory;
  final bool? initialFree;
  final String? initialSort;
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final _q = TextEditingController(text: widget.initialQuery);
  late var _filter = CourseFilter(
    q: widget.initialQuery,
    category: widget.initialCategory,
    free: widget.initialFree,
    sort: widget.initialSort,
    pageSize: 50,
  );

  bool get _browsing => _filter.q.isEmpty && _filter.category == null && _filter.free == null && _filter.level == null && _filter.sort == null;

  void _set({String? q, Object? category = _keep, Object? free = _keep, Object? level = _keep, Object? sort = _keep}) {
    setState(() => _filter = CourseFilter(
          q: q ?? _filter.q,
          category: category == _keep ? _filter.category : category as String?,
          free: free == _keep ? _filter.free : free as bool?,
          level: level == _keep ? _filter.level : level as String?,
          sort: sort == _keep ? _filter.sort : sort as String?,
          pageSize: 50,
        ));
  }

  Map<String, String> get _sorts => {
        'relevance': t('Most relevant', 'প্রাসঙ্গিক'),
        'rating': t('Highest rated', 'সর্বোচ্চ রেটিং'),
        'newest': t('Newest', 'নতুন'),
        'price_asc': t('Price: low to high', 'দাম: কম থেকে বেশি'),
        'price_desc': t('Price: high to low', 'দাম: বেশি থেকে কম'),
      };

  Future<void> _pickSort() async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(t('Sort by', 'সাজান'), style: Theme.of(ctx).textTheme.titleMedium),
          ),
          for (final e in _sorts.entries)
            ListTile(
              title: Text(e.value),
              trailing: (_filter.sort ?? 'relevance') == e.key ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, e.key),
            ),
        ]),
      ),
    );
    if (v != null) _set(sort: v == 'relevance' ? null : v);
  }

  Future<void> _pickLevel() async {
    final levels = ['BEGINNER', 'INTERMEDIATE', 'ADVANCED', 'ALL'];
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t('Level', 'লেভেল'), style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(title: Text(t('Any level', 'যেকোনো লেভেল')), onTap: () => Navigator.pop(ctx, '')),
          for (final l in levels)
            ListTile(
              title: Text(levelLabel(l)),
              trailing: _filter.level == l ? const Icon(Icons.check_rounded) : null,
              onTap: () => Navigator.pop(ctx, l),
            ),
        ]),
      ),
    );
    if (v != null) _set(level: v.isEmpty ? null : v);
  }

  @override
  Widget build(BuildContext context) {
    final cats = ref.watch(categoriesProvider).value ?? const [];
    final scheme = Theme.of(context).colorScheme;
    String? catName;
    for (final c in cats) {
      if (c['slug'] == _filter.category) catName = c['name'] as String;
    }

    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: TextField(
          controller: _q,
          autofocus: widget.initialQuery.isEmpty && widget.initialCategory == null && widget.initialSort == null && widget.initialFree == null,
          textInputAction: TextInputAction.search,
          onSubmitted: (v) => _set(q: v.trim()),
          decoration: InputDecoration(
            hintText: t('Search courses', 'কোর্স খুঁজুন'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _q.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _q.clear();
                      _set(q: '');
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 10),
          ),
        ),
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LangToggle())],
      ),
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: [
              ActionChip(
                avatar: const Icon(Icons.swap_vert_rounded, size: 18),
                label: Text(_sorts[_filter.sort ?? 'relevance']!),
                onPressed: _pickSort,
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(t('Free', 'ফ্রি')),
                selected: _filter.free == true,
                onSelected: (on) => _set(free: on ? true : null),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(t('Paid', 'পেইড')),
                selected: _filter.free == false,
                onSelected: (on) => _set(free: on ? false : null),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: Text(_filter.level == null ? t('Level', 'লেভেল') : levelLabel(_filter.level)),
                selected: _filter.level != null,
                onSelected: (_) => _pickLevel(),
              ),
              if (catName != null) ...[
                const SizedBox(width: 8),
                InputChip(label: Text(catName), selected: true, onDeleted: () => _set(category: null)),
              ],
            ],
          ),
        ),
        const Divider(),
        Expanded(child: _browsing ? _Browse(onPick: (slug) => _set(category: slug), onQuery: (q) {
          _q.text = q;
          _set(q: q);
        }) : _Results(filter: _filter, scheme: scheme)),
      ]),
    );
  }
}

const _keep = Object();

class _Results extends ConsumerWidget {
  const _Results({required this.filter, required this.scheme});
  final CourseFilter filter;
  final ColorScheme scheme;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final res = ref.watch(coursesProvider(filter));
    return AsyncView(
      value: res,
      onRetry: () => ref.invalidate(coursesProvider(filter)),
      data: (items) => items.isEmpty
          ? EmptyState(
              t('Try a different word or remove a filter.', 'অন্য কোনো শব্দ দিয়ে খুঁজুন বা একটা ফিল্টার সরিয়ে দিন।'),
              title: t('No courses found', 'কোনো কোর্স পাওয়া যায়নি'),
              icon: Icons.search_off_rounded,
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: items.length + 1,
              itemBuilder: (_, i) => i == 0
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Text(
                        t('${items.length} results', '${items.length}টি ফলাফল'),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                      ),
                    )
                  : CourseTile(items[i - 1] as Map<String, dynamic>),
            ),
    );
  }
}

/// Before the user types: popular searches and every category.
class _Browse extends ConsumerWidget {
  const _Browse({required this.onPick, required this.onQuery});
  final void Function(String slug) onPick;
  final void Function(String q) onQuery;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).value ?? const [];
    const popular = ['Flutter', 'React', 'Python', 'Figma', 'SEO', 'Facebook Ads', 'Excel', 'English'];
    final text = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text(t('Popular searches', 'জনপ্রিয় সার্চ'), style: text.titleMedium),
      const SizedBox(height: 10),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in popular) ActionChip(avatar: const Icon(Icons.trending_up_rounded, size: 16), label: Text(p), onPressed: () => onQuery(p)),
      ]),
      const SizedBox(height: 24),
      Text(t('Browse categories', 'ক্যাটাগরি'), style: text.titleMedium),
      const SizedBox(height: 10),
      for (final c in cats)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Card(
            child: ListTile(
              leading: IconBadge(categoryIcon(c['icon'] as String?), color: hexColor(c['color'] as String?)),
              title: Text(c['name'] as String),
              subtitle: Text(t(c['courseCount'] == 1 ? '1 course' : '${c['courseCount'] ?? 0} courses', '${c['courseCount'] ?? 0}টি কোর্স')),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => onPick(c['slug'] as String),
            ),
          ),
        ),
      const SizedBox(height: 8),
      Center(
        child: TextButton.icon(
          onPressed: () => context.go('/jobs'),
          icon: const Icon(Icons.work_outline_rounded),
          label: Text(t('Looking for a job instead?', 'চাকরি খুঁজছেন?')),
        ),
      ),
    ]);
  }
}
