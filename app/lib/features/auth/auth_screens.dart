import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.register = false});
  final bool register;
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _show = false;

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final auth = ref.read(authProvider.notifier);
      if (widget.register) {
        await auth.register(name: _name.text.trim(), identifier: _id.text.trim(), password: _password.text);
      } else {
        await auth.login(_id.text.trim(), _password.text);
      }
      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final reg = widget.register;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: Brand.heroGradient,
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: Column(children: [
                  Row(children: [
                    IconButton(
                      onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                      icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                    ),
                    const Spacer(),
                    const LangToggle(onDark: true),
                  ]),
                  const SizedBox(height: 8),
                  const BrandMark(size: 72, color: Brand.cyan),
                  const SizedBox(height: 10),
                  const BrandWordmark(size: 24, color: Brand.cyan, showMark: false),
                  const SizedBox(height: 8),
                  Text(
                    reg ? t('Create your free account', 'ফ্রি অ্যাকাউন্ট খুলুন') : t('Welcome back! Let\'s keep learning.', 'আবার স্বাগতম! চলুন শেখা চালিয়ে যাই।'),
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(reg ? t('Sign up', 'রেজিস্টার') : t('Log in', 'লগইন'), style: text.headlineSmall),
                  const SizedBox(height: 20),
                  if (reg) ...[
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: t('Your name', 'আপনার নাম'), prefixIcon: const Icon(Icons.person_outline_rounded)),
                      validator: (v) => (v ?? '').trim().length < 2 ? t('Enter your name', 'নাম লিখুন') : null,
                    ),
                    const SizedBox(height: 14),
                  ],
                  TextFormField(
                    controller: _id,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: t('Email or mobile number', 'ইমেইল অথবা মোবাইল নম্বর'),
                      prefixIcon: const Icon(Icons.alternate_email_rounded),
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty ? t('Enter your email or mobile', 'ইমেইল বা মোবাইল লিখুন') : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    obscureText: !_show,
                    decoration: InputDecoration(
                      labelText: t('Password', 'পাসওয়ার্ড'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _show = !_show),
                        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      ),
                    ),
                    validator: (v) => (v ?? '').length < 8 ? t('At least 8 characters', 'কমপক্ষে ৮ অক্ষর') : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  CtaButton(busy: _busy, label: reg ? t('Create account', 'অ্যাকাউন্ট খুলুন') : t('Log in', 'লগইন'), onPressed: _submit),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.go(reg ? '/login' : '/register'),
                    child: Text(reg ? t('Already have an account? Log in', 'আগে থেকে অ্যাকাউন্ট আছে? লগইন') : t('New here? Create an account', 'নতুন? অ্যাকাউন্ট খুলুন')),
                  ),
                  TextButton(onPressed: () => context.go('/'), child: Text(t('Browse courses without logging in', 'লগইন ছাড়া কোর্স দেখুন'))),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
