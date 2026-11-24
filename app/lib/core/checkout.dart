import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth.dart';
import 'i18n.dart';
import 'widgets.dart';

/// The affiliate code from the last `?ref=` link this visitor opened. Passed on
/// course checkout so the affiliate gets the commission.
String? affiliateRef;

/// Opens the payment page for an order the API just created and waits for the
/// person to come back. Returns true once the order is PAID.
Future<bool> payOrder(BuildContext context, WidgetRef ref, Map<String, dynamic> checkout) async {
  final orderId = checkout['orderId'] as String;
  await launchUrl(Uri.parse(checkout['gatewayUrl'] as String), mode: LaunchMode.externalApplication);
  if (!context.mounted) return false;
  final paid = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _WaitForPayment(orderId: orderId),
  );
  return paid ?? false;
}

class _WaitForPayment extends ConsumerStatefulWidget {
  const _WaitForPayment({required this.orderId});
  final String orderId;
  @override
  ConsumerState<_WaitForPayment> createState() => _WaitForPaymentState();
}

class _WaitForPaymentState extends ConsumerState<_WaitForPayment> {
  bool _checking = false;

  Future<void> _check() async {
    setState(() => _checking = true);
    try {
      for (var i = 0; i < 5; i++) {
        final o = await ref.read(apiProvider).get<Map<String, dynamic>>('/orders/${widget.orderId}');
        if (o['status'] == 'PAID') {
          if (mounted) Navigator.pop(context, true);
          return;
        }
        if (o['status'] != 'PENDING') break;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (mounted) showMessage(context, t('Payment not received yet.', 'পেমেন্ট এখনো পৌঁছায়নি।'));
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(t('Finish the payment', 'পেমেন্ট শেষ করুন')),
        content: Text(t('Pay with bKash, Nagad, Rocket or card on the page that opened, then come back here.',
            'যে পেজ খুলেছে সেখানে বিকাশ, নগদ, রকেট বা কার্ডে পেমেন্ট করুন, তারপর এখানে ফিরে আসুন।')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t('Later', 'পরে'))),
          FilledButton(
            onPressed: _checking ? null : _check,
            child: Text(_checking ? t('Checking…', 'দেখছি…') : t('I have paid', 'পেমেন্ট করেছি')),
          ),
        ],
      );
}
