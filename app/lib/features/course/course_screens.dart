import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

final courseProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
    (ref, id) => ref.read(apiProvider).get('/courses/$id'));

class CourseDetailScreen extends ConsumerStatefulWidget {
  const CourseDetailScreen(this.id, {super.key});
  final String id;
  @override
  ConsumerState<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends ConsumerState<CourseDetailScreen> with WidgetsBindingObserver {
  String get id => widget.id;
  String? _pendingOrder;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// When the user comes back from the payment page, check the order a few times.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingOrder != null) _checkOrder();
  }

  Future<void> _checkOrder() async {
    final orderId = _pendingOrder;
    if (orderId == null) return;
    for (var i = 0; i < 6; i++) {
      final o = await ref.read(apiProvider).get<Map<String, dynamic>>('/orders/$orderId');
      if (o['status'] == 'PAID') {
        _pendingOrder = null;
        ref.invalidate(courseProvider(id));
        if (mounted) showMessage(context, 'পেমেন্ট সফল! কোর্স শুরু করুন।');
        return;
      }
      if (o['status'] != 'PENDING') break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (mounted) showMessage(context, 'পেমেন্ট এখনো নিশ্চিত হয়নি। টাকা কেটে থাকলে কিছুক্ষণের মধ্যে আপডেট হবে।');
  }

  Future<void> _enroll(Map<String, dynamic> course) async {
    if (!ref.read(authProvider).loggedIn) return context.go('/login');
    setState(() => _busy = true);
    try {
      final api = ref.read(apiProvider);
      if (course['isFree'] == true) {
        await api.post('/courses/$id/enroll');
        ref.invalidate(courseProvider(id));
        if (mounted) showMessage(context, 'এনরোল সম্পন্ন! এখন শেখা শুরু করুন।');
      } else {
        // Paid: open the SSLCommerz page (bKash, Nagad, card…). Enrollment happens
        // on the server once the gateway confirms the payment.
        final checkout = await api.post<Map<String, dynamic>>('/checkout/course/$id');
        _pendingOrder = checkout['orderId'] as String;
        await launchUrl(Uri.parse(checkout['gatewayUrl'] as String), mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final course = ref.watch(courseProvider(id));
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView(
        value: course,
        onRetry: () => ref.invalidate(courseProvider(id)),
        data: (c) {
          final text = Theme.of(context).textTheme;
          final enrolled = c['enrolled'] == true;
          final sections = c['sections'] as List;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(c['title'] as String, style: text.headlineSmall),
            if (c['subtitle'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(c['subtitle'] as String)),
            const SizedBox(height: 8),
            InkWell(
              onTap: () => context.push('/teachers/${c['teacher']['id']}'),
              child: Text('শিক্ষক: ${c['teacher']['name']}', style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.primary)),
            ),
            const SizedBox(height: 4),
            Text('${c['_count']['enrollments']} জন শিখছে'),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: enrolled || _busy ? null : () => _enroll(c),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(enrolled ? 'আপনি এনরোলড' : (c['isFree'] == true ? 'ফ্রি এনরোল করুন' : 'কিনুন ${price(c)}')),
              ),
            ),
            const SizedBox(height: 24),
            Text('কোর্স সম্পর্কে', style: text.titleMedium),
            const SizedBox(height: 8),
            Text(c['description'] as String),
            const SizedBox(height: 24),
            Text('কারিকুলাম', style: text.titleMedium),
            for (final s in sections)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                initiallyExpanded: true,
                title: Text(s['title'] as String),
                children: [
                  for (final l in s['lessons'] as List)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(enrolled || l['isPreview'] == true ? Icons.play_circle_outline : Icons.lock_outline),
                      title: Text(l['title'] as String),
                      subtitle: Text([duration(l['durationSec'] as int), if (l['isPreview'] == true) 'প্রিভিউ'].join(' · ')),
                      onTap: enrolled || l['isPreview'] == true ? () => context.push('/lessons/${l['id']}') : null,
                    ),
                ],
              ),
          ]);
        },
      ),
    );
  }
}

final lessonProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
    (ref, id) => ref.read(apiProvider).get('/lessons/$id'));

class LessonScreen extends ConsumerWidget {
  const LessonScreen(this.id, {super.key});
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lesson = ref.watch(lessonProvider(id));
    return Scaffold(
      appBar: AppBar(title: Text(lesson.value?['title'] as String? ?? '')),
      body: AsyncView(
        value: lesson,
        data: (l) => ListView(children: [
          if (l['mediaUrl'] != null && l['type'] == 'VIDEO')
            _Player(url: l['mediaUrl'] as String, onProgress: (sec, done) {
              if (!ref.read(authProvider).loggedIn) return;
              ref.read(apiProvider).post('/lessons/$id/progress', {'watchedSec': sec, if (done) 'completed': true}).ignore();
            }),
          if (l['content'] != null) Padding(padding: const EdgeInsets.all(16), child: Text(l['content'] as String)),
          if (l['mediaUrl'] == null && l['content'] == null)
            const EmptyState('এই লেসনের কনটেন্ট শীঘ্রই যোগ হবে', icon: Icons.video_file_outlined),
        ]),
      ),
    );
  }
}

class _Player extends StatefulWidget {
  const _Player({required this.url, required this.onProgress});
  final String url;
  final void Function(int seconds, bool done) onProgress;
  @override
  State<_Player> createState() => _PlayerState();
}

class _PlayerState extends State<_Player> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  int _lastReported = 0;

  @override
  void initState() {
    super.initState();
    _c.initialize().then((_) => setState(() {}));
    _c.addListener(_tick);
  }

  /// Reports progress every 15 seconds of playback and once at the end.
  void _tick() {
    final pos = _c.value.position.inSeconds;
    final done = _c.value.duration.inSeconds > 0 && pos >= _c.value.duration.inSeconds - 1;
    if (pos - _lastReported >= 15 || (done && _lastReported != pos)) {
      _lastReported = pos;
      widget.onProgress(pos, done);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_tick);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AspectRatio(
        aspectRatio: _c.value.isInitialized ? _c.value.aspectRatio : 16 / 9,
        child: !_c.value.isInitialized
            ? const ColoredBox(color: Colors.black, child: Center(child: CircularProgressIndicator()))
            : Stack(alignment: Alignment.bottomCenter, children: [
                VideoPlayer(_c),
                GestureDetector(onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play())),
                if (!_c.value.isPlaying) const Center(child: Icon(Icons.play_circle_fill, size: 64, color: Colors.white)),
                VideoProgressIndicator(_c, allowScrubbing: true),
              ]),
      );
}

final teacherProfileProvider = FutureProvider.autoDispose.family<Map<String, dynamic>, String>(
    (ref, id) => ref.read(apiProvider).get('/teachers/$id'));

class TeacherProfileScreen extends ConsumerWidget {
  const TeacherProfileScreen(this.id, {super.key});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(teacherProfileProvider(id));
    return Scaffold(
      appBar: AppBar(),
      body: AsyncView(
        value: profile,
        data: (p) {
          final user = p['user'] as Map<String, dynamic>;
          final text = Theme.of(context).textTheme;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(user['name'] as String, style: text.headlineSmall),
            Text(p['headline'] as String),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [for (final s in p['skills'] as List) Chip(label: Text(s as String))]),
            const SizedBox(height: 16),
            Text(p['bio'] as String),
            const SizedBox(height: 24),
            Text('পোর্টফোলিও', style: text.titleMedium),
            for (final item in user['portfolioItems'] as List)
              ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.link), title: Text(item['title'] as String), subtitle: Text(item['url'] as String)),
            const SizedBox(height: 16),
            Text('কোর্সসমূহ', style: text.titleMedium),
            for (final c in user['courses'] as List)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(c['title'] as String),
                trailing: Text(price(c as Map<String, dynamic>)),
                onTap: () => context.push('/courses/${c['id']}'),
              ),
          ]);
        },
      ),
    );
  }
}
