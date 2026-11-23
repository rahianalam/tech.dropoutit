import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../learning/my_learning_screen.dart';

/// What the catalogue is asked for. Used by the home rows and the search screen.
class CourseFilter {
  const CourseFilter({this.q = '', this.category, this.free, this.sort, this.level, this.pageSize = 20});
  final String q;
  final String? category;
  final bool? free;
  final String? sort;
  final String? level;
  final int pageSize;

  Map<String, dynamic> get query => {
        if (q.isNotEmpty) 'q': q,
        if (category != null) 'category': category,
        if (free != null) 'free': '$free',
        if (sort != null) 'sort': sort,
        if (level != null) 'level': level,
        'pageSize': '$pageSize',
      };

  @override
  bool operator ==(Object other) =>
      other is CourseFilter &&
      other.q == q &&
      other.category == category &&
      other.free == free &&
      other.sort == sort &&
      other.level == level &&
      other.pageSize == pageSize;
  @override
  int get hashCode => Object.hash(q, category, free, sort, level, pageSize);
}

final categoriesProvider = FutureProvider<List<dynamic>>((ref) => ref.read(apiProvider).get('/categories'));

final coursesProvider = FutureProvider.autoDispose.family<List<dynamic>, CourseFilter>((ref, f) async {
  final res = await ref.read(apiProvider).get<Map<String, dynamic>>('/courses', query: f.query);
  return res['items'] as List;
});

final mentorsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/teachers'));

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const _popular = CourseFilter(pageSize: 12);
  static const _topRated = CourseFilter(sort: 'rating', pageSize: 12);
  static const _newest = CourseFilter(sort: 'newest', pageSize: 12);
  static const _free = CourseFilter(free: true, pageSize: 12);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authProvider).me;
    Future<void> refresh() async {
      ref.invalidate(categoriesProvider);
      ref.invalidate(mentorsProvider);
      for (final f in [_popular, _topRated, _newest, _free]) {
        ref.invalidate(coursesProvider(f));
      }
      if (me != null) ref.invalidate(myEnrollmentsProvider);
      await ref.read(coursesProvider(_popular).future);
    }

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: refresh,
        child: CustomScrollView(slivers: [
          SliverToBoxAdapter(child: _Hero(name: me?.name)),
          if (me != null) const SliverToBoxAdapter(child: _ContinueLearning()),
          const SliverToBoxAdapter(child: _Categories()),
          SliverToBoxAdapter(
            child: _CourseRow(
              title: t('Bestsellers', 'বেস্টসেলার কোর্স'),
              subtitle: t('Most loved by learners like you', 'আপনার মতো শিক্ষার্থীদের সবচেয়ে পছন্দের'),
              filter: _popular,
              seeAll: '/search',
              featuredFirst: true,
            ),
          ),
          const SliverToBoxAdapter(child: _Mentors()),
          SliverToBoxAdapter(
            child: _CourseRow(
              title: t('Top rated', 'সেরা রেটিং'),
              subtitle: t('Highest rated by students', 'শিক্ষার্থীদের দেওয়া সর্বোচ্চ রেটিং'),
              filter: _topRated,
              seeAll: '/search?sort=rating',
            ),
          ),
          const SliverToBoxAdapter(child: _JobsPromo()),
          SliverToBoxAdapter(
            child: _CourseRow(
              title: t('New & noteworthy', 'নতুন কোর্স'),
              filter: _newest,
              seeAll: '/search?sort=newest',
            ),
          ),
          SliverToBoxAdapter(
            child: _CourseRow(
              title: t('Start free', 'ফ্রিতে শুরু করুন'),
              subtitle: t('Learn something new today, no payment needed', 'আজই নতুন কিছু শিখুন, কোনো টাকা লাগবে না'),
              filter: _free,
              seeAll: '/search?free=true',
            ),
          ),
          if (!(me?.isTeacher ?? false) && !(me?.isAdmin ?? false)) const SliverToBoxAdapter(child: _TeachPromo()),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ]),
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({this.name});
  final String? name;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final first = name?.split(' ').first;
    return Container(
      decoration: const BoxDecoration(
        gradient: Brand.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Stack(children: [
        Positioned(
          right: -40,
          top: 30,
          child: Opacity(opacity: 0.08, child: Image.asset('assets/brand/mark.png', width: 220, color: Brand.cyan)),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 22),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const BrandWordmark(size: 19, color: Brand.cyan),
                const Spacer(),
                const LangToggle(onDark: true),
                if (name != null)
                  IconButton(
                    tooltip: t('Notifications', 'নোটিফিকেশন'),
                    onPressed: () => context.push('/notifications'),
                    icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                  )
                else ...[
                  const SizedBox(width: 8),
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () => context.go('/login'),
                    child: Text(t('Log in', 'লগইন')),
                  ),
                ],
              ]),
              const SizedBox(height: 18),
              Text(
                first != null ? t('Hi, $first 👋', 'হাই, $first 👋') : t('Welcome 👋', 'স্বাগতম 👋'),
                style: text.titleMedium?.copyWith(color: Brand.cyan),
              ),
              const SizedBox(height: 4),
              Text(
                t('What do you want to\nlearn today?', 'আজ কী শিখতে\nচান?'),
                style: text.headlineMedium?.copyWith(color: Colors.white, height: 1.2),
              ),
              const SizedBox(height: 16),
              Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => context.go('/search'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    child: Row(children: [
                      const Icon(Icons.search_rounded, color: Brand.teal),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          t('Search Flutter, design, marketing…', 'Flutter, ডিজাইন, মার্কেটিং খুঁজুন…'),
                          style: const TextStyle(color: Brand.muted),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Brand.orangeStrong, borderRadius: BorderRadius.circular(9)),
                        child: const Icon(Icons.tune_rounded, size: 18, color: Colors.white),
                      ),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _HeroChip(Icons.play_circle_outline_rounded, t('Learn at your pace', 'নিজের গতিতে শিখুন')),
                _HeroChip(Icons.groups_2_outlined, t('1:1 mentors', '১:১ মেন্টর')),
                _HeroChip(Icons.work_outline_rounded, t('Get hired', 'চাকরি পান')),
              ]),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip(this.icon, this.label);
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: Brand.cyan),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w500)),
        ]),
      );
}

class _ContinueLearning extends ConsumerWidget {
  const _ContinueLearning();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myEnrollmentsProvider).value ?? const [];
    final active = list.where((e) => (e['progressPct'] as int) < 100).take(6).toList();
    if (active.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(t('Continue learning', 'যেখানে থেমেছিলেন'), onSeeAll: () => context.go('/learning')),
      SizedBox(
        height: 108,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: active.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: 300, child: ResumeCard(active[i] as Map<String, dynamic>, compact: true)),
        ),
      ),
    ]);
  }
}

class _Categories extends ConsumerWidget {
  const _Categories();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cats = ref.watch(categoriesProvider).value ?? const [];
    if (cats.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(t('Explore categories', 'ক্যাটাগরি দেখুন')),
      SizedBox(
        height: 196,
        child: GridView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: cats.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.42),
          itemBuilder: (_, i) {
            final c = cats[i] as Map<String, dynamic>;
            final color = hexColor(c['color'] as String?);
            return Card(
              child: InkWell(
                onTap: () => context.go('/search?category=${c['slug']}'),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    IconBadge(categoryIcon(c['icon'] as String?), color: color, size: 44),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(c['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(height: 1.2)),
                        const SizedBox(height: 2),
                        Text(
                          t(c['courseCount'] == 1 ? '1 course' : '${c['courseCount'] ?? 0} courses', '${c['courseCount'] ?? 0}টি কোর্স'),
                          style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                        ),
                      ]),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _CourseRow extends ConsumerWidget {
  const _CourseRow({required this.title, required this.filter, this.subtitle, this.seeAll, this.featuredFirst = false});
  final String title;
  final String? subtitle;
  final CourseFilter filter;
  final String? seeAll;
  final bool featuredFirst;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(coursesProvider(filter));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(title, subtitle: subtitle, onSeeAll: seeAll == null ? null : () => context.go(seeAll!)),
      courses.when(
        loading: () => const CourseRowSkeleton(),
        error: (e, _) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            Expanded(child: Text(e.toString())),
            TextButton(onPressed: () => ref.invalidate(coursesProvider(filter)), child: Text(t('Retry', 'আবার')))
          ]),
        ),
        data: (items) {
          var list = items.cast<Map<String, dynamic>>();
          if (featuredFirst) list = [...list.where((c) => c['isFeatured'] == true), ...list.where((c) => c['isFeatured'] != true)];
          if (list.isEmpty) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(t('Courses are coming soon.', 'শীঘ্রই কোর্স আসছে।')),
            );
          }
          return SizedBox(
            height: 288,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) => CourseCard(list[i]),
            ),
          );
        },
      ),
    ]);
  }
}

class _Mentors extends ConsumerWidget {
  const _Mentors();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mentors = ref.watch(mentorsProvider).value ?? const [];
    if (mentors.isEmpty) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SectionHeader(
        t('Learn 1:1 with mentors', 'মেন্টরের সাথে ১:১ শিখুন'),
        subtitle: t('Book a live session with an expert', 'একজন এক্সপার্টের সাথে লাইভ সেশন বুক করুন'),
      ),
      SizedBox(
        height: 186,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: mentors.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) {
            final m = mentors[i] as Map<String, dynamic>;
            return SizedBox(
              width: 160,
              child: Card(
                child: InkWell(
                  onTap: () => context.push('/teachers/${m['id']}'),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(children: [
                      Avatar(m['name'] as String, url: m['avatarUrl'] as String?, radius: 30),
                      const SizedBox(height: 8),
                      Text(m['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                      Text(
                        m['headline'] as String? ?? '',
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall?.copyWith(color: muted, height: 1.25),
                      ),
                      const Spacer(),
                      Text(
                        t('${m['students']} students · ${m['courses']} courses', '${m['students']} শিক্ষার্থী · ${m['courses']} কোর্স'),
                        style: text.labelSmall?.copyWith(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600),
                      ),
                    ]),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }
}

class _JobsPromo extends StatelessWidget {
  const _JobsPromo();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
        child: Material(
          color: const Color(0xFFFFEDE2),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.go('/jobs'),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      t('Ready for your first tech job?', 'প্রথম টেক জবের জন্য তৈরি?'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(color: const Color(0xFF6B2E0E)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      t('Companies hire Tech.Dropout learners. Add your CV and apply in one tap.',
                          'কোম্পানিগুলো Tech.Dropout-এর শিক্ষার্থীদের নিয়োগ দেয়। CV দিন, এক ট্যাপে আবেদন করুন।'),
                      style: const TextStyle(color: Color(0xFF8A4A26), fontSize: 13),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Text(t('Browse jobs', 'জব দেখুন'), style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.orangeStrong)),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded, size: 18, color: Brand.orangeStrong),
                    ]),
                  ]),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(color: Brand.orangeStrong, shape: BoxShape.circle),
                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 32),
                ),
              ]),
            ),
          ),
        ),
      );
}

class _TeachPromo extends StatelessWidget {
  const _TeachPromo();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
        child: Container(
          decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(18)),
          padding: const EdgeInsets.all(18),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  t('Become an instructor', 'ইন্সট্রাক্টর হোন'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  t('Share what you know, teach live 1:1 sessions and earn every month.',
                      'আপনার জানা স্কিল শেখান, ১:১ লাইভ সেশন নিন আর প্রতি মাসে আয় করুন।'),
                  style: const TextStyle(color: Brand.cyanSoft, fontSize: 13),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.teal, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
                  onPressed: () => context.push('/teacher/apply'),
                  child: Text(t('Start teaching', 'পড়ানো শুরু করুন')),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            const BrandMark(size: 72, color: Brand.cyan),
          ]),
        ),
      );
}
