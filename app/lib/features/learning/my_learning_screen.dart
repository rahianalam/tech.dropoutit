import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/widgets.dart';

final myEnrollmentsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/me/enrollments'));

class MyLearningScreen extends ConsumerWidget {
  const MyLearningScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(myEnrollmentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('আমার লার্নিং')),
      body: AsyncView(
        value: items,
        onRetry: () => ref.invalidate(myEnrollmentsProvider),
        data: (list) => list.isEmpty
            ? const EmptyState('এখনো কোনো কোর্সে এনরোল করেননি। একটা ফ্রি কোর্স দিয়ে শুরু করুন!', icon: Icons.school_outlined)
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final e = list[i];
                  final pct = (e['progressPct'] as int) / 100;
                  return Card(
                    child: ListTile(
                      title: Text(e['course']['title'] as String),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(e['course']['teacher']['name'] as String),
                        const SizedBox(height: 8),
                        LinearProgressIndicator(value: pct),
                        const SizedBox(height: 4),
                        Text('${e['progressPct']}% সম্পন্ন'),
                      ]),
                      onTap: () => context.push('/courses/${e['course']['id']}'),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
