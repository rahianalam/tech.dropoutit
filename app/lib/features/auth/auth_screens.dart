import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key, this.register = false, this.as, this.ref});
  final bool register;

  /// 'teacher' or 'affiliate' opens that version of the screen.
  final String? as;

  /// A friend's invite code from a referral link.
  final String? ref;
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _id = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  late final _ref = TextEditingController(text: widget.ref ?? '');
  bool _show = false;
  late String _role = _roleOf(widget.as);
  bool get _teacher => _role == 'teacher';
  bool get _affiliate => _role == 'affiliate';

  static String _roleOf(String? as) => as == 'teacher' || as == 'affiliate' ? as! : 'student';

  @override
  void didUpdateWidget(LoginScreen old) {
    super.didUpdateWidget(old);
    if (old.as != widget.as) _role = _roleOf(widget.as);
    if (old.ref != widget.ref && widget.ref != null) _ref.text = widget.ref!;
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final auth = ref.read(authProvider.notifier);
      if (widget.register) {
        await auth.register(name: _name.text.trim(), identifier: _id.text.trim(), password: _password.text, ref: _role == 'student' ? _ref.text.trim().toUpperCase() : null);
      } else {
        await auth.login(_id.text.trim(), _password.text);
      }
      // The router sends the user on: back to the page that asked for login, the
      // instructor dashboard, or the teacher application for a new instructor.
      if (mounted && _teacher) context.go('/teacher');
      if (mounted && _affiliate) context.go('/affiliate');
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
            decoration: BoxDecoration(
              gradient: _teacher ? Brand.teachGradient : (_affiliate ? Brand.affiliateGradient : Brand.heroGradient),
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
                  const SizedBox(height: 4),
                  BrandMark(size: 64, color: _role == 'student' ? Brand.cyan : Colors.white),
                  const SizedBox(height: 8),
                  BrandWordmark(size: 24, color: _role == 'student' ? Brand.cyan : Colors.white, showMark: false),
                  const SizedBox(height: 18),
                  _RolePicker(role: _role, onChanged: (v) => setState(() => _role = v)),
                  const SizedBox(height: 14),
                  Text(
                    _teacher
                        ? (reg ? t('Teach on Tech.Dropout and earn', 'Tech.Dropout-এ পড়ান, আয় করুন') : t('Welcome back, instructor!', 'আবার স্বাগতম, ইন্সট্রাক্টর!'))
                        : _affiliate
                        ? (reg ? t('Share courses, earn a commission on every sale', 'কোর্স শেয়ার করুন, প্রতিটি বিক্রিতে কমিশন পান') : t('Welcome back, partner!', 'আবার স্বাগতম, পার্টনার!'))
                        : (reg ? t('Create your free account', 'ফ্রি অ্যাকাউন্ট খুলুন') : t('Welcome back! Let\'s keep learning.', 'আবার স্বাগতম! চলুন শেখা চালিয়ে যাই।')),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
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
                  Text(
                    _teacher
                        ? (reg ? t('Instructor sign up', 'ইন্সট্রাক্টর রেজিস্ট্রেশন') : t('Instructor log in', 'ইন্সট্রাক্টর লগইন'))
                        : _affiliate
                        ? (reg ? t('Affiliate sign up', 'অ্যাফিলিয়েট রেজিস্ট্রেশন') : t('Affiliate log in', 'অ্যাফিলিয়েট লগইন'))
                        : (reg ? t('Student sign up', 'স্টুডেন্ট রেজিস্ট্রেশন') : t('Student log in', 'স্টুডেন্ট লগইন')),
                    style: text.headlineSmall,
                  ),
                  if (_teacher && reg) ...[const SizedBox(height: 14), const _TeacherSteps()],
                  if (_affiliate && reg) ...[const SizedBox(height: 14), const _AffiliateSteps()],
                  const SizedBox(height: 20),
                  if (reg) ...[
                    TextFormField(
                      controller: _name,
                      textInputAction: TextInputAction.next,
                      decoration: InputDecoration(labelText: t('Your name', 'আপনার নাম'), hintText: t('e.g. Anika Rahman', 'যেমন: আনিকা রহমান'), prefixIcon: const Icon(Icons.person_outline_rounded)),
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
                      hintText: t('you@example.com', 'you@example.com'),
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
                      hintText: reg ? t('At least 8 characters', 'কমপক্ষে ৮ অক্ষর') : t('Enter your password', 'পাসওয়ার্ড লিখুন'),
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => _show = !_show),
                        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      ),
                    ),
                    validator: (v) => (v ?? '').length < 8 ? t('At least 8 characters', 'কমপক্ষে ৮ অক্ষর') : null,
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (reg && _role == 'student') ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _ref,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: t('Invite code (optional)', 'ইনভাইট কোড (ঐচ্ছিক)'),
                        hintText: t('From a friend, e.g. AB12CD', 'বন্ধুর দেওয়া কোড, যেমন: AB12CD'),
                        prefixIcon: const Icon(Icons.card_giftcard_rounded),
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  CtaButton(
                    busy: _busy,
                    label: reg
                        ? (_teacher
                            ? t('Continue to instructor application', 'ইন্সট্রাক্টর আবেদনে যান')
                            : _affiliate
                                ? t('Continue to affiliate setup', 'অ্যাফিলিয়েট সেটআপে যান')
                                : t('Create account', 'অ্যাকাউন্ট খুলুন'))
                        : t('Log in', 'লগইন'),
                    onPressed: _submit,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => context.pushReplacement(Uri(path: reg ? '/login' : '/register', queryParameters: {if (_role != 'student') 'as': _role}).toString()),
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


/// Student / Instructor / Affiliate switch at the top of login and sign up.
class _RolePicker extends StatelessWidget {
  const _RolePicker({required this.role, required this.onChanged});
  final String role;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    Widget seg(String value, IconData icon, String label, Color color) {
      final on = role == value;
      return Expanded(
        child: Semantics(
          button: true,
          selected: on,
          child: GestureDetector(
            onTap: () => onChanged(value),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: on ? Colors.white : Colors.transparent, borderRadius: BorderRadius.circular(24)),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 17, color: on ? color : Colors.white),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? color : Colors.white)),
                ),
              ]),
            ),
          ),
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(28)),
      child: Row(children: [
        seg('student', Icons.school_outlined, t('Student', 'স্টুডেন্ট'), Brand.teal),
        seg('teacher', Icons.cast_for_education_outlined, t('Instructor', 'ইন্সট্রাক্টর'), Brand.orangeStrong),
        seg('affiliate', Icons.handshake_outlined, t('Affiliate', 'অ্যাফিলিয়েট'), const Color(0xFF1E6A73)),
      ]),
    );
  }
}

/// What an affiliate does after signing up.
class _AffiliateSteps extends StatelessWidget {
  const _AffiliateSteps();
  @override
  Widget build(BuildContext context) {
    final steps = [
      t('Create your account', 'অ্যাকাউন্ট খুলুন'),
      t('Verify with your NID, a photo and a live selfie', 'NID, ছবি আর লাইভ সেলফি দিয়ে ভেরিফাই করুন'),
      t('Pay the membership fee; the admin approves you', 'মেম্বারশিপ ফি দিন, অ্যাডমিন অনুমোদন দেবেন'),
      t('Share course links and earn on every sale', 'কোর্সের লিংক শেয়ার করুন, প্রতিটি বিক্রিতে আয় করুন'),
    ];
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, s) in steps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              CircleAvatar(radius: 11, backgroundColor: Brand.teal.withValues(alpha: 0.15), child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.teal))),
              const SizedBox(width: 10),
              Expanded(child: Text(s)),
            ]),
          ),
      ]),
    );
  }
}

/// What happens after an instructor signs up.
class _TeacherSteps extends StatelessWidget {
  const _TeacherSteps();
  @override
  Widget build(BuildContext context) {
    final steps = [
      t('Create your account', 'অ্যাকাউন্ট খুলুন'),
      t('Read and accept the instructor rules', 'ইন্সট্রাক্টর নিয়মগুলো পড়ে রাজি হন'),
      t('Send your portfolio; the admin reviews it', 'পোর্টফোলিও পাঠান, অ্যাডমিন রিভিউ করবেন'),
      t('Once approved, upload courses and take 1:1 bookings', 'অনুমোদনের পর কোর্স আপলোড আর ১:১ বুকিং নিন'),
    ];
    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final (i, s) in steps.indexed)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              CircleAvatar(radius: 11, backgroundColor: Brand.orange.withValues(alpha: 0.18), child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Brand.orangeStrong))),
              const SizedBox(width: 10),
              Expanded(child: Text(s)),
            ]),
          ),
      ]),
    );
  }
}
