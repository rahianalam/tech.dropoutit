import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../booking/booking_screens.dart';

final myEnrollmentsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/me/enrollments'));

class MyLearningScreen extends ConsumerWidget {
  const MyLearningScreen({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      key: ValueKey(initialTab),
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: Text(t('My learning', 'আমার লার্নিং')),
          actions: const [Padding(padding: EdgeInsets.only(right: 12), child: LangToggle())],
          bottom: TabBar(tabs: [Tab(text: t('Courses', 'কোর্স')), Tab(text: t('1:1 sessions', '১:১ সেশন'))]),
        ),
        body: const TabBarView(children: [_CoursesTab(), MySessionsList()]),
      ),
    );
  }
}

class _CoursesTab extends ConsumerStatefulWidget {
  const _CoursesTab();
  @override
  ConsumerState<_CoursesTab> createState() => _CoursesTabState();
}

class _CoursesTabState extends ConsumerState<_CoursesTab> {
  var _show = 'all';

  @override
  Widget build(BuildContext context) {
    final items = ref.watch(myEnrollmentsProvider);
    return AsyncView(
      value: items,
      onRetry: () => ref.invalidate(myEnrollmentsProvider),
      data: (list) {
        if (list.isEmpty) {
          return EmptyState(
            t('Start with a free course — it takes one tap.', 'একটা ফ্রি কোর্স দিয়ে শুরু করুন — এক ট্যাপেই।'),
            title: t('Your learning journey starts here', 'আপনার শেখার যাত্রা এখান থেকেই শুরু'),
            icon: Icons.rocket_launch_outlined,
            action: FilledButton(onPressed: () => context.go('/search?free=true'), child: Text(t('Browse free courses', 'ফ্রি কোর্স দেখুন'))),
          );
        }
        final done = list.where((e) => (e['progressPct'] as int) >= 100).length;
        final filtered = list.where((e) {
          final p = e['progressPct'] as int;
          return _show == 'all' || (_show == 'done' ? p >= 100 : p < 100);
        }).toList();
        return RefreshIndicator(
          onRefresh: () => ref.refresh(myEnrollmentsProvider.future),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            _Streak(total: list.length, done: done),
            const SizedBox(height: 16),
            Wrap(spacing: 8, children: [
              for (final (k, label) in [('all', t('All', 'সব')), ('active', t('In progress', 'চলছে')), ('done', t('Completed', 'শেষ'))])
                ChoiceChip(label: Text(label), selected: _show == k, onSelected: (_) => setState(() => _show = k)),
            ]),
            const SizedBox(height: 12),
            for (final e in filtered) ...[ResumeCard(e as Map<String, dynamic>), const SizedBox(height: 12)],
            if (filtered.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(t('Nothing here yet.', 'এখানে এখনো কিছু নেই।')))),
          ]),
        );
      },
    );
  }
}

/// A small motivation header: courses enrolled and finished.
class _Streak extends ConsumerWidget {
  const _Streak({required this.total, required this.done});
  final int total;
  final int done;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(authProvider).me?.name.split(' ').first ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t('Keep going, $name!', 'চালিয়ে যান, $name!'), style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
            const SizedBox(height: 4),
            Text(
              t('$total courses enrolled · $done completed', '$totalটি কোর্সে এনরোলড · $doneটি শেষ'),
              style: const TextStyle(color: Brand.cyan, fontSize: 13),
            ),
            const SizedBox(height: 4),
            Text(
              t('A little every day beats a lot once a week.', 'প্রতিদিন একটু করে শেখাই সবচেয়ে কাজের।'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ]),
        ),
        const Icon(Icons.local_fire_department_rounded, color: Brand.orange, size: 44),
      ]),
    );
  }
}

/// Enrolled course with progress and a one-tap "resume" into the next lesson.
class ResumeCard extends StatelessWidget {
  const ResumeCard(this.enrollment, {super.key, this.compact = false});
  final Map<String, dynamic> enrollment;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final c = enrollment['course'] as Map<String, dynamic>;
    final pct = enrollment['progressPct'] as int;
    final resume = enrollment['resumeLesson'] as Map<String, dynamic>?;
    final text = Theme.of(context).textTheme;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    void open() => resume != null && pct < 100 ? context.push('/lessons/${resume['id']}') : context.push('/courses/${c['id']}');
    return Card(
      child: InkWell(
        onTap: open,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: compact ? 96 : 120, child: CourseThumb(c, radius: 10, showTitle: false)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(c['title'] as String, maxLines: compact ? 1 : 2, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                if (!compact) Text(c['teacher']['name'] as String, style: text.bodySmall?.copyWith(color: muted)),
                const SizedBox(height: 6),
                ProgressLine(pct),
                const SizedBox(height: 4),
                if (pct >= 100)
                  Row(children: [
                    const Icon(Icons.emoji_events_rounded, size: 16, color: Brand.amber),
                    const SizedBox(width: 4),
                    Text(t('Completed', 'সম্পন্ন'), style: text.labelMedium),
                  ])
                else if (resume != null)
                  Text(
                    t('Next: ${resume['title']}', 'পরের লেসন: ${resume['title']}'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(color: muted),
                  ),
              ]),
            ),
            if (!compact && pct < 100)
              IconButton.filledTonal(onPressed: open, icon: const Icon(Icons.play_arrow_rounded), tooltip: t('Resume', 'চালিয়ে যান')),
          ]),
        ),
      ),
    );
  }
}
