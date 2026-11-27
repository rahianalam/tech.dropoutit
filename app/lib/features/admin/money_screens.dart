import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/i18n.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';

final payoutsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/admin/payouts'));
final revenueProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(apiProvider).get('/admin/revenue'));

Map<String, String> get _methods => {'bkash': 'bKash', 'nagad': 'Nagad', 'rocket': 'Rocket', 'bank': t('Bank', 'ব্যাংক')};
Map<String, String> get _status => {'DRAFT': t('Draft', 'খসড়া'), 'APPROVED': t('Approved', 'অনুমোদিত'), 'PAID': t('Sent', 'পাঠানো হয়েছে')};

/// Draft → approve → send money (bKash/Nagad/bank) → record the reference.
class PayoutsScreen extends ConsumerWidget {
  const PayoutsScreen({super.key});

  Future<void> _run(BuildContext context, WidgetRef ref, Future<Object?> Function() fn, String done) async {
    try {
      await fn();
      ref.invalidate(payoutsProvider);
      ref.invalidate(revenueProvider);
      if (context.mounted) showSuccess(context, done);
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payouts = ref.watch(payoutsProvider);
    final revenue = ref.watch(revenueProvider).value;
    final api = ref.read(apiProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Teacher payouts', 'টিচার পেআউট'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _run(context, ref, () => api.post('/admin/payouts/generate'), t('Payout drafts created', 'পেআউট খসড়া তৈরি হয়েছে')),
        icon: const Icon(Icons.playlist_add),
        label: Text(t('Create payouts now', 'এখন পেআউট তৈরি')),
      ),
      body: AsyncView(
        value: payouts,
        onRetry: () => ref.invalidate(payoutsProvider),
        data: (list) => ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
          if (revenue != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t('Money overview', 'টাকার হিসাব'), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  InfoRow(t('Total sales (${revenue['paidOrders']} orders)', 'মোট বিক্রি (${revenue['paidOrders']} অর্ডার)'), taka(revenue['grossPaisa'] as int)),
                  InfoRow(t('Gateway fees', 'গেটওয়ে ফি'), taka(revenue['gatewayFeesPaisa'] as int)),
                  InfoRow(t('Owed to teachers', 'টিচারদের পাওনা'), taka(revenue['teacherOwedPaisa'] as int)),
                  InfoRow(t('Sent to teachers', 'টিচারদের পাঠানো'), taka(revenue['teacherPaidPaisa'] as int)),
                  const Divider(height: 20),
                  InfoRow(t('Platform net income', 'প্ল্যাটফর্মের নিট আয়'), taka(revenue['platformNetPaisa'] as int), strong: true, valueColor: Brand.success),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            EmptyState(
              t('Drafts are created automatically on schedule, or tap "Create payouts now".', 'শিডিউল অনুযায়ী খসড়া আপনা থেকে তৈরি হবে, অথবা "এখন পেআউট তৈরি" চাপুন।'),
              title: t('No payouts yet', 'এখনো কোনো পেআউট নেই'),
              icon: Icons.payments_outlined,
              compact: true,
            ),
          for (final p in list)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ListTile(
                  title: Text('${p['teacher']['name']} · ${taka(p['amountPaisa'] as int)}'),
                  subtitle: Text([
                    p['account'] == null ? t('No payout account added', 'পেআউট অ্যাকাউন্ট দেননি') : '${_methods[p['method']] ?? p['method']}: ${p['account']}',
                    _status[p['status']]!,
                    if (p['reference'] != null) t('Ref: ${p['reference']}', 'রেফ: ${p['reference']}'),
                  ].join(' · ')),
                ),
                if (p['status'] != 'PAID')
                  OverflowBar(alignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: () async {
                        if (!await confirmAction(context, title: t('Cancel this payout?', 'এই পেআউট বাতিল করবেন?'), confirm: t('Cancel payout', 'পেআউট বাতিল'))) return;
                        if (context.mounted) await _run(context, ref, () => api.delete('/admin/payouts/${p['id']}'), t('Cancelled', 'বাতিল হয়েছে'));
                      }, child: Text(t('Cancel', 'বাতিল'))),
                    if (p['status'] == 'DRAFT')
                      FilledButton(onPressed: () => _run(context, ref, () => api.post('/admin/payouts/${p['id']}/approve'), t('Approved', 'অনুমোদিত')), child: Text(t('Approve', 'অনুমোদন'))),
                    if (p['status'] == 'APPROVED')
                      FilledButton(
                        onPressed: () async {
                          final ref0 = TextEditingController();
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(t('Money sent?', 'টাকা পাঠিয়েছেন?')),
                              content: TextField(controller: ref0, decoration: InputDecoration(labelText: t('Transaction ID / reference', 'ট্রানজ্যাকশন আইডি / রেফারেন্স'))),
                              actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Sent', 'পাঠানো হয়েছে')))],
                            ),
                          );
                          if (ok == true && context.mounted) {
                            await _run(context, ref, () => api.post('/admin/payouts/${p['id']}/paid', {'reference': ref0.text.trim()}), t('Payout completed', 'পেআউট সম্পন্ন'));
                          }
                        },
                        child: Text(t('Sent', 'পাঠানো হয়েছে')),
                      ),
                    const SizedBox(width: 8),
                  ]),
              ]),
            ),
        ]),
      ),
    );
  }
}

final ordersProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/admin/orders', query: {'status': 'PAID'}));

class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(ordersProvider);
    final date = DateFormat('d MMM y, h:mm a');
    return Scaffold(
      appBar: AppBar(title: Text(t('Paid orders', 'পেইড অর্ডার'))),
      body: AsyncView(
        value: orders,
        data: (list) => list.isEmpty
            ? EmptyState(t('No paid orders yet', 'এখনো কোনো পেইড অর্ডার নেই'))
            : ListView(children: [
                for (final o in list)
                  ListTile(
                    title: Text('${o['user']['name']} · ${taka(o['amountPaisa'] as int)}'),
                    subtitle: Text('${o['tranId']} · ${date.format(DateTime.parse(o['createdAt'] as String).toLocal())}'),
                    trailing: TextButton(
                      child: Text(t('Refund', 'রিফান্ড')),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: Text(t('Record a refund?', 'রিফান্ড রেকর্ড করবেন?')),
                            content: Text(t('The student loses access and the amount is deducted from the teacher\'s earnings. Return the money from the SSLCommerz panel.', 'স্টুডেন্টের অ্যাক্সেস বন্ধ হবে এবং টিচারের আয় থেকে কাটা হবে। টাকা ফেরত SSLCommerz প্যানেল থেকে দিন।')),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('No', 'না'))),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Refund', 'রিফান্ড'))),
                            ],
                          ),
                        );
                        if (ok != true) return;
                        try {
                          await ref.read(apiProvider).post('/admin/orders/${o['id']}/refund');
                          ref.invalidate(ordersProvider);
                        } catch (e) {
                          if (context.mounted) showMessage(context, e);
                        }
                      },
                    ),
                  ),
              ]),
      ),
    );
  }
}
