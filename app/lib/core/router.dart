import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../features/admin/admin_screens.dart';
import '../features/admin/money_screens.dart';
import '../features/auth/auth_screens.dart';
import '../features/booking/booking_screens.dart';
import '../features/course/course_screens.dart';
import '../features/home/home_screen.dart';
import '../features/home/search_screen.dart';
import '../features/account/account_screens.dart';
import '../features/admin/admin_manage_screens.dart';
import '../features/jobs/employer_screens.dart';
import '../features/jobs/jobs_screens.dart';
import '../features/learning/my_learning_screen.dart';
import '../features/profile_screen.dart';
import '../features/teacher/earnings_screen.dart';
import '../features/teacher/teacher_screens.dart';
import 'auth.dart';
import 'i18n.dart';

/// Bottom tabs (max 5) depend on the user's roles:
/// students: Home, Search, My learning, Jobs, Account
/// teachers: Home, Search, My learning, Teach, Account (jobs from Home/Account)
/// admins:   Home, Search, Jobs, Admin, Account
List<({String path, IconData icon, IconData selected, String label})> tabsFor(Me? me) {
  final admin = me?.isAdmin ?? false;
  final teacher = (me?.isTeacher ?? false) && !admin;
  return [
    (path: '/', icon: Icons.home_outlined, selected: Icons.home_rounded, label: t('Home', 'হোম')),
    (path: '/search', icon: Icons.search_rounded, selected: Icons.saved_search_rounded, label: t('Search', 'খুঁজুন')),
    if (!admin) (path: '/learning', icon: Icons.play_circle_outline_rounded, selected: Icons.play_circle_rounded, label: t('Learning', 'লার্নিং')),
    if (!teacher) (path: '/jobs', icon: Icons.work_outline_rounded, selected: Icons.work_rounded, label: t('Jobs', 'জবস')),
    if (teacher) (path: '/teacher', icon: Icons.cast_for_education_outlined, selected: Icons.cast_for_education_rounded, label: t('Teach', 'পড়ান')),
    if (admin) (path: '/admin', icon: Icons.space_dashboard_outlined, selected: Icons.space_dashboard_rounded, label: t('Admin', 'অ্যাডমিন')),
    (path: '/profile', icon: Icons.person_outline_rounded, selected: Icons.person_rounded, label: t('Account', 'অ্যাকাউন্ট')),
  ];
}

const _needsLogin = ['/learning', '/teacher', '/admin', '/notifications', '/employer', '/jobs/profile', '/jobs/applications', '/account'];

/// Prefix match on whole path segments, so '/teacher' does not swallow the
/// public '/teachers/:id' pages.
bool _under(String loc, String root) => loc == root || loc.startsWith('$root/');

/// Where the user was, so switching language (which rebuilds the router and every
/// screen in the new language) keeps them on the same page.
String _lastLocation = '/';

final routerProvider = Provider<GoRouter>((ref) {
  ref.watch(langProvider);
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  final rootKey = GlobalKey<NavigatorState>();
  late final GoRouter router;
  void track() => _lastLocation = router.routerDelegate.currentConfiguration.uri.toString();
  router = GoRouter(
    navigatorKey: rootKey,
    initialLocation: _lastLocation,
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (!auth.ready) return null;
      final loc = state.matchedLocation;
      final me = auth.me;
      if (me == null && (_needsLogin.any((r) => _under(loc, r)) || loc.endsWith('/book'))) return '/login';
      if (me != null && (loc == '/login' || loc == '/register')) return '/';
      if (_under(loc, '/admin') && !(me?.isAdmin ?? false)) return '/';
      final canTeach = (me?.isTeacher ?? false) || ((me?.isAdmin ?? false) && loc.startsWith('/teacher/courses'));
      if (_under(loc, '/teacher') && loc != '/teacher/apply' && !canTeach) return '/teacher/apply';
      if (_under(loc, '/employer') && loc != '/employer/setup' && !(me?.isEmployer ?? false)) return '/employer/setup';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const LoginScreen(register: true)),
      ShellRoute(
        builder: (context, state, child) => _Shell(location: state.matchedLocation, child: child),
        routes: [
          // Every page outside the tabs sits on top of Home, so a page opened from a
          // link, a notification or after a language switch still has a back arrow
          // and Android back lands on Home instead of closing the app.
          GoRoute(
            path: '/',
            builder: (_, _) => const HomeScreen(),
            routes: [
              GoRoute(parentNavigatorKey: rootKey, path: 'courses/:id', builder: (_, s) => CourseDetailScreen(s.pathParameters['id']!)),
              GoRoute(parentNavigatorKey: rootKey, path: 'lessons/:id', builder: (_, s) => LessonScreen(s.pathParameters['id']!)),
              GoRoute(parentNavigatorKey: rootKey, path: 'teachers/:id', builder: (_, s) => TeacherProfileScreen(s.pathParameters['id']!)),
              GoRoute(
                parentNavigatorKey: rootKey,
                path: 'teachers/:id/book',
                builder: (_, s) => BookSessionScreen(s.pathParameters['id']!, teacherName: s.uri.queryParameters['name']),
              ),
              GoRoute(parentNavigatorKey: rootKey, path: 'teacher/sessions', builder: (_, _) => const TeacherSessionsScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'teacher/availability', builder: (_, _) => const AvailabilityScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'jobs/profile', builder: (_, _) => const SeekerProfileScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'jobs/applications', builder: (_, _) => const MyApplicationsScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'jobs/:id', builder: (_, s) => JobDetailScreen(s.pathParameters['id']!)),
              GoRoute(parentNavigatorKey: rootKey, path: 'employer', builder: (_, _) => const EmployerDashboard()),
              GoRoute(parentNavigatorKey: rootKey, path: 'employer/setup', builder: (_, _) => const EmployerSetupScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'employer/jobs/new', builder: (_, _) => const JobEditorScreen()),
              GoRoute(
                parentNavigatorKey: rootKey,
                path: 'employer/jobs/:id/edit',
                builder: (_, s) => JobEditorScreen(job: s.extra as Map<String, dynamic>?),
              ),
              GoRoute(
                parentNavigatorKey: rootKey,
                path: 'employer/jobs/:id/applicants',
                builder: (_, s) => ApplicantsScreen(s.pathParameters['id']!, title: s.uri.queryParameters['title']),
              ),
              GoRoute(parentNavigatorKey: rootKey, path: 'admin/jobs', builder: (_, _) => const AdminJobsScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'notifications', builder: (_, _) => const NotificationsScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'teacher/apply', builder: (_, _) => const TeacherApplyScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'teacher/courses/:id', builder: (_, s) => CourseEditorScreen(s.pathParameters['id']!)),
              GoRoute(parentNavigatorKey: rootKey, path: 'admin/applications', builder: (_, _) => const ApplicationsScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'admin/applications/:id', builder: (_, s) => ApplicationReviewScreen(s.pathParameters['id']!)),
              GoRoute(parentNavigatorKey: rootKey, path: 'admin/course-reviews', builder: (_, _) => const CourseReviewScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'teacher/earnings', builder: (_, _) => const EarningsScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'admin/payouts', builder: (_, _) => const PayoutsScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'admin/orders', builder: (_, _) => const OrdersScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'admin/settings', builder: (_, _) => const SettingsScreen()),
              GoRoute(
                parentNavigatorKey: rootKey,
                path: 'admin/courses',
                builder: (_, _) => TeacherDashboard(customTitle: t('My recorded courses', 'আমার রেকর্ডেড কোর্স')),
              ),
              GoRoute(parentNavigatorKey: rootKey, path: 'admin/all-courses', builder: (_, _) => const AdminCoursesScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'admin/categories', builder: (_, _) => const CategoriesScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'admin/users', builder: (_, _) => const UsersScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'admin/audit', builder: (_, _) => const AuditScreen()),
              GoRoute(parentNavigatorKey: rootKey, path: 'account/security', builder: (_, _) => const AccountSecurityScreen()),
            ],
          ),
          GoRoute(
            path: '/search',
            builder: (_, s) => SearchScreen(
              key: ValueKey(s.uri.toString()),
              initialQuery: s.uri.queryParameters['q'] ?? '',
              initialCategory: s.uri.queryParameters['category'],
              initialFree: s.uri.queryParameters['free'] == null ? null : s.uri.queryParameters['free'] == 'true',
              initialSort: s.uri.queryParameters['sort'],
            ),
          ),
          GoRoute(
            path: '/learning',
            builder: (_, s) => MyLearningScreen(initialTab: s.uri.queryParameters['tab'] == 'sessions' ? 1 : 0),
          ),
          GoRoute(path: '/jobs', builder: (_, _) => const JobsScreen()),
          GoRoute(path: '/teacher', builder: (_, _) => const TeacherDashboard()),
          GoRoute(path: '/admin', builder: (_, _) => const AdminDashboard()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ],
      ),
    ],
  );
  router.routerDelegate.addListener(track);
  ref.onDispose(() {
    router.routerDelegate.removeListener(track);
    router.dispose();
  });
  return router;
});

class _Shell extends ConsumerWidget {
  const _Shell({required this.location, required this.child});
  final String location;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = tabsFor(ref.watch(authProvider).me);
    final index = tabs.indexWhere((t) => t.path == location);
    // Android back on a tab: other tabs go to Home first; on Home a second press
    // within 2 seconds closes the app, so one stray tap never throws the user out.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (location != '/') return context.go('/');
        final now = DateTime.now();
        if (_lastBack != null && now.difference(_lastBack!) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        _lastBack = now;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(t('Press back again to exit', 'বের হতে আবার ব্যাক চাপুন')), duration: const Duration(seconds: 2)));
      },
      child: Scaffold(
        body: child,
        bottomNavigationBar: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: Theme.of(context).colorScheme.outlineVariant)),
          ),
          child: NavigationBar(
            selectedIndex: index < 0 ? 0 : index,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            onDestinationSelected: (i) => context.go(tabs[i].path),
            destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.icon), selectedIcon: Icon(t.selected), label: t.label)],
          ),
        ),
      ),
    );
  }
}

DateTime? _lastBack;
