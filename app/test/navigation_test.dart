import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:techdropout/core/auth.dart';
import 'package:techdropout/core/router.dart';

class _SignedOut extends AuthController {
  @override
  AuthState build() => const AuthState(ready: true);
}

String _where(GoRouter r) => r.routerDelegate.currentConfiguration.uri.path;

void main() {
  late GoRouter router;

  Future<void> boot(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [authProvider.overrideWith(_SignedOut.new)]);
    addTearDown(container.dispose);
    router = container.read(routerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> back(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await settle(tester);
  }

  testWidgets('Android back on a tab goes to Home, and Home asks before closing', (tester) async {
    await boot(tester);
    router.go('/search');
    await settle(tester);
    await back(tester);
    expect(_where(router), '/');
    await back(tester);
    expect(_where(router), '/');
    expect(find.text('Press back again to exit'), findsOneWidget);
  });

  testWidgets('a page opened from a link has a back arrow that lands on Home', (tester) async {
    await boot(tester);
    router.go('/jobs/abc');
    await settle(tester);
    expect(find.byTooltip('Back'), findsOneWidget);
    await back(tester);
    expect(_where(router), '/');
  });

  testWidgets('back from a pushed page returns to the tab it came from', (tester) async {
    await boot(tester);
    router.go('/search');
    await settle(tester);
    router.push('/courses/abc');
    await settle(tester);
    await back(tester);
    expect(_where(router), '/search');
  });
}
