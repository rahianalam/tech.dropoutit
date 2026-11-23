import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _form,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text('Tech.Dropout', style: Theme.of(context).textTheme.headlineMedium, textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(reg ? 'নতুন অ্যাকাউন্ট খুলুন' : 'আপনার অ্যাকাউন্টে লগইন করুন', textAlign: TextAlign.center),
                  const SizedBox(height: 32),
                  if (reg) ...[
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'আপনার নাম'),
                      validator: (v) => (v ?? '').trim().length < 2 ? 'নাম লিখুন' : null,
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _id,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'ইমেইল অথবা মোবাইল নম্বর'),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'ইমেইল বা মোবাইল লিখুন' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'পাসওয়ার্ড'),
                    validator: (v) => (v ?? '').length < 8 ? 'কমপক্ষে ৮ অক্ষর' : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy ? null : _submit,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: _busy
                          ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : Text(reg ? 'রেজিস্টার' : 'লগইন'),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go(reg ? '/login' : '/register'),
                    child: Text(reg ? 'আগে থেকে অ্যাকাউন্ট আছে? লগইন' : 'অ্যাকাউন্ট নেই? রেজিস্টার করুন'),
                  ),
                  TextButton(onPressed: () => context.go('/'), child: const Text('লগইন ছাড়া কোর্স দেখুন')),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
