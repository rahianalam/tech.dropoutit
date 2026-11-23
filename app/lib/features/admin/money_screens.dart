import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

final payoutsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/admin/payouts'));
final revenueProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(apiProvider).get('/admin/revenue'));

const _methods = {'bkash': 'bKash', 'nagad': 'Nagad', 'rocket': 'Rocket', 'bank': 'ব্যাংক'};
const _status = {'DRAFT': 'খসড়া', 'APPROVED': 'অনুমোদিত', 'PAID': 'পাঠানো হয়েছে'};

/// Draft → approve → send money (bKash/Nagad/bank) → record the reference.
class PayoutsScreen extends ConsumerWidget {
  const PayoutsScreen({super.key});

  Future<void> _run(BuildContext context, WidgetRef ref, Future<Object?> Function() fn, String done) async {
    try {
      await fn();
      ref.invalidate(payoutsProvider);
      ref.invalidate(revenueProvider);
      if (context.mounted) showMessage(context, done);
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
      appBar: AppBar(title: const Text('টিচার পেআউট')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _run(context, ref, () => api.post('/admin/payouts/generate'), 'পেআউট খসড়া তৈরি হয়েছে'),
        icon: const Icon(Icons.playlist_add),
        label: const Text('এখন পেআউট তৈরি'),
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
                  Text('মোট বিক্রি ${taka(revenue['grossPaisa'] as int)} (${revenue['paidOrders']} অর্ডার)'),
                  Text('গেটওয়ে ফি ${taka(revenue['gatewayFeesPaisa'] as int)}'),
                  Text('টিচারদের পাওনা ${taka(revenue['teacherOwedPaisa'] as int)} · পাঠানো ${taka(revenue['teacherPaidPaisa'] as int)}'),
                  const SizedBox(height: 4),
                  Text('প্ল্যাটফর্মের নিট আয় ${taka(revenue['platformNetPaisa'] as int)}', style: Theme.of(context).textTheme.titleMedium),
                ]),
              ),
            ),
          const SizedBox(height: 16),
          if (list.isEmpty) const EmptyState('কোনো পেআউট নেই। শিডিউল অনুযায়ী খসড়া আপনা থেকে তৈরি হবে।', icon: Icons.payments_outlined),
          for (final p in list)
            Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                ListTile(
                  title: Text('${p['teacher']['name']} · ${taka(p['amountPaisa'] as int)}'),
                  subtitle: Text([
                    p['account'] == null ? 'পেআউট অ্যাকাউন্ট দেননি' : '${_methods[p['method']] ?? p['method']}: ${p['account']}',
                    _status[p['status']]!,
                    if (p['reference'] != null) 'রেফ: ${p['reference']}',
                  ].join(' · ')),
                ),
                if (p['status'] != 'PAID')
                  OverflowBar(alignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () => _run(context, ref, () => api.delete('/admin/payouts/${p['id']}'), 'বাতিল হয়েছে'), child: const Text('বাতিল')),
                    if (p['status'] == 'DRAFT')
                      FilledButton(onPressed: () => _run(context, ref, () => api.post('/admin/payouts/${p['id']}/approve'), 'অনুমোদিত'), child: const Text('অনুমোদন')),
                    if (p['status'] == 'APPROVED')
                      FilledButton(
                        onPressed: () async {
                          final ref0 = TextEditingController();
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('টাকা পাঠিয়েছেন?'),
                              content: TextField(controller: ref0, decoration: const InputDecoration(labelText: 'ট্রানজ্যাকশন আইডি / রেফারেন্স')),
                              actions: [FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('পাঠানো হয়েছে'))],
                            ),
                          );
                          if (ok == true && context.mounted) {
                            await _run(context, ref, () => api.post('/admin/payouts/${p['id']}/paid', {'reference': ref0.text.trim()}), 'পেআউট সম্পন্ন');
                          }
                        },
                        child: const Text('পাঠানো হয়েছে'),
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
      appBar: AppBar(title: const Text('পেইড অর্ডার')),
      body: AsyncView(
        value: orders,
        data: (list) => list.isEmpty
            ? const EmptyState('এখনো কোনো পেইড অর্ডার নেই')
            : ListView(children: [
                for (final o in list)
                  ListTile(
                    title: Text('${o['user']['name']} · ${taka(o['amountPaisa'] as int)}'),
                    subtitle: Text('${o['tranId']} · ${date.format(DateTime.parse(o['createdAt'] as String).toLocal())}'),
                    trailing: TextButton(
                      child: const Text('রিফান্ড'),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('রিফান্ড রেকর্ড করবেন?'),
                            content: const Text('স্টুডেন্টের অ্যাক্সেস বন্ধ হবে এবং টিচারের আয় থেকে কাটা হবে। টাকা ফেরত SSLCommerz প্যানেল থেকে দিন।'),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('না')),
                              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('রিফান্ড')),
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
