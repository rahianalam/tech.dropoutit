import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

final earningsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(apiProvider).get('/teacher/earnings'));

const _methods = {'bkash': 'bKash', 'nagad': 'Nagad', 'rocket': 'Rocket', 'bank': 'ব্যাংক'};
const _schedule = {'WEEKLY': 'প্রতি রবিবার', 'MONTHLY': 'প্রতি মাসে', 'MANUAL': 'অ্যাডমিন যখন পাঠান'};

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  Future<void> _editAccount(BuildContext context, WidgetRef ref, Map<String, dynamic>? current) async {
    var method = current?['payoutMethod'] as String? ?? 'bkash';
    final account = TextEditingController(text: current?['payoutAccount'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('পেআউট অ্যাকাউন্ট'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: method,
              items: [for (final e in _methods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => method = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: account,
              decoration: InputDecoration(labelText: method == 'bank' ? 'ব্যাংক, শাখা, অ্যাকাউন্ট নম্বর, নাম' : 'মোবাইল নম্বর'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('বাতিল')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('সেভ')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(apiProvider).patch('/teacher/payout-account', {'method': method, 'account': account.text.trim()});
      ref.invalidate(earningsProvider);
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(earningsProvider);
    final date = DateFormat('d MMM y');
    return Scaffold(
      appBar: AppBar(title: const Text('আমার আয়')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(earningsProvider.future),
        child: AsyncView(
          value: data,
          onRetry: () => ref.invalidate(earningsProvider),
          data: (e) {
            final acc = e['payoutAccount'] as Map<String, dynamic>?;
            final s = e['schedule'] as Map<String, dynamic>;
            final text = Theme.of(context).textTheme;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Row(children: [
                Expanded(child: _Tile('উত্তোলনযোগ্য', taka(e['availablePaisa'] as int), strong: true)),
                const SizedBox(width: 12),
                Expanded(child: _Tile('হোল্ডে আছে', taka(e['pendingPaisa'] as int))),
                const SizedBox(width: 12),
                Expanded(child: _Tile('মোট পেয়েছেন', taka(e['paidPaisa'] as int))),
              ]),
              const SizedBox(height: 12),
              Text(
                'বিক্রির ${s['holdDays']} দিন পর টাকা উত্তোলনযোগ্য হয়। পেআউট: ${_schedule[s['payoutSchedule']]}'
                '${s['payoutSchedule'] == 'MONTHLY' ? ' ${s['payoutDayOfMonth']} তারিখে' : ''}, সর্বনিম্ন ${taka(s['minPayoutPaisa'] as int)}।',
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(acc?['payoutMethod'] == null ? 'পেআউট অ্যাকাউন্ট যোগ করুন' : '${_methods[acc!['payoutMethod']]}: ${acc['payoutAccount']}'),
                  subtitle: acc?['payoutMethod'] == null ? const Text('টাকা পেতে এটা দরকার') : null,
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editAccount(context, ref, acc),
                ),
              ),
              const SizedBox(height: 24),
              Text('পেআউট', style: text.titleMedium),
              if ((e['payouts'] as List).isEmpty) const Padding(padding: EdgeInsets.all(8), child: Text('এখনো কোনো পেআউট হয়নি')),
              for (final p in e['payouts'] as List)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(taka(p['amountPaisa'] as int)),
                  subtitle: Text([date.format(DateTime.parse(p['createdAt'] as String).toLocal()), if (p['reference'] != null) 'রেফ: ${p['reference']}'].join(' · ')),
                  trailing: Text(p['status'] == 'PAID' ? 'পাঠানো হয়েছে' : 'প্রক্রিয়াধীন'),
                ),
              const SizedBox(height: 16),
              Text('লেনদেন', style: text.titleMedium),
              for (final l in e['entries'] as List)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l['type'] == 'REFUND' ? 'রিফান্ড কর্তন' : 'বিক্রি (কমিশন ${(l['commissionBps'] as int) / 100}%)'),
                  subtitle: Text(date.format(DateTime.parse(l['createdAt'] as String).toLocal())),
                  trailing: Text(taka(l['amountPaisa'] as int)),
                ),
            ]);
          },
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, {this.strong = false});
  final String label;
  final String value;
  final bool strong;
  @override
  Widget build(BuildContext context) => Card(
        color: strong ? Theme.of(context).colorScheme.primaryContainer : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(child: Text(value, style: Theme.of(context).textTheme.titleLarge)),
            Text(label, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      );
}
