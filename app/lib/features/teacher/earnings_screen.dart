import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/i18n.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

final earningsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) => ref.read(apiProvider).get('/teacher/earnings'));

Map<String, String> get _methods => {'bkash': 'bKash', 'nagad': 'Nagad', 'rocket': 'Rocket', 'bank': t('Bank', 'ব্যাংক')};
Map<String, String> get _schedule => {'WEEKLY': t('Every Sunday', 'প্রতি রবিবার'), 'MONTHLY': t('Every month', 'প্রতি মাসে'), 'MANUAL': t('When the admin sends it', 'অ্যাডমিন যখন পাঠান')};

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  Future<void> _editAccount(BuildContext context, WidgetRef ref, Map<String, dynamic>? current) async {
    var method = current?['payoutMethod'] as String? ?? 'bkash';
    final account = TextEditingController(text: current?['payoutAccount'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(t('Payout account', 'পেআউট অ্যাকাউন্ট')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<String>(
              initialValue: method,
              items: [for (final e in _methods.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
              onChanged: (v) => setState(() => method = v!),
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
      appBar: AppBar(title: Text(t('My earnings', 'আমার আয়'))),
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
                Expanded(child: _Tile(t('Available', 'উত্তোলনযোগ্য'), taka(e['availablePaisa'] as int), strong: true)),
                const SizedBox(width: 12),
                Expanded(child: _Tile(t('On hold', 'হোল্ডে আছে'), taka(e['pendingPaisa'] as int))),
                const SizedBox(width: 12),
                Expanded(child: _Tile(t('Total received', 'মোট পেয়েছেন'), taka(e['paidPaisa'] as int))),
              ]),
              const SizedBox(height: 12),
              Text(
                t('Money becomes available ${s['holdDays']} days after a sale. Payouts: ${_schedule[s['payoutSchedule']]}', 'বিক্রির ${s['holdDays']} দিন পর টাকা উত্তোলনযোগ্য হয়। পেআউট: ${_schedule[s['payoutSchedule']]}') +
                t('${s['payoutSchedule'] == 'MONTHLY' ? ' on day ${s['payoutDayOfMonth']}' : ''}, minimum ${taka(s['minPayoutPaisa'] as int)}.', '${s['payoutSchedule'] == 'MONTHLY' ? ' ${s['payoutDayOfMonth']} তারিখে' : ''}, সর্বনিম্ন ${taka(s['minPayoutPaisa'] as int)}।'),
                style: text.bodySmall,
              ),
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(acc?['payoutMethod'] == null ? t('Add a payout account', 'পেআউট অ্যাকাউন্ট যোগ করুন') : '${_methods[acc!['payoutMethod']]}: ${acc['payoutAccount']}'),
                  subtitle: acc?['payoutMethod'] == null ? Text(t('Needed to get paid', 'টাকা পেতে এটা দরকার')) : null,
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: () => _editAccount(context, ref, acc),
                ),
              ),
              const SizedBox(height: 24),
              Text(t('Payouts', 'পেআউট'), style: text.titleMedium),
              if ((e['payouts'] as List).isEmpty) Padding(padding: EdgeInsets.all(8), child: Text(t('No payouts yet', 'এখনো কোনো পেআউট হয়নি'))),
              for (final p in e['payouts'] as List)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(taka(p['amountPaisa'] as int)),
                  subtitle: Text([date.format(DateTime.parse(p['createdAt'] as String).toLocal()), if (p['reference'] != null) t('Ref: ${p['reference']}', 'রেফ: ${p['reference']}')].join(' · ')),
                  trailing: Text(p['status'] == 'PAID' ? t('Sent', 'পাঠানো হয়েছে') : t('Processing', 'প্রক্রিয়াধীন')),
                ),
              const SizedBox(height: 16),
              Text(t('Transactions', 'লেনদেন'), style: text.titleMedium),
              for (final l in e['entries'] as List)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(l['type'] == 'REFUND' ? t('Refund deduction', 'রিফান্ড কর্তন') : t('Sale (commission ${(l['commissionBps'] as int) / 100}%)', 'বিক্রি (কমিশন ${(l['commissionBps'] as int) / 100}%)')),
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
