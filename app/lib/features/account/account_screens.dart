import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/i18n.dart';
import '../../core/widgets.dart';

/// Change name, login email/phone and password. For the admin this is how the
/// admin login ID and password are changed from inside the app.
class AccountSecurityScreen extends ConsumerStatefulWidget {
  const AccountSecurityScreen({super.key});
  @override
  ConsumerState<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends ConsumerState<AccountSecurityScreen> {
  late final Me _me = ref.read(authProvider).me!;
  late final _name = TextEditingController(text: _me.name);
  late final _email = TextEditingController(text: _me.json['email'] as String? ?? '');
  late final _phone = TextEditingController(text: _me.json['phone'] as String? ?? '');
  final _loginPassword = TextEditingController();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _busy;

  Future<void> _run(String key, Future<void> Function() fn, String done) async {
    setState(() => _busy = key);
    try {
      await fn();
      await ref.read(authProvider.notifier).reload();
      if (mounted) showMessage(context, done);
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _saveName() => _run('name', () async {
        await ref.read(apiProvider).patch('/auth/me', {'name': _name.text.trim()});
      }, t('Name saved', 'নাম সেভ হয়েছে'));

  Future<void> _saveLogin() async {
    final email = _email.text.trim();
    final phone = _phone.text.trim();
    final emailChanged = email.isNotEmpty && email != (_me.json['email'] ?? '');
    final phoneChanged = phone.isNotEmpty && phone != (_me.json['phone'] ?? '');
    if (!emailChanged && !phoneChanged) return showMessage(context, t('Nothing changed', 'কিছু বদলায়নি'));
    if (_loginPassword.text.isEmpty) return showMessage(context, t('Enter your current password', 'বর্তমান পাসওয়ার্ড দিন'));
    await _run('login', () async {
      await ref.read(apiProvider).post('/auth/change-login', {
        'password': _loginPassword.text,
        if (emailChanged) 'email': email,
        if (phoneChanged) 'phone': phone,
      });
      _loginPassword.clear();
    }, t('Login updated. Use the new email/phone next time you log in.', 'লগইন আপডেট হয়েছে। এরপর নতুন ইমেইল/মোবাইল দিয়ে লগইন করবেন।'));
  }

  Future<void> _savePassword() async {
    if (_next.text.length < 8) return showMessage(context, t('New password needs at least 8 characters', 'নতুন পাসওয়ার্ড কমপক্ষে ৮ অক্ষর'));
    if (_next.text != _again.text) return showMessage(context, t('The two new passwords don\'t match', 'দুইবার দেওয়া নতুন পাসওয়ার্ড মেলেনি'));
    await _run('password', () async {
      final api = ref.read(apiProvider);
      final tokens = await api.post<Map<String, dynamic>>('/auth/change-password', {'currentPassword': _current.text, 'newPassword': _next.text});
      await api.saveTokens(tokens);
      _current.clear();
      _next.clear();
      _again.clear();
    }, t('Password changed. Other devices were logged out.', 'পাসওয়ার্ড বদলেছে। অন্য সব ডিভাইস থেকে লগআউট হয়েছে।'));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget save(String key, VoidCallback onTap) => Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _busy == null ? onTap : null,
            child: _busy == key ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : Text(t('Save', 'সেভ')),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(t('Login & security', 'লগইন ও নিরাপত্তা'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('Profile', 'প্রোফাইল'), style: text.titleMedium),
            const SizedBox(height: 12),
            TextField(controller: _name, decoration: InputDecoration(labelText: t('Full name', 'পুরো নাম'))),
            const SizedBox(height: 12),
            save('name', _saveName),
          ]),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('Login ID (email or mobile)', 'লগইন আইডি (ইমেইল বা মোবাইল)'), style: text.titleMedium),
            const SizedBox(height: 4),
            Text(t('You log in with either of these.', 'এর যেকোনো একটি দিয়ে লগইন করবেন।'), style: text.bodySmall),
            const SizedBox(height: 12),
            TextField(controller: _email, keyboardType: TextInputType.emailAddress, decoration: InputDecoration(labelText: t('Email', 'ইমেইল'))),
            const SizedBox(height: 12),
            TextField(controller: _phone, keyboardType: TextInputType.phone, decoration: InputDecoration(labelText: t('Mobile (01XXXXXXXXX)', 'মোবাইল (01XXXXXXXXX)'))),
            const SizedBox(height: 12),
            TextField(controller: _loginPassword, obscureText: true, decoration: InputDecoration(labelText: t('Current password (to confirm)', 'বর্তমান পাসওয়ার্ড (নিশ্চিত করতে)'))),
            const SizedBox(height: 12),
            save('login', _saveLogin),
          ]),
        ),
        const SizedBox(height: 16),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(t('Change password', 'পাসওয়ার্ড বদলান'), style: text.titleMedium),
            const SizedBox(height: 12),
            TextField(controller: _current, obscureText: true, decoration: InputDecoration(labelText: t('Current password', 'বর্তমান পাসওয়ার্ড'))),
            const SizedBox(height: 12),
            TextField(controller: _next, obscureText: true, decoration: InputDecoration(labelText: t('New password (8+ characters)', 'নতুন পাসওয়ার্ড (৮+ অক্ষর)'))),
            const SizedBox(height: 12),
            TextField(controller: _again, obscureText: true, decoration: InputDecoration(labelText: t('New password again', 'নতুন পাসওয়ার্ড আবার'))),
            const SizedBox(height: 12),
            save('password', _savePassword),
          ]),
        ),
      ]),
    );
  }
}
