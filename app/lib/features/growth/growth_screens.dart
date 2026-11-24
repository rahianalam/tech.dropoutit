import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/api.dart';
import '../../core/auth.dart';
import '../../core/checkout.dart';
import '../../core/config.dart';
import '../../core/format.dart';
import '../../core/i18n.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../home/home_screen.dart';
import '../teacher/instructor_screens.dart';

final referralProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(apiProvider).get('/me/referral'));

/// The affiliate dashboard. A 404 means the person has not joined yet (null).
final affiliateProvider = FutureProvider.autoDispose<Map<String, dynamic>?>((ref) async {
  try {
    return await ref.read(apiProvider).get<Map<String, dynamic>>('/affiliates/me');
  } on ApiError catch (e) {
    if (e.status == 404) return null;
    rethrow;
  }
});

final _date = DateFormat('d MMM y');

Future<void> _copy(BuildContext context, String text) async {
  await Clipboard.setData(ClipboardData(text: text));
  if (context.mounted) showMessage(context, t('Copied', 'কপি হয়েছে'));
}

Map<String, String> get _methods => {'bkash': 'bKash', 'nagad': 'Nagad', 'rocket': 'Rocket', 'bank': t('Bank', 'ব্যাংক')};

// ---------------------------------------------------------------- referral

/// Invite friends: 15 friends who buy a paid course give a 15-day pass to any course.
class ReferralScreen extends ConsumerWidget {
  const ReferralScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(referralProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: Text(t('Invite friends', 'বন্ধুদের ইনভাইট করুন'))),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(referralProvider),
        data: (r) {
          final target = r['target'] as int;
          final toward = (r['towardNext'] as int).clamp(0, target);
          final link = '$webUrl/#/register?ref=${r['code']}';
          final until = r['freePassUntil'] == null ? null : DateTime.parse(r['freePassUntil'] as String).toLocal();
          return ListView(padding: const EdgeInsets.all(16), children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(gradient: Brand.heroGradient, borderRadius: BorderRadius.circular(20)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.card_giftcard_rounded, color: Brand.cyan, size: 36),
                const SizedBox(height: 10),
                Text(
                  t('Invite $target friends who buy a paid course and get ${r['passDays']} days of any course free.',
                      '$target জন বন্ধু ইনভাইট করুন, তারা পেইড কোর্স কিনলে আপনি ${r['passDays']} দিন যেকোনো কোর্স ফ্রি করতে পারবেন।'),
                  style: text.titleMedium?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 16),
                Text(t('Your invite code', 'আপনার ইনভাইট কোড'), style: const TextStyle(color: Colors.white70)),
                const SizedBox(height: 4),
                Row(children: [
                  Text(r['code'] as String, style: text.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 2)),
                  const Spacer(),
                  IconButton(
                    tooltip: t('Copy code', 'কোড কপি'),
                    onPressed: () => _copy(context, r['code'] as String),
                    icon: const Icon(Icons.copy_rounded, color: Colors.white),
                  ),
                ]),
              ]),
            ),
            const SizedBox(height: 16),
            if (until != null)
              Panel(
                margin: const EdgeInsets.only(bottom: 16),
                child: Row(children: [
                  const IconBadge(Icons.workspace_premium_rounded, color: Brand.success),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(t('Your free pass is on until ${_date.format(until)}. Enroll in any paid course from its page.', 'আপনার ফ্রি পাস ${_date.format(until)} পর্যন্ত চালু। যেকোনো পেইড কোর্সের পেজ থেকে এনরোল করুন।')),
                  ),
                ]),
              ),
            Panel(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(t('Progress to the next pass', 'পরের পাসের অগ্রগতি'), style: text.titleSmall)),
                  Text('$toward / $target', style: text.titleSmall),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(value: target == 0 ? 0 : toward / target, minHeight: 10, color: Brand.orangeStrong, backgroundColor: Brand.line),
                ),
                const SizedBox(height: 10),
                Text(
                  t('${r['joined']} joined with your code · ${r['qualified']} bought a paid course', 'আপনার কোড দিয়ে ${r['joined']} জন যোগ দিয়েছে · ${r['qualified']} জন পেইড কোর্স কিনেছে'),
                  style: text.bodySmall,
                ),
              ]),
            ),
            const SizedBox(height: 16),
            CtaButton(icon: Icons.link_rounded, label: t('Copy invite link', 'ইনভাইট লিংক কপি করুন'), onPressed: () => _copy(context, link)),
            const SizedBox(height: 8),
            Text(t('Friends enter your code when they sign up, or open your link.', 'বন্ধুরা সাইন আপের সময় আপনার কোড দেবে, অথবা আপনার লিংক খুলবে।'), style: text.bodySmall, textAlign: TextAlign.center),
          ]);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- affiliate

Map<String, String> get _affStatus => {
      'UNPAID': t('Not active yet', 'এখনো চালু হয়নি'),
      'IN_REVIEW': t('In review', 'রিভিউতে আছে'),
      'ACTIVE': t('Active', 'চালু'),
      'REJECTED': t('Needs new pictures', 'নতুন ছবি দরকার'),
      'DEACTIVATED': t('Deactivated', 'বন্ধ'),
    };

class AffiliateDashboard extends ConsumerStatefulWidget {
  const AffiliateDashboard({super.key});
  @override
  ConsumerState<AffiliateDashboard> createState() => _AffiliateDashboardState();
}

class _AffiliateDashboardState extends ConsumerState<AffiliateDashboard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() => _busy = true);
    try {
      await fn();
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() => _run(() async {
        await ref.read(apiProvider).post('/affiliates/join');
        await ref.read(authProvider.notifier).reload();
        ref.invalidate(affiliateProvider);
      });

  Future<void> _pay() => _run(() async {
        final c = await ref.read(apiProvider).post<Map<String, dynamic>>('/affiliates/me/membership');
        if (!mounted) return;
        final paid = await payOrder(context, ref, c);
        ref.invalidate(affiliateProvider);
        if (paid && mounted) showMessage(context, t('Membership paid', 'মেম্বারশিপ ফি দেওয়া হয়েছে'));
      });

  Future<void> _payout(Map<String, dynamic> p) async {
    var method = p['payoutMethod'] as String? ?? 'bkash';
    final account = TextEditingController(text: p['payoutAccount'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(t('Payout account', 'পেআউট অ্যাকাউন্ট')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: method,
              items: [for (final e in _methods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => set(() => method = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: account,
              decoration: InputDecoration(labelText: method == 'bank' ? t('Bank, branch, account number, name', 'ব্যাংক, শাখা, অ্যাকাউন্ট নম্বর, নাম') : t('Mobile number', 'মোবাইল নম্বর')),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel', 'বাতিল'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Save', 'সেভ'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await ref.read(apiProvider).dio.put('/affiliates/me/payout', data: {'method': method, 'account': account.text.trim()});
      ref.invalidate(affiliateProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(affiliateProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Affiliate dashboard', 'অ্যাফিলিয়েট ড্যাশবোর্ড'))),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(affiliateProvider.future),
        child: AsyncView(
          value: data,
          onRetry: () => ref.invalidate(affiliateProvider),
          data: (d) => d == null ? _JoinView(busy: _busy, onJoin: _join) : _dashboard(context, d),
        ),
      ),
    );
  }

  Widget _dashboard(BuildContext context, Map<String, dynamic> d) {
    final text = Theme.of(context).textTheme;
    final p = d['profile'] as Map<String, dynamic>;
    final rules = d['rules'] as Map<String, dynamic>;
    final status = p['status'] as String;
    final active = status == 'ACTIVE';
    final paid = p['membershipPaidAt'] != null && status != 'DEACTIVATED';
    final docs = p['documentsSent'] == true;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(gradient: Brand.affiliateGradient, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.handshake_outlined, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(_affStatus[status] ?? status, style: text.titleMedium?.copyWith(color: Colors.white))),
            Tag(t('${bps(rules['commissionBps'])} per sale', 'প্রতি বিক্রিতে ${bps(rules['commissionBps'])}')),
          ]),
          const SizedBox(height: 14),
          Text(t('Your link code', 'আপনার লিংক কোড'), style: const TextStyle(color: Colors.white70)),
          Row(children: [
            Text(p['code'] as String, style: text.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800, letterSpacing: 2)),
            const Spacer(),
            IconButton(tooltip: t('Copy code', 'কোড কপি'), onPressed: () => _copy(context, p['code'] as String), icon: const Icon(Icons.copy_rounded, color: Colors.white)),
          ]),
        ]),
      ),
      const SizedBox(height: 16),
      if (!active) ...[
        if (status == 'DEACTIVATED')
          _Note(Icons.pause_circle_outline, t('Your account was switched off after ${rules['inactiveDays']} days without activity. Pay the membership again to switch it back on.',
              '${rules['inactiveDays']} দিন কোনো কাজ না থাকায় অ্যাকাউন্ট বন্ধ হয়েছে। আবার চালু করতে মেম্বারশিপ ফি দিন।')),
        if (status == 'REJECTED' && p['adminNote'] != null)
          _Note(Icons.error_outline, t('Admin: ${p['adminNote']}', 'অ্যাডমিন: ${p['adminNote']}')),
        _Step(
          n: 1,
          done: docs,
          title: t('Verify your identity', 'পরিচয় যাচাই করুন'),
          body: t('NID front and back, a clear photo and a live selfie.', 'NID-এর সামনে ও পেছনের ছবি, একটি পরিষ্কার ছবি আর লাইভ সেলফি।'),
          action: docs && status != 'REJECTED' ? null : (t('Start', 'শুরু করুন'), () async {
            await context.push('/affiliate/verify');
            ref.invalidate(affiliateProvider);
          }),
        ),
        _Step(
          n: 2,
          done: paid,
          title: t('Pay the membership fee: ${taka(rules['feePaisa'] as int)}', 'মেম্বারশিপ ফি দিন: ${taka(rules['feePaisa'] as int)}'),
          body: t('One-time. Your account stays on while you are active; after ${rules['inactiveDays']} idle days it is switched off.', 'এককালীন। সক্রিয় থাকলে অ্যাকাউন্ট চালু থাকে; ${rules['inactiveDays']} দিন নিষ্ক্রিয় থাকলে বন্ধ হয়ে যায়।'),
          action: paid ? null : (t('Pay now', 'এখনই দিন'), _busy ? null : _pay),
        ),
        _Step(
          n: 3,
          done: false,
          title: t('Admin approval', 'অ্যাডমিনের অনুমোদন'),
          body: status == 'IN_REVIEW'
              ? t('Your documents are being checked. You will get a notification.', 'আপনার কাগজপত্র যাচাই হচ্ছে। নোটিফিকেশন পাবেন।')
              : t('After steps 1 and 2 the admin checks your documents.', '১ আর ২ নম্বর ধাপের পর অ্যাডমিন কাগজপত্র যাচাই করবেন।'),
        ),
        const SizedBox(height: 8),
      ],
      if (active) ..._activeView(context, d),
    ]);
  }

  List<Widget> _activeView(BuildContext context, Map<String, dynamic> d) {
    final text = Theme.of(context).textTheme;
    final p = d['profile'] as Map<String, dynamic>;
    final totals = d['totals'] as Map<String, dynamic>;
    final money = d['money'] as Map<String, dynamic>;
    final rules = d['rules'] as Map<String, dynamic>;
    final perDay = (d['perDay'] as List).cast<Map<String, dynamic>>();
    return [
      Row(children: [
        Expanded(child: _Stat('${totals['clicks30']}', t('Clicks, 30 days', 'ক্লিক, ৩০ দিন'))),
        const SizedBox(width: 10),
        Expanded(child: _Stat('${totals['sales']}', t('Sales', 'বিক্রি'))),
        const SizedBox(width: 10),
        Expanded(child: _Stat('${totals['conversionPct']}%', t('Conversion', 'কনভার্সন'))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _Stat(taka(money['availablePaisa'] as int), t('Available', 'উত্তোলনযোগ্য'), strong: true)),
        const SizedBox(width: 10),
        Expanded(child: _Stat(taka(money['pendingPaisa'] as int), t('On hold', 'হোল্ডে'))),
        const SizedBox(width: 10),
        Expanded(child: _Stat(taka(money['paidPaisa'] as int), t('Received', 'পেয়েছেন'))),
      ]),
      const SizedBox(height: 6),
      Text(t('Earnings are released ${rules['holdDays']} days after a sale, then the admin sends them to your account.', 'বিক্রির ${rules['holdDays']} দিন পর আয় উত্তোলনযোগ্য হয়, তারপর অ্যাডমিন আপনার অ্যাকাউন্টে পাঠান।'), style: text.bodySmall),
      SectionHeader(t('Clicks per day', 'প্রতিদিনের ক্লিক'), padding: const EdgeInsets.fromLTRB(0, 20, 0, 8)),
      Panel(child: ClicksChart(perDay)),
      SectionHeader(t('Your course links', 'আপনার কোর্স লিংক'), subtitle: t('Share these. A sale through them earns you ${bps(rules['commissionBps'])}.', 'এগুলো শেয়ার করুন। এগুলো দিয়ে বিক্রি হলে ${bps(rules['commissionBps'])} পাবেন।'), padding: const EdgeInsets.fromLTRB(0, 20, 0, 8)),
      _CourseLinks(code: p['code'] as String),
      SectionHeader(t('Payout account', 'পেআউট অ্যাকাউন্ট'), padding: const EdgeInsets.fromLTRB(0, 20, 0, 8)),
      Card(
        child: ListTile(
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: Text(p['payoutMethod'] == null ? t('Add a payout account', 'পেআউট অ্যাকাউন্ট যোগ করুন') : '${_methods[p['payoutMethod']]}: ${p['payoutAccount']}'),
          trailing: const Icon(Icons.edit_outlined),
          onTap: () => _payout(p),
        ),
      ),
      SectionHeader(t('Recent sales', 'সাম্প্রতিক বিক্রি'), padding: const EdgeInsets.fromLTRB(0, 20, 0, 4)),
      if ((d['recent'] as List).isEmpty) Padding(padding: const EdgeInsets.all(8), child: Text(t('No sales yet. Share your links to start.', 'এখনো কোনো বিক্রি নেই। লিংক শেয়ার করে শুরু করুন।'))),
      for (final e in d['recent'] as List)
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(e['courseTitle'] as String? ?? t('Course', 'কোর্স'), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text('${_date.format(DateTime.parse(e['createdAt'] as String).toLocal())} · ${switch (e['status']) {
            'AVAILABLE' => t('Available', 'উত্তোলনযোগ্য'),
            'PAID' => t('Paid out', 'পেয়েছেন'),
            'VOID' => t('Refunded', 'ফেরত গেছে'),
            _ => t('On hold', 'হোল্ডে'),
          }}'),
          trailing: Text(taka(e['amountPaisa'] as int), style: text.titleSmall),
        ),
    ];
  }
}

class _JoinView extends ConsumerWidget {
  const _JoinView({required this.busy, required this.onJoin});
  final bool busy;
  final VoidCallback onJoin;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final rules = ref.watch(instructorRulesProvider).value;
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(gradient: Brand.affiliateGradient, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.handshake_outlined, color: Colors.white, size: 40),
          const SizedBox(height: 10),
          Text(t('Become an affiliate', 'অ্যাফিলিয়েট হোন'), style: text.headlineSmall?.copyWith(color: Colors.white)),
          const SizedBox(height: 6),
          Text(t('Share Tech.Dropout courses with your link and earn a commission on every sale.', 'নিজের লিংক দিয়ে Tech.Dropout-এর কোর্স শেয়ার করুন, প্রতিটি বিক্রিতে কমিশন পান।'),
              style: const TextStyle(color: Colors.white)),
        ]),
      ),
      const SizedBox(height: 16),
      for (final (icon, line) in [
        (Icons.percent_rounded, t('2% of the course price on every sale through your link', 'আপনার লিংক দিয়ে প্রতিটি বিক্রিতে কোর্সের দামের ২%')),
        (Icons.verified_user_outlined, t('Verification with your NID, a photo and a live selfie', 'NID, ছবি আর লাইভ সেলফি দিয়ে ভেরিফিকেশন')),
        (Icons.payments_outlined, t('A one-time membership fee (about \$5)', 'এককালীন মেম্বারশিপ ফি (প্রায় \$৫)')),
        (Icons.insights_outlined, t('Your own dashboard with clicks, sales and earnings', 'ক্লিক, বিক্রি আর আয়ের নিজস্ব ড্যাশবোর্ড')),
        (Icons.pause_circle_outline, t('Accounts idle for 6 months are switched off', '৬ মাস নিষ্ক্রিয় থাকলে অ্যাকাউন্ট বন্ধ হয়ে যায়')),
      ])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [Icon(icon, color: Brand.teal), const SizedBox(width: 12), Expanded(child: Text(line))]),
        ),
      if (rules == null) const SizedBox.shrink(),
      const SizedBox(height: 16),
      CtaButton(busy: busy, icon: Icons.arrow_forward_rounded, label: t('Join the affiliate program', 'অ্যাফিলিয়েট প্রোগ্রামে যোগ দিন'), onPressed: onJoin),
    ]);
  }
}

class _Note extends StatelessWidget {
  const _Note(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Panel(
        margin: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(icon, color: Brand.orangeStrong), const SizedBox(width: 10), Expanded(child: Text(text))]),
      );
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.done, required this.title, required this.body, this.action});
  final int n;
  final bool done;
  final String title;
  final String body;
  final (String, VoidCallback?)? action;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Panel(
      margin: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: done ? Brand.success : Brand.teal.withValues(alpha: 0.12),
          child: done ? const Icon(Icons.check_rounded, size: 18, color: Colors.white) : Text('$n', style: const TextStyle(fontWeight: FontWeight.w700, color: Brand.teal)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleSmall),
            const SizedBox(height: 2),
            Text(body, style: text.bodySmall),
            if (action != null) ...[
              const SizedBox(height: 8),
              FilledButton(onPressed: action!.$2, child: Text(action!.$1)),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.value, this.label, {this.strong = false});
  final String value;
  final String label;
  final bool strong;
  @override
  Widget build(BuildContext context) => Card(
        color: strong ? Theme.of(context).colorScheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(child: Text(value, style: Theme.of(context).textTheme.titleLarge)),
            Text(label, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
      );
}

/// Clicks per day for the last 30 days. One series, so the title names it and
/// there is no legend; long-press or hover a bar for its day and counts.
class ClicksChart extends StatelessWidget {
  const ClicksChart(this.days, {super.key});
  final List<Map<String, dynamic>> days;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final max = days.fold<int>(0, (m, d) => (d['clicks'] as int) > m ? d['clicks'] as int : m);
    final fmt = DateFormat('d MMM');
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(t('Most in a day: $max', 'এক দিনে সর্বোচ্চ: $max'), style: text.bodySmall),
      const SizedBox(height: 8),
      SizedBox(
        height: 110,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final d in days)
            Expanded(
              child: Tooltip(
                message: '${fmt.format(DateTime.parse(d['day'] as String))}: ${t('${d['clicks']} clicks, ${d['sales']} sales', '${d['clicks']} ক্লিক, ${d['sales']} বিক্রি')}',
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  height: max == 0 ? 2 : 2 + 108 * (d['clicks'] as int) / max,
                  decoration: BoxDecoration(
                    color: (d['clicks'] as int) == 0 ? Brand.line : Brand.teal,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
              ),
            ),
        ]),
      ),
      const Divider(height: 1),
      const SizedBox(height: 4),
      Row(children: [
        Text(fmt.format(DateTime.parse(days.first['day'] as String)), style: text.labelSmall),
        const Spacer(),
        Text(t('Today', 'আজ'), style: text.labelSmall),
      ]),
    ]);
  }
}

/// Paid courses with a copy button for each affiliate link.
class _CourseLinks extends ConsumerWidget {
  const _CourseLinks({required this.code});
  final String code;
  static const _paid = CourseFilter(free: false, pageSize: 20);
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courses = ref.watch(coursesProvider(_paid));
    return courses.when(
      loading: () => const Skeleton(height: 120),
      error: (e, _) => Text(e.toString()),
      data: (list) => Column(children: [
        Card(
          child: ListTile(
            leading: const Icon(Icons.home_outlined),
            title: Text(t('Any course (home page)', 'যেকোনো কোর্স (হোম পেজ)')),
            subtitle: Text(t('Visitors who buy within the visit earn you a commission', 'এই লিংক থেকে কেউ কোর্স কিনলে কমিশন পাবেন'), maxLines: 2),
            trailing: const Icon(Icons.copy_rounded),
            onTap: () => _copy(context, '$webUrl/#/?ref=$code'),
          ),
        ),
        for (final c in list)
          Card(
            child: ListTile(
              title: Text(c['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis),
              subtitle: Text(taka(c['pricePaisa'] as int)),
              trailing: const Icon(Icons.copy_rounded),
              onTap: () => _copy(context, '$webUrl/#/courses/${c['id']}?ref=$code'),
            ),
          ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- verification

class AffiliateVerifyScreen extends ConsumerStatefulWidget {
  const AffiliateVerifyScreen({super.key});
  @override
  ConsumerState<AffiliateVerifyScreen> createState() => _AffiliateVerifyScreenState();
}

class _AffiliateVerifyScreenState extends ConsumerState<AffiliateVerifyScreen> {
  final _nid = TextEditingController();
  final _ids = <String, String>{};
  final _bytes = <String, Uint8List>{};
  String? _uploading;
  bool _busy = false;

  Future<void> _pick(String slot, ImageSource source) async {
    final file = await ImagePicker().pickImage(
      source: source,
      preferredCameraDevice: slot == 'selfie' ? CameraDevice.front : CameraDevice.rear,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null) return;
    setState(() => _uploading = slot);
    try {
      final bytes = await file.readAsBytes();
      final mime = file.mimeType ?? (file.name.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg');
      final form = FormData.fromMap({
        'file': MultipartFile.fromBytes(bytes, filename: file.name.isEmpty ? '$slot.jpg' : file.name, contentType: DioMediaType.parse(mime)),
      });
      final res = await ref.read(apiProvider).dio.post('/uploads', data: form, queryParameters: {'kind': 'KYC'});
      setState(() {
        _ids[slot] = (res.data as Map)['id'] as String;
        _bytes[slot] = bytes;
      });
    } on DioException catch (e) {
      if (mounted) showMessage(context, ApiError.from(e));
    } finally {
      if (mounted) setState(() => _uploading = null);
    }
  }

  Future<void> _submit() async {
    final nid = _nid.text.trim();
    if (!RegExp(r'^(\d{10}|\d{13}|\d{17})$').hasMatch(nid)) {
      showMessage(context, t('NID number must have 10, 13 or 17 digits', 'NID নম্বর ১০, ১৩ বা ১৭ সংখ্যার হতে হবে'));
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(apiProvider).dio.put('/affiliates/me/verification', data: {
        'nidNumber': nid,
        'nidFrontId': _ids['front'],
        'nidBackId': _ids['back'],
        'photoId': _ids['photo'],
        'selfieId': _ids['selfie'],
      });
      ref.invalidate(affiliateProvider);
      if (mounted) {
        showMessage(context, t('Sent for review', 'রিভিউর জন্য পাঠানো হয়েছে'));
        context.pop();
      }
    } on DioException catch (e) {
      if (mounted) showMessage(context, ApiError.from(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final slots = [
      ('front', Icons.credit_card_rounded, t('NID front', 'NID-এর সামনে'), false),
      ('back', Icons.credit_card_outlined, t('NID back', 'NID-এর পেছনে'), false),
      ('photo', Icons.portrait_rounded, t('Your photo', 'আপনার ছবি'), false),
      ('selfie', Icons.face_retouching_natural_rounded, t('Live selfie', 'লাইভ সেলফি'), true),
    ];
    final ready = _ids.length == 4 && _uploading == null;
    return Scaffold(
      appBar: AppBar(title: Text(t('Verify your identity', 'পরিচয় যাচাই'))),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text(t('Your documents are private. Only the admin sees them, to check that you are a real person.', 'আপনার কাগজপত্র গোপন থাকবে। শুধু অ্যাডমিন দেখবেন, আপনি আসল মানুষ কি না যাচাই করতে।'), style: text.bodySmall),
        const SizedBox(height: 16),
        TextField(
          controller: _nid,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: t('NID number', 'NID নম্বর'), prefixIcon: const Icon(Icons.badge_outlined)),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 0.9,
          children: [
            for (final (slot, icon, label, cameraOnly) in slots)
              Panel(
                padding: const EdgeInsets.all(10),
                onTap: _uploading != null ? null : () => _choose(slot, cameraOnly),
                child: Column(children: [
                  Expanded(
                    child: _uploading == slot
                        ? const Center(child: CircularProgressIndicator())
                        : _bytes[slot] != null
                            ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(_bytes[slot]!, fit: BoxFit.cover, width: double.infinity))
                            : Center(child: Icon(icon, size: 44, color: Brand.teal)),
                  ),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    if (_ids[slot] != null) const Icon(Icons.check_circle_rounded, color: Brand.success, size: 18),
                    if (_ids[slot] != null) const SizedBox(width: 4),
                    Flexible(child: Text(label, style: text.titleSmall, overflow: TextOverflow.ellipsis)),
                  ]),
                  if (cameraOnly) Text(t('Camera only', 'শুধু ক্যামেরা'), style: text.labelSmall),
                ]),
              ),
          ],
        ),
        const SizedBox(height: 24),
        CtaButton(busy: _busy, label: t('Send for review', 'রিভিউর জন্য পাঠান'), onPressed: ready ? _submit : null),
      ]),
    );
  }

  Future<void> _choose(String slot, bool cameraOnly) async {
    if (cameraOnly) return _pick(slot, ImageSource.camera);
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: Text(t('Take a picture', 'ছবি তুলুন')), onTap: () => Navigator.pop(ctx, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: Text(t('Choose from gallery', 'গ্যালারি থেকে নিন')), onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
        ]),
      ),
    );
    if (source != null) await _pick(slot, source);
  }
}

// ---------------------------------------------------------------- admin

final adminAffiliatesProvider = FutureProvider.autoDispose.family<List<dynamic>, String?>(
    (ref, status) => ref.read(apiProvider).get('/admin/affiliates', query: {'status': ?status}));
final adminAffiliateProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, id) => ref.read(apiProvider).get('/admin/affiliates/$id'));

class AdminAffiliatesScreen extends ConsumerStatefulWidget {
  const AdminAffiliatesScreen({super.key});
  @override
  ConsumerState<AdminAffiliatesScreen> createState() => _AdminAffiliatesScreenState();
}

class _AdminAffiliatesScreenState extends ConsumerState<AdminAffiliatesScreen> {
  String? _status = 'IN_REVIEW';
  @override
  Widget build(BuildContext context) {
    final list = ref.watch(adminAffiliatesProvider(_status));
    return Scaffold(
      appBar: AppBar(title: Text(t('Affiliates', 'অ্যাফিলিয়েট'))),
      body: Column(children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(children: [
            for (final s in [null, 'IN_REVIEW', 'ACTIVE', 'UNPAID', 'REJECTED', 'DEACTIVATED'])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(label: Text(s == null ? t('All', 'সব') : _affStatus[s]!), selected: _status == s, onSelected: (_) => setState(() => _status = s)),
              ),
          ]),
        ),
        Expanded(
          child: AsyncView(
            value: list,
            onRetry: () => ref.invalidate(adminAffiliatesProvider(_status)),
            data: (items) => items.isEmpty
                ? EmptyState(t('Nobody here', 'কেউ নেই'), icon: Icons.handshake_outlined)
                : ListView.builder(
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final a = items[i] as Map<String, dynamic>;
                      final u = a['user'] as Map<String, dynamic>;
                      return ListTile(
                        leading: Avatar(u['name'] as String),
                        title: Text(u['name'] as String),
                        subtitle: Text('${u['email'] ?? u['phone'] ?? ''} · ${a['code']}'),
                        trailing: Tag(_affStatus[a['status']] ?? a['status'] as String),
                        onTap: () async {
                          await context.push('/admin/affiliates/${a['userId']}');
                          ref.invalidate(adminAffiliatesProvider(_status));
                        },
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }
}

class AdminAffiliateScreen extends ConsumerWidget {
  const AdminAffiliateScreen(this.id, {super.key});
  final String id;

  Future<void> _act(BuildContext context, WidgetRef ref, Future<Object?> Function() fn, String done) async {
    try {
      await fn();
      ref.invalidate(adminAffiliateProvider(id));
      if (context.mounted) showMessage(context, done);
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(adminAffiliateProvider(id));
    final api = ref.read(apiProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Affiliate', 'অ্যাফিলিয়েট'))),
      body: AsyncView(
        value: data,
        onRetry: () => ref.invalidate(adminAffiliateProvider(id)),
        data: (a) {
          final u = a['user'] as Map<String, dynamic>;
          final docs = a['documents'] as Map<String, dynamic>;
          final text = Theme.of(context).textTheme;
          return ListView(padding: const EdgeInsets.all(16), children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Avatar(u['name'] as String),
              title: Text(u['name'] as String, style: text.titleMedium),
              subtitle: Text([u['email'], u['phone']].whereType<String>().join(' · ')),
              trailing: Tag(_affStatus[a['status']] ?? a['status'] as String),
            ),
            Text(t('Code: ${a['code']}', 'কোড: ${a['code']}')),
            Text(t('NID: ${a['nidNumber'] ?? 'not sent'}', 'NID: ${a['nidNumber'] ?? 'পাঠায়নি'}')),
            Text(a['membershipPaidAt'] == null
                ? t('Membership fee: not paid', 'মেম্বারশিপ ফি: দেয়নি')
                : t('Membership paid ${_date.format(DateTime.parse(a['membershipPaidAt'] as String).toLocal())}', 'মেম্বারশিপ ফি দিয়েছে ${_date.format(DateTime.parse(a['membershipPaidAt'] as String).toLocal())}')),
            if (a['adminNote'] != null) Text(t('Note: ${a['adminNote']}', 'নোট: ${a['adminNote']}')),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              children: [
                for (final (key, label) in [
                  ('nidFront', t('NID front', 'NID সামনে')),
                  ('nidBack', t('NID back', 'NID পেছনে')),
                  ('photo', t('Photo', 'ছবি')),
                  ('selfie', t('Live selfie', 'লাইভ সেলফি')),
                ])
                  Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: docs[key] == null
                            ? Container(color: Brand.line, child: const Icon(Icons.image_not_supported_outlined))
                            : InkWell(
                                onTap: () => showDialog<void>(context: context, builder: (_) => Dialog(child: InteractiveViewer(child: Image.network(docs[key] as String)))),
                                child: Image.network(docs[key] as String, fit: BoxFit.cover, errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined)),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(label, style: text.labelMedium, textAlign: TextAlign.center),
                  ]),
              ],
            ),
            const SizedBox(height: 16),
            if (a['status'] != 'ACTIVE')
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final note = TextEditingController();
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(t('Reject', 'বাতিল করুন')),
                          content: TextField(controller: note, maxLines: 3, decoration: InputDecoration(labelText: t('What should they fix?', 'কী ঠিক করতে হবে?'))),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel', 'বাতিল'))),
                            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Send', 'পাঠান'))),
                          ],
                        ),
                      );
                      if (ok == true && context.mounted) {
                        await _act(context, ref, () => api.post('/admin/affiliates/$id/review', {'decision': 'REJECTED', 'note': note.text.trim()}), t('Rejected', 'বাতিল হয়েছে'));
                      }
                    },
                    child: Text(t('Reject', 'বাতিল')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _act(context, ref, () => api.post('/admin/affiliates/$id/review', {'decision': 'APPROVED'}), t('Approved', 'অনুমোদন হয়েছে')),
                    child: Text(t('Approve', 'অনুমোদন')),
                  ),
                ),
              ]),
            const SizedBox(height: 16),
            Panel(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(t('To pay: ${taka(a['availablePaisa'] as int)}', 'পাঠাতে হবে: ${taka(a['availablePaisa'] as int)}'), style: text.titleSmall),
                    Text(a['payoutMethod'] == null ? t('No payout account yet', 'পেআউট অ্যাকাউন্ট নেই') : '${_methods[a['payoutMethod']]}: ${a['payoutAccount']}', style: text.bodySmall),
                  ]),
                ),
                FilledButton.tonal(
                  onPressed: (a['availablePaisa'] as int) <= 0 ? null : () => _act(context, ref, () => api.post('/admin/affiliates/$id/paid'), t('Marked as paid', 'পাঠানো হয়েছে চিহ্নিত')),
                  child: Text(t('Mark paid', 'পাঠানো হয়েছে')),
                ),
              ]),
            ),
          ]);
        },
      ),
    );
  }
}
