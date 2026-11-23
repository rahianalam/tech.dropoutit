import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'core/api.dart';
import 'core/auth.dart';
import 'core/i18n.dart';
import 'core/push.dart';
import 'core/router.dart';
import 'core/theme.dart';
import 'core/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await loadSavedLang();
  runApp(const ProviderScope(retry: _retry, child: TechDropoutApp()));
}

/// Retry a failed load only for network trouble, and only twice. A "not found" or
/// "not allowed" answer will not change, so it shows at once with a Try again button
/// instead of a spinner that keeps going.
Duration? _retry(int count, Object error) {
  if (count >= 2 || error is! ApiError || error.status != null) return null;
  return Duration(seconds: 1 << count);
}

class TechDropoutApp extends ConsumerWidget {
  const TechDropoutApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(authProvider.select((s) => s.ready));
    ref.watch(pushProvider); // registers the phone for push once signed in
    ref.watch(langProvider);
    // Always use the router (a plain MaterialApp would rewrite the browser URL and lose deep links);
    // show a branded splash over it until the saved session has been restored.
    return MaterialApp.router(
      title: 'Tech.Dropout IT',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) => ready ? child! : const _Splash(),
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => const Scaffold(
        backgroundColor: Brand.teal,
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            BrandMark(size: 96, color: Brand.cyan),
            SizedBox(height: 16),
            BrandWordmark(size: 26, color: Brand.cyan, showMark: false),
            SizedBox(height: 28),
            SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Brand.cyan)),
          ]),
        ),
      );
}
