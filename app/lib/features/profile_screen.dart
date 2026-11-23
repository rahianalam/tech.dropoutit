import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/auth.dart';
import '../core/config.dart';
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
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('প্রাইভেসি পলিসি'),
          onTap: () => launchUrl(Uri.parse('$siteUrl/privacy'), mode: LaunchMode.externalApplication),
        ),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('লগআউট'),
          onTap: () => ref.read(authProvider.notifier).logout(),
        ),
        const Divider(),
        ListTile(
          leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
          title: Text('অ্যাকাউন্ট ডিলিট করুন', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          onTap: () => _deleteAccount(context, ref),
        ),
      ]),
    );
  }
}

Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
  final password = TextEditingController();
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('অ্যাকাউন্ট চিরতরে ডিলিট করবেন?'),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('আপনার নাম, ইমেইল/মোবাইল, জব প্রোফাইল, CV আর পোর্টফোলিও মুছে যাবে। কেনা কোর্সে আর ঢুকতে পারবেন না। এটা ফেরানো যাবে না।'),
        const SizedBox(height: 12),
        TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'নিশ্চিত করতে পাসওয়ার্ড দিন')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('না')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('ডিলিট করুন'),
        ),
      ],
    ),
  );
  if (ok != true || password.text.isEmpty) return;
  try {
    await ref.read(apiProvider).post('/auth/delete-account', {'password': password.text});
    await ref.read(authProvider.notifier).logout();
    if (context.mounted) showMessage(context, 'অ্যাকাউন্ট ডিলিট হয়েছে');
  } catch (e) {
    if (context.mounted) showMessage(context, e);
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
