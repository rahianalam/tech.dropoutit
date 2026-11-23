import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

class CourseFilter {
  const CourseFilter({this.q = '', this.category, this.free});
  final String q;
  final String? category;
  final bool? free;
  @override
  bool operator ==(Object other) => other is CourseFilter && other.q == q && other.category == category && other.free == free;
  @override
  int get hashCode => Object.hash(q, category, free);
}

final categoriesProvider = FutureProvider<List<dynamic>>((ref) => ref.read(apiProvider).get('/categories'));

final coursesProvider = FutureProvider.autoDispose.family<List<dynamic>, CourseFilter>((ref, f) async {
  final res = await ref.read(apiProvider).get<Map<String, dynamic>>('/courses', query: {
    if (f.q.isNotEmpty) 'q': f.q,
    if (f.category != null) 'category': f.category,
    if (f.free != null) 'free': '${f.free}',
  });
  return res['items'] as List;
});

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  var _filter = const CourseFilter();

  @override
  Widget build(BuildContext context) {
    final courses = ref.watch(coursesProvider(_filter));
    final categories = ref.watch(categoriesProvider).value ?? [];
    final me = ref.watch(authProvider).me;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tech.Dropout'),
        actions: [if (me == null) TextButton(onPressed: () => context.go('/login'), child: const Text('লগইন'))],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(coursesProvider(_filter).future),
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: SearchBar(
                hintText: 'কী শিখতে চান? যেমন Flutter, ডিজাইন',
                leading: const Icon(Icons.search),
                onSubmitted: (q) => setState(() => _filter = CourseFilter(q: q.trim(), category: _filter.category, free: _filter.free)),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  FilterChip(
                    label: const Text('ফ্রি কোর্স'),
                    selected: _filter.free == true,
                    onSelected: (on) => setState(() => _filter = CourseFilter(q: _filter.q, category: _filter.category, free: on ? true : null)),
                  ),
                  for (final c in categories) ...[
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(c['name'] as String),
                      selected: _filter.category == c['slug'],
                      onSelected: (on) => setState(() => _filter = CourseFilter(q: _filter.q, category: on ? c['slug'] as String : null, free: _filter.free)),
                    ),
                  ],
                ],
              ),
            ),
          ),
          SliverFillRemaining(
            hasScrollBody: true,
            child: AsyncView(
              value: courses,
              onRetry: () => ref.invalidate(coursesProvider(_filter)),
              data: (items) => items.isEmpty
                  ? const EmptyState('কোনো কোর্স পাওয়া যায়নি', icon: Icons.search_off)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (_, i) => CourseCard(items[i] as Map<String, dynamic>),
                    ),
            ),
          ),
        ]),
      ),
    );
  }
}

class CourseCard extends StatelessWidget {
  const CourseCard(this.course, {super.key});
  final Map<String, dynamic> course;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final rating = (course['ratingAvg'] as num).toDouble();
    return Card(
      child: InkWell(
        onTap: () => context.push('/courses/${course['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 96,
                height: 64,
                child: course['thumbnailUrl'] != null
                    ? Image.network(course['thumbnailUrl'] as String, fit: BoxFit.cover)
                    : ColoredBox(color: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.play_lesson_outlined)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(course['title'] as String, style: text.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                Text(course['teacher']['name'] as String, style: text.bodySmall),
                const SizedBox(height: 4),
                Row(children: [
                  if (course['ratingCount'] as int > 0) ...[
                    const Icon(Icons.star, size: 16, color: Colors.amber),
                    Text(' ${rating.toStringAsFixed(1)} (${course['ratingCount']})', style: text.bodySmall),
                    const Spacer(),
                  ] else
                    const Spacer(),
                  Text(price(course), style: text.titleSmall),
                ]),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}
