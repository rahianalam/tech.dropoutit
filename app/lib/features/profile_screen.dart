import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../core/auth.dart';
import '../core/widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authProvider).me;
    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('প্রোফাইল')),
        body: Center(child: FilledButton(onPressed: () => context.go('/login'), child: const Text('লগইন করুন'))),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('প্রোফাইল')),
      body: ListView(children: [
        ListTile(
          leading: CircleAvatar(child: Text(me.name.characters.first)),
          title: Text(me.name),
          subtitle: Text(me.json['email'] as String? ?? me.json['phone'] as String? ?? ''),
        ),
        const Divider(),
        if (!me.isTeacher)
          ListTile(
            leading: const Icon(Icons.cast_for_education_outlined),
            title: const Text('টিচার হোন'),
            subtitle: const Text('আপনার স্কিল শেখান এবং আয় করুন'),
            onTap: () => context.push('/teacher/apply'),
          ),
        ListTile(
          leading: const Icon(Icons.badge_outlined),
          title: const Text('জব প্রোফাইল ও CV'),
          subtitle: Text(me.isSeeker ? 'আপডেট করুন' : 'চাকরি খুঁজতে প্রোফাইল তৈরি করুন'),
          onTap: () => context.push('/jobs/profile'),
        ),
        ListTile(
          leading: const Icon(Icons.business_center_outlined),
          title: Text(me.isEmployer ? 'আমার কোম্পানি ও জব পোস্ট' : 'কোম্পানি হিসেবে জব পোস্ট করুন'),
          onTap: () => context.push(me.isEmployer ? '/employer' : '/employer/setup'),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('নোটিফিকেশন'),
          onTap: () => context.push('/notifications'),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('লগআউট'),
          onTap: () => ref.read(authProvider.notifier).logout(),
        ),
      ]),
    );
  }
}

final notificationsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/me/notifications'));

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(notificationsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('নোটিফিকেশন')),
      body: AsyncView(
        value: list,
        data: (items) => items.isEmpty
            ? const EmptyState('কোনো নোটিফিকেশন নেই')
            : ListView(children: [
                for (final n in items)
                  ListTile(
                    leading: Icon(n['readAt'] == null ? Icons.circle : Icons.circle_outlined, size: 12),
                    title: Text(n['title'] as String),
                    subtitle: Text(n['body'] as String),
                  ),
              ]),
      ),
    );
  }
}
