import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

/// Renders an AsyncValue with a spinner, a retry-able error, or the data.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry});
  final AsyncValue<T> value;
  final Widget Function(T) data;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => value.when(
        data: data,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(e.toString(), textAlign: TextAlign.center),
              if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('আবার চেষ্টা করুন')),
            ]),
          ),
        ),
      );
}

void showMessage(BuildContext context, Object message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.toString())));

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(text, textAlign: TextAlign.center),
          ]),
        ),
      );
}
