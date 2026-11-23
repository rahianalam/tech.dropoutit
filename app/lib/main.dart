import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'core/auth.dart';
import 'core/push.dart';
import 'core/router.dart';
import 'core/theme.dart';

void main() => runApp(const ProviderScope(child: TechDropoutApp()));

class TechDropoutApp extends ConsumerWidget {
  const TechDropoutApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(authProvider.select((s) => s.ready));
    ref.watch(pushProvider); // registers the phone for push once signed in
    // Always use the router (a plain MaterialApp would rewrite the browser URL and lose deep links);
    // show a splash over it until the saved session has been restored.
    return MaterialApp.router(
      title: 'Tech.Dropout',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => ready ? child! : const Scaffold(body: Center(child: CircularProgressIndicator())),
    );
  }
}
