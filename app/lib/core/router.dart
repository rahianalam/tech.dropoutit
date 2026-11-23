import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import '../features/admin/admin_screens.dart';
import '../features/auth/auth_screens.dart';
import '../features/course/course_screens.dart';
import '../features/home/home_screen.dart';
import '../features/learning/my_learning_screen.dart';
import '../features/profile_screen.dart';
import '../features/teacher/teacher_screens.dart';
import 'auth.dart';

/// Tabs depend on the user's roles: everyone gets Explore / My learning / Profile,
/// teachers also get Teach, admins also get Admin.
List<({String path, IconData icon, String label})> tabsFor(Me? me) => [
      (path: '/', icon: Icons.explore_outlined, label: 'এক্সপ্লোর'),
      (path: '/learning', icon: Icons.school_outlined, label: 'লার্নিং'),
      if (me?.isTeacher ?? false) (path: '/teacher', icon: Icons.cast_for_education_outlined, label: 'টিচিং'),
      if (me?.isAdmin ?? false) (path: '/admin', icon: Icons.admin_panel_settings_outlined, label: 'অ্যাডমিন'),
      (path: '/profile', icon: Icons.person_outline, label: 'প্রোফাইল'),
    ];

const _needsLogin = ['/learning', '/teacher', '/admin', '/notifications'];

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authProvider);
      if (!auth.ready) return null;
      final loc = state.matchedLocation;
      final me = auth.me;
      if (me == null && _needsLogin.any(loc.startsWith)) return '/login';
      if (me != null && (loc == '/login' || loc == '/register')) return '/';
      if (loc.startsWith('/admin') && !(me?.isAdmin ?? false)) return '/';
      final canTeach = (me?.isTeacher ?? false) || ((me?.isAdmin ?? false) && loc.startsWith('/teacher/courses'));
      if (loc.startsWith('/teacher') && loc != '/teacher/apply' && !canTeach) return '/teacher/apply';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/register', builder: (_, _) => const LoginScreen(register: true)),
      ShellRoute(
        builder: (context, state, child) => _Shell(location: state.matchedLocation, child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
          GoRoute(path: '/learning', builder: (_, _) => const MyLearningScreen()),
          GoRoute(path: '/teacher', builder: (_, _) => const TeacherDashboard()),
          GoRoute(path: '/admin', builder: (_, _) => const AdminDashboard()),
          GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        ],
      ),
      GoRoute(path: '/courses/:id', builder: (_, s) => CourseDetailScreen(s.pathParameters['id']!)),
      GoRoute(path: '/lessons/:id', builder: (_, s) => LessonScreen(s.pathParameters['id']!)),
      GoRoute(path: '/teachers/:id', builder: (_, s) => TeacherProfileScreen(s.pathParameters['id']!)),
      GoRoute(path: '/notifications', builder: (_, _) => const NotificationsScreen()),
      GoRoute(path: '/teacher/apply', builder: (_, _) => const TeacherApplyScreen()),
      GoRoute(path: '/teacher/courses/:id', builder: (_, s) => CourseEditorScreen(s.pathParameters['id']!)),
      GoRoute(path: '/admin/applications', builder: (_, _) => const ApplicationsScreen()),
      GoRoute(path: '/admin/applications/:id', builder: (_, s) => ApplicationReviewScreen(s.pathParameters['id']!)),
      GoRoute(path: '/admin/course-reviews', builder: (_, _) => const CourseReviewScreen()),
      GoRoute(path: '/admin/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/admin/courses', builder: (_, _) => const TeacherDashboard(title: 'আমার রেকর্ডেড কোর্স')),
    ],
  );
});

class _Shell extends ConsumerWidget {
  const _Shell({required this.location, required this.child});
  final String location;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = tabsFor(ref.watch(authProvider).me);
    final index = tabs.indexWhere((t) => t.path == location).clamp(0, tabs.length - 1);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => context.go(tabs[i].path),
        destinations: [for (final t in tabs) NavigationDestination(icon: Icon(t.icon), label: t.label)],
      ),
    );
  }
}
