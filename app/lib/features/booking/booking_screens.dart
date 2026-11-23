import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import '../../core/i18n.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/auth.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';

final _day = DateFormat('EEE, d MMM');
final _time = DateFormat('h:mm a');
final _full = DateFormat('EEE, d MMM · h:mm a');

final slotsProvider = FutureProvider.autoDispose.family<List<dynamic>, String>(
    (ref, teacherId) => ref.read(apiProvider).get('/teachers/$teacherId/slots', query: {'days': '14'}));

/// Student picks a free slot (shown in the phone's local time) and pays.
class BookSessionScreen extends ConsumerStatefulWidget {
  const BookSessionScreen(this.teacherId, {super.key, this.teacherName});
  final String teacherId;
  final String? teacherName;
  @override
  ConsumerState<BookSessionScreen> createState() => _BookSessionScreenState();
}

class _BookSessionScreenState extends ConsumerState<BookSessionScreen> with WidgetsBindingObserver {
  Map<String, dynamic>? _picked;
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingOrder != null) _check();
  }

  Future<void> _check() async {
    for (var i = 0; i < 6; i++) {
      final o = await ref.read(apiProvider).get<Map<String, dynamic>>('/orders/$_pendingOrder');
      if (o['status'] == 'PAID') {
        _pendingOrder = null;
        if (mounted) {
          showMessage(context, t('Session confirmed!', 'সেশন নিশ্চিত হয়েছে!'));
          context.go('/learning?tab=sessions');
        }
        return;
      }
      if (o['status'] != 'PENDING') break;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    if (mounted) showMessage(context, t('Payment not confirmed yet. The slot is held for you for 10 minutes.', 'পেমেন্ট এখনো নিশ্চিত হয়নি। স্লটটি ১০ মিনিট আপনার জন্য রাখা আছে।'));
  }

  Future<void> _book() async {
    if (!ref.read(authProvider).loggedIn) return context.go('/login');
    final slot = _picked!;
    setState(() => _busy = true);
    try {
      final res = await ref.read(apiProvider).post<Map<String, dynamic>>('/bookings', {'teacherId': widget.teacherId, 'startAt': slot['startAt']});
      if (res['gatewayUrl'] == null) {
        if (mounted) {
          showMessage(context, t('Free session confirmed!', 'ফ্রি সেশন নিশ্চিত হয়েছে!'));
          context.go('/learning?tab=sessions');
        }
        return;
      }
      _pendingOrder = res['orderId'] as String;
      await launchUrl(Uri.parse(res['gatewayUrl'] as String), mode: LaunchMode.externalApplication);
    } catch (e) {
      ref.invalidate(slotsProvider(widget.teacherId));
      if (mounted) showMessage(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final slots = ref.watch(slotsProvider(widget.teacherId));
    return Scaffold(
      appBar: AppBar(title: Text(widget.teacherName == null ? t('Book a session', 'সেশন বুক করুন') : t('Session with ${widget.teacherName}', '${widget.teacherName}-এর সাথে সেশন'))),
      bottomNavigationBar: _picked == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  onPressed: _busy ? null : _book,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text('${_full.format(DateTime.parse(_picked!['startAt'] as String).toLocal())} · '
                        '${t('${_picked!['pricePaisa'] == 0 ? 'Free' : taka(_picked!['pricePaisa'] as int)} — Book now', '${_picked!['pricePaisa'] == 0 ? 'ফ্রি' : taka(_picked!['pricePaisa'] as int)} — বুক করুন')}'),
                  ),
                ),
              ),
            ),
      body: AsyncView(
        value: slots,
        onRetry: () => ref.invalidate(slotsProvider(widget.teacherId)),
        data: (list) {
          if (list.isEmpty) return EmptyState(t('No free time in the next 2 weeks', 'আগামী ২ সপ্তাহে কোনো খালি সময় নেই'), icon: Icons.event_busy);
          final byDay = <String, List<Map<String, dynamic>>>{};
          for (final s in list.cast<Map<String, dynamic>>()) {
            byDay.putIfAbsent(_day.format(DateTime.parse(s['startAt'] as String).toLocal()), () => []).add(s);
          }
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(t('Times are shown in your phone\'s time zone.', 'সময়গুলো আপনার ফোনের সময় অনুযায়ী দেখানো হচ্ছে।'), style: Theme.of(context).textTheme.bodySmall),
            for (final entry in byDay.entries) ...[
              const SizedBox(height: 16),
              Text(entry.key, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final s in entry.value)
                  ChoiceChip(
                    label: Text(t('${_time.format(DateTime.parse(s['startAt'] as String).toLocal())} · ${s['pricePaisa'] == 0 ? 'Free' : taka(s['pricePaisa'] as int)}', '${_time.format(DateTime.parse(s['startAt'] as String).toLocal())} · ${s['pricePaisa'] == 0 ? 'ফ্রি' : taka(s['pricePaisa'] as int)}')),
                    selected: _picked?['startAt'] == s['startAt'],
                    onSelected: (_) => setState(() => _picked = s),
                  ),
              ]),
            ],
          ]);
        },
      ),
    );
  }
}

final myBookingsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/me/bookings'));
final teacherBookingsProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/teacher/bookings'));

Map<String, String> get _status => {'CONFIRMED': t('Confirmed', 'নিশ্চিত'), 'COMPLETED': t('Completed', 'সম্পন্ন'), 'CANCELLED': t('Cancel', 'বাতিল'), 'NO_SHOW': t('No-show', 'অনুপস্থিত')};

/// A session card with Join (opens 15 minutes before), cancel, complete and review actions.
class BookingTile extends ConsumerWidget {
  const BookingTile(this.b, {super.key, required this.asTeacher});
  final Map<String, dynamic> b;
  final bool asTeacher;

  Future<void> _act(BuildContext context, WidgetRef ref, Future<Object?> Function() fn, String done) async {
    try {
      await fn();
      ref.invalidate(asTeacher ? teacherBookingsProvider : myBookingsProvider);
      if (context.mounted) showMessage(context, done);
    } catch (e) {
      if (context.mounted) showMessage(context, e);
    }
  }

  Future<String?> _ask(BuildContext context, String title, String label) async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(controller: c, maxLines: 3, decoration: InputDecoration(labelText: label)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel', 'বাতিল'))),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Send', 'পাঠান'))),
        ],
      ),
    );
    return ok == true ? c.text.trim() : null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final api = ref.read(apiProvider);
    final start = DateTime.parse(b['startAt'] as String).toLocal();
    final end = DateTime.parse(b['endAt'] as String).toLocal();
    final now = DateTime.now();
    final status = b['status'] as String;
    final confirmed = status == 'CONFIRMED';
    final canJoin = confirmed && now.isAfter(start.subtract(Duration(minutes: 15))) && now.isBefore(end.add(Duration(minutes: 30)));
    final started = now.isAfter(start);
    final other = (asTeacher ? b['student'] : b['teacher']) as Map<String, dynamic>;
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        ListTile(
          leading: const Icon(Icons.video_call_outlined),
          title: Text(other['name'] as String),
          subtitle: Text('${_full.format(start)} – ${_time.format(end)} · ${_status[status] ?? status}'),
        ),
        OverflowBar(alignment: MainAxisAlignment.end, spacing: 4, children: [
          if (confirmed && !started)
            TextButton(
              onPressed: () => _act(context, ref, () => api.post('/bookings/${b['id']}/cancel'), t('Session cancelled', 'সেশন বাতিল হয়েছে')),
              child: Text(t('Cancel', 'বাতিল')),
            ),
          if (asTeacher && confirmed && started) ...[
            TextButton(
              onPressed: () => _act(context, ref, () => api.post('/bookings/${b['id']}/complete', {'outcome': 'NO_SHOW'}), t('Marked as no-show', 'অনুপস্থিত হিসেবে চিহ্নিত')),
              child: Text(t('Student didn\'t come', 'স্টুডেন্ট আসেনি')),
            ),
            FilledButton.tonal(
              onPressed: () => _act(context, ref, () => api.post('/bookings/${b['id']}/complete', {'outcome': 'COMPLETED'}), t('Completed', 'সম্পন্ন')),
              child: Text(t('Completed', 'সম্পন্ন')),
            ),
          ],
          if (!asTeacher && confirmed && started)
            TextButton(
              onPressed: () async {
                final reason = await _ask(context, t('Report a problem', 'সমস্যা জানান'), t('What happened?', 'কী হয়েছিল?'));
                if (reason != null && context.mounted) await _act(context, ref, () => api.post('/bookings/${b['id']}/report', {'reason': reason}), t('The admin has been told', 'অ্যাডমিনকে জানানো হয়েছে'));
              },
              child: Text(t('Report a problem', 'সমস্যা জানান')),
            ),
          if (!asTeacher && status == 'COMPLETED' && b['review'] == null)
            TextButton(
              onPressed: () async {
                final r = await askRating(context, t('How was the session?', 'সেশনটি কেমন ছিল?'));
                if (r != null && context.mounted) await _act(context, ref, () => api.post('/bookings/${b['id']}/review', {'rating': r}), t('Thank you!', 'ধন্যবাদ!'));
              },
              child: Text(t('Leave a review', 'রিভিউ দিন')),
            ),
          if (canJoin && b['meetingUrl'] != null)
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse(b['meetingUrl'] as String), mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.videocam),
              label: Text(t('Join', 'জয়েন করুন')),
            ),
          const SizedBox(width: 8),
        ]),
      ]),
    );
  }
}

class MySessionsList extends ConsumerWidget {
  const MySessionsList({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(myBookingsProvider);
    return AsyncView(
      value: list,
      onRetry: () => ref.invalidate(myBookingsProvider),
      data: (items) => items.isEmpty
          ? EmptyState(t('You haven\'t booked any sessions. Book one from a teacher\'s profile.', 'কোনো সেশন বুক করেননি। টিচারের প্রোফাইল থেকে সেশন বুক করুন।'), icon: Icons.event_available_outlined)
          : RefreshIndicator(
              onRefresh: () => ref.refresh(myBookingsProvider.future),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => BookingTile(items[i] as Map<String, dynamic>, asTeacher: false),
              ),
            ),
    );
  }
}

class TeacherSessionsScreen extends ConsumerWidget {
  const TeacherSessionsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(teacherBookingsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('My sessions', 'আমার সেশন')), actions: [
        TextButton.icon(onPressed: () => context.push('/teacher/availability'), icon: Icon(Icons.schedule), label: Text(t('Schedule', 'সময়সূচি'))),
      ]),
      body: AsyncView(
        value: list,
        onRetry: () => ref.invalidate(teacherBookingsProvider),
        data: (items) => items.isEmpty
            ? EmptyState(t('No bookings yet. Add your schedule so students can book you.', 'এখনো কোনো বুকিং নেই। সময়সূচি দিলে স্টুডেন্টরা বুক করতে পারবে।'), icon: Icons.event_note_outlined)
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => BookingTile(items[i] as Map<String, dynamic>, asTeacher: true),
              ),
      ),
    );
  }
}

final availabilityProvider = FutureProvider.autoDispose<List<dynamic>>((ref) => ref.read(apiProvider).get('/teacher/availability'));
List<String> get _weekdays => [t('Sunday', 'রবিবার'), t('Monday', 'সোমবার'), t('Tuesday', 'মঙ্গলবার'), t('Wednesday', 'বুধবার'), t('Thursday', 'বৃহস্পতিবার'), t('Friday', 'শুক্রবার'), t('Saturday', 'শনিবার')];

/// Weekly schedule editor: one or more time windows per weekday, slot length and price.
class AvailabilityScreen extends ConsumerStatefulWidget {
  const AvailabilityScreen({super.key});
  @override
  ConsumerState<AvailabilityScreen> createState() => _AvailabilityScreenState();
}

class _AvailabilityScreenState extends ConsumerState<AvailabilityScreen> {
  List<Map<String, int>>? _rules;

  String _hm(int m) => _time.format(DateTime(2000, 1, 1, m ~/ 60, m % 60));

  Future<void> _add() async {
    var weekday = 5;
    var start = const TimeOfDay(hour: 19, minute: 0);
    var end = const TimeOfDay(hour: 21, minute: 0);
    var slot = 60;
    final price = TextEditingController(text: '500');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(t('Add a time', 'সময় যোগ করুন')),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              initialValue: weekday,
              items: [for (var i = 0; i < 7; i++) DropdownMenuItem(value: i, child: Text(_weekdays[i]))],
              onChanged: (v) => set(() => weekday = v!),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('Start: ${start.format(ctx)}', 'শুরু: ${start.format(ctx)}')),
              onTap: () async {
                final t = await showTimePicker(context: ctx, initialTime: start);
                if (t != null) set(() => start = t);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(t('End: ${end.format(ctx)}', 'শেষ: ${end.format(ctx)}')),
              onTap: () async {
                final t = await showTimePicker(context: ctx, initialTime: end);
                if (t != null) set(() => end = t);
              },
            ),
            DropdownButtonFormField<int>(
              initialValue: slot,
              decoration: InputDecoration(labelText: t('Length of each session', 'প্রতি সেশনের দৈর্ঘ্য')),
              items: [for (final m in [30, 45, 60, 90, 120]) DropdownMenuItem(value: m, child: Text(t('$m minutes', '$m মিনিট')))],
              onChanged: (v) => set(() => slot = v!),
            ),
            const SizedBox(height: 12),
            TextField(controller: price, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: t('Price per session (BDT, 0 = free)', 'প্রতি সেশনের দাম (টাকা, ০ = ফ্রি)'))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(t('Cancel', 'বাতিল'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(t('Add', 'যোগ করুন'))),
          ],
        ),
      ),
    );
    if (ok != true) return;
    setState(() => _rules!.add({
          'weekday': weekday,
          'startMinute': start.hour * 60 + start.minute,
          'endMinute': end.hour * 60 + end.minute,
          'slotMinutes': slot,
          'priceBdt': int.tryParse(price.text) ?? 0,
        }));
  }

  Future<void> _save() async {
    try {
      await ref.read(apiProvider).dio.put('/teacher/availability', data: {'rules': _rules});
      ref.invalidate(availabilityProvider);
      if (mounted) showMessage(context, t('Schedule saved', 'সময়সূচি সেভ হয়েছে'));
    } catch (e) {
      if (mounted) showMessage(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = ref.watch(availabilityProvider);
    return Scaffold(
      appBar: AppBar(title: Text(t('Weekly schedule', 'সাপ্তাহিক সময়সূচি')), actions: [TextButton(onPressed: _rules == null ? null : _save, child: Text(t('Save', 'সেভ')))]),
      floatingActionButton: FloatingActionButton(onPressed: _rules == null ? null : _add, child: const Icon(Icons.add)),
      body: AsyncView(
        value: data,
        data: (rules) {
          _rules ??= [
            for (final r in rules)
              {
                'weekday': r['weekday'] as int,
                'startMinute': r['startMinute'] as int,
                'endMinute': r['endMinute'] as int,
                'slotMinutes': r['slotMinutes'] as int,
                'priceBdt': (r['pricePaisa'] as int) ~/ 100,
              },
          ];
          final sorted = [..._rules!]..sort((a, b) => (a['weekday']! * 1440 + a['startMinute']!) - (b['weekday']! * 1440 + b['startMinute']!));
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text(t('Add the times you can teach (Bangladesh time). Students only see free slots.', 'যে সময়গুলোতে আপনি পড়াতে পারবেন সেগুলো যোগ করুন (বাংলাদেশ সময়)। স্টুডেন্টরা শুধু খালি স্লট দেখবে।')),
            const SizedBox(height: 12),
            if (sorted.isEmpty) EmptyState(t('No times added yet', 'এখনো কোনো সময় যোগ করেননি'), icon: Icons.schedule),
            for (final r in sorted)
              Card(
                child: ListTile(
                  title: Text('${_weekdays[r['weekday']!]} · ${_hm(r['startMinute']!)} – ${_hm(r['endMinute']!)}'),
                  subtitle: Text(t('${r['slotMinutes']} min · ${r['priceBdt'] == 0 ? 'Free' : '৳${r['priceBdt']}'}', '${r['slotMinutes']} মিনিট · ${r['priceBdt'] == 0 ? 'ফ্রি' : '৳${r['priceBdt']}'}')),
                  trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => _rules!.remove(r))),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// 1–5 star picker shared by session and course reviews.
Future<int?> askRating(BuildContext context, String title) => showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(title: Text(title), children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          for (var i = 1; i <= 5; i++)
            IconButton(tooltip: '$i', icon: const Icon(Icons.star, color: Colors.amber), onPressed: () => Navigator.pop(ctx, i)),
        ]),
      ]),
    );
