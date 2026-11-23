import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/auth.dart';
import '../core/config.dart';
import '../core/i18n.dart';
import '../core/theme.dart';
import '../core/widgets.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authProvider).me;
    final lang = ref.watch(langProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final languageItem = MenuItem(
      icon: Icons.translate_rounded,
      title: t('Language', 'ভাষা'),
      subtitle: lang == Lang.en ? 'English' : 'বাংলা',
      trailing: const LangToggle(),
    );
    final about = MenuGroup(title: t('About', 'সম্পর্কে'), items: [
      MenuItem(
        icon: Icons.privacy_tip_outlined,
        title: t('Privacy policy', 'প্রাইভেসি পলিসি'),
        onTap: () => launchUrl(Uri.parse('$siteUrl/privacy'), mode: LaunchMode.externalApplication),
      ),
      MenuItem(
        icon: Icons.language_rounded,
        title: t('Visit our website', 'ওয়েবসাইট দেখুন'),
        subtitle: 'tech.dropout.it',
        onTap: () => launchUrl(Uri.parse('https://tech.dropout.it'), mode: LaunchMode.externalApplication),
      ),
    ]);

    if (me == null) {
      return Scaffold(
        appBar: AppBar(title: Text(t('Account', 'অ্যাকাউন্ট'))),
        body: ListView(children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                const BrandMark(size: 56, color: Brand.cyan),
                const SizedBox(height: 10),
                Text(t('Learn, grow and get hired', 'শিখুন, এগিয়ে যান, চাকরি পান'), style: text.titleMedium?.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(
                  t('Log in to save your progress, book mentors and apply to jobs.', 'অগ্রগতি সেভ করতে, মেন্টর বুক করতে আর জবে আবেদন করতে লগইন করুন।'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Brand.cyanSoft),
                ),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Brand.teal),
                      onPressed: () => context.push('/login'),
                      child: Text(t('Log in', 'লগইন')),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: Brand.orangeStrong),
                      onPressed: () => context.push('/register'),
                      child: Text(t('Sign up', 'রেজিস্টার')),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
          MenuGroup(title: t('Settings', 'সেটিংস'), items: [languageItem]),
          about,
        ]),
      );
    }

    final contact = me.json['email'] as String? ?? me.json['phone'] as String? ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(t('Account', 'অ্যাকাউন্ট'))),
      body: ListView(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Panel(
            onTap: () => context.push('/account/security'),
            child: Row(children: [
              Avatar(me.name, url: me.json['avatarUrl'] as String?, radius: 30),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(me.name, style: text.titleMedium),
                  Text(contact, style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    if (me.isAdmin) Tag(t('Admin', 'অ্যাডমিন'), color: scheme.primaryContainer, textColor: scheme.onPrimaryContainer),
                    if (me.isTeacher) Tag(t('Instructor', 'ইন্সট্রাক্টর'), color: const Color(0xFFFFE3D2), textColor: const Color(0xFF8A3A10)),
                    if (me.isEmployer) Tag(t('Employer', 'নিয়োগদাতা')),
                    Tag(t('Learner', 'শিক্ষার্থী')),
                  ]),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded),
            ]),
          ),
        ),
        MenuGroup(title: t('Learning', 'লার্নিং'), items: [
          MenuItem(icon: Icons.play_circle_outline_rounded, title: t('My courses', 'আমার কোর্স'), onTap: () => context.go('/learning')),
          MenuItem(icon: Icons.event_available_outlined, title: t('My 1:1 sessions', 'আমার ১:১ সেশন'), onTap: () => context.go('/learning?tab=sessions')),
          MenuItem(icon: Icons.notifications_none_rounded, title: t('Notifications', 'নোটিফিকেশন'), onTap: () => context.push('/notifications')),
        ]),
        MenuGroup(title: t('Teaching', 'পড়ানো'), items: [
          if (me.isAdmin)
            MenuItem(icon: Icons.space_dashboard_outlined, title: t('Admin panel', 'অ্যাডমিন প্যানেল'), onTap: () => context.go('/admin'))
          else if (me.isTeacher) ...[
            MenuItem(icon: Icons.cast_for_education_outlined, title: t('Teacher dashboard', 'টিচার ড্যাশবোর্ড'), onTap: () => context.go('/teacher')),
            MenuItem(icon: Icons.account_balance_wallet_outlined, title: t('My earnings', 'আমার আয়'), onTap: () => context.push('/teacher/earnings')),
          ] else
            MenuItem(
              icon: Icons.school_outlined,
              title: t('Become an instructor', 'ইন্সট্রাক্টর হোন'),
              subtitle: t('Teach your skills and earn', 'আপনার স্কিল শেখান এবং আয় করুন'),
              color: Brand.orangeStrong,
              onTap: () => context.push('/teacher/apply'),
            ),
        ]),
        MenuGroup(title: t('Career', 'ক্যারিয়ার'), items: [
          MenuItem(
            icon: Icons.badge_outlined,
            title: t('Job profile & CV', 'জব প্রোফাইল ও CV'),
            subtitle: me.isSeeker ? t('Keep it up to date', 'আপডেট রাখুন') : t('Create one to apply for jobs', 'চাকরি খুঁজতে প্রোফাইল তৈরি করুন'),
            onTap: () => context.push('/jobs/profile'),
          ),
          MenuItem(icon: Icons.assignment_outlined, title: t('My applications', 'আমার আবেদন'), onTap: () => context.push('/jobs/applications')),
          MenuItem(
            icon: Icons.business_center_outlined,
            title: me.isEmployer ? t('My company & job posts', 'আমার কোম্পানি ও জব পোস্ট') : t('Post jobs as a company', 'কোম্পানি হিসেবে জব পোস্ট করুন'),
            onTap: () => context.push(me.isEmployer ? '/employer' : '/employer/setup'),
          ),
        ]),
        MenuGroup(title: t('Settings', 'সেটিংস'), items: [
          languageItem,
          MenuItem(
            icon: Icons.lock_outline_rounded,
            title: t('Login & security', 'লগইন ও নিরাপত্তা'),
            subtitle: t('Name, email/phone, password', 'নাম, ইমেইল/মোবাইল, পাসওয়ার্ড'),
            onTap: () => context.push('/account/security'),
          ),
        ]),
        about,
        MenuGroup(items: [
          MenuItem(icon: Icons.logout_rounded, title: t('Log out', 'লগআউট'), onTap: () => ref.read(authProvider.notifier).logout()),
          MenuItem(
            icon: Icons.delete_forever_outlined,
            title: t('Delete account', 'অ্যাকাউন্ট ডিলিট করুন'),
            color: scheme.error,
            onTap: () => _deleteAccount(context, ref),
          ),
        ]),
        Center(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Text('Tech.Dropout IT · v1.0', style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ),
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
      title: Text(t('Delete your account forever?', 'অ্যাকাউন্ট চিরতরে ডিলিট করবেন?')),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(t(
          'Your name, email/mobile, job profile, CV and portfolio will be erased. You will lose access to bought courses. This cannot be undone.',
          'আপনার নাম, ইমেইল/মোবাইল, জব প্রোফাইল, CV আর পোর্টফোলিও মুছে যাবে। কেনা কোর্সে আর ঢুকতে পারবেন না। এটা ফেরানো যাবে না।',
        )),
        const SizedBox(height: 12),
        TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: t('Enter your password to confirm', 'নিশ্চিত করতে পাসওয়ার্ড দিন'))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('No', 'না'))),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(t('Delete', 'ডিলিট করুন')),
        ),
      ],
    ),
  );
  if (ok != true || password.text.isEmpty) return;
  try {
    await ref.read(apiProvider).post('/auth/delete-account', {'password': password.text});
    await ref.read(authProvider.notifier).logout();
    if (context.mounted) showMessage(context, t('Account deleted', 'অ্যাকাউন্ট ডিলিট হয়েছে'));
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(t('Notifications', 'নোটিফিকেশন'))),
      body: AsyncView(
        value: list,
        onRetry: () => ref.invalidate(notificationsProvider),
        data: (items) => items.isEmpty
            ? EmptyState(t('You\'re all caught up.', 'নতুন কিছু নেই।'), title: t('No notifications', 'কোনো নোটিফিকেশন নেই'), icon: Icons.notifications_none_rounded)
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final n = items[i];
                  final unread = n['readAt'] == null;
                  return Card(
                    color: unread ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
                    child: ListTile(
                      leading: IconBadge(unread ? Icons.notifications_active_rounded : Icons.notifications_none_rounded, size: 38),
                      title: Text(n['title'] as String),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(n['body'] as String),
                        if (n['createdAt'] != null)
                          Text(DateFormat.yMMMd().add_jm().format(DateTime.parse(n['createdAt'] as String).toLocal()), style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
