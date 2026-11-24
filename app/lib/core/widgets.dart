import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'format.dart';
import 'i18n.dart';
import 'theme.dart';

// ---------------------------------------------------------------------------
// Loading, errors, empty states
// ---------------------------------------------------------------------------

/// Renders an AsyncValue with a skeleton/spinner, a retry-able error, or the data.
class AsyncView<T> extends StatelessWidget {
  const AsyncView({super.key, required this.value, required this.data, this.onRetry, this.loading});
  final AsyncValue<T> value;
  final Widget Function(T) data;
  final VoidCallback? onRetry;
  final Widget? loading;

  @override
  Widget build(BuildContext context) => value.when(
        data: data,
        loading: () => loading ?? const Center(child: CircularProgressIndicator()),
        error: (e, _) => EmptyState(
          e.toString(),
          icon: Icons.cloud_off_outlined,
          action: onRetry == null ? null : OutlinedButton(onPressed: onRetry, child: Text(t('Try again', 'আবার চেষ্টা করুন'))),
        ),
      );
}

void showMessage(BuildContext context, Object message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message.toString())));

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined, this.title, this.action});
  final String text;
  final String? title;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: 0.6), shape: BoxShape.circle),
            child: Icon(icon, size: 40, color: scheme.primary),
          ),
          const SizedBox(height: 16),
          if (title != null) ...[
            Text(title!, style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 6),
          ],
          Text(text, textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ]),
      ),
    );
  }
}

/// Grey placeholder boxes shown while content loads (feels faster than a spinner).
class Skeleton extends StatefulWidget {
  const Skeleton({super.key, this.width, this.height = 14, this.radius = 8});
  final double? width;
  final double height;
  final double radius;
  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
        child: Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(widget.radius),
          ),
        ),
      );
}

class CourseRowSkeleton extends StatelessWidget {
  const CourseRowSkeleton({super.key});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 252,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 3,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, _) => const SizedBox(
            width: 232,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Skeleton(height: 130, radius: 14),
              SizedBox(height: 10),
              Skeleton(width: 200),
              SizedBox(height: 6),
              Skeleton(width: 140),
              SizedBox(height: 6),
              Skeleton(width: 90),
            ]),
          ),
        ),
      );
}

// ---------------------------------------------------------------------------
// Brand
// ---------------------------------------------------------------------------

/// The brain mark from the logo, tinted to fit light or dark backgrounds.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 28, this.color});
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) =>
      Image.asset('assets/brand/mark.png', width: size, height: size, color: color ?? Theme.of(context).colorScheme.primary);
}

/// "Tech.Dropout" wordmark with the orange D, like the logo.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 20, this.color, this.showMark = true});
  final double size;
  final Color? color;
  final bool showMark;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    final style = TextStyle(fontFamily: 'Poppins', fontSize: size, fontWeight: FontWeight.w700, color: c, letterSpacing: -0.3);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (showMark) ...[BrandMark(size: size * 1.35, color: c), SizedBox(width: size * 0.35)],
      // Same as the logo: "Tech.Dropout IT" with an orange D tilted to the left.
      Text.rich(TextSpan(style: style, children: [
        const TextSpan(text: 'Tech.'),
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: size * 0.04),
            child: Transform.rotate(
              angle: -0.27,
              child: Text('D', style: style.copyWith(color: Brand.orange, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
        const TextSpan(text: 'ropout IT'),
      ])),
    ]);
  }
}

/// EN | বাং switch shown in the top bar of every main screen.
class LangToggle extends ConsumerWidget {
  const LangToggle({super.key, this.onDark = false});
  final bool onDark;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(langProvider);
    final scheme = Theme.of(context).colorScheme;
    final border = onDark ? Colors.white54 : scheme.outlineVariant;
    Widget seg(String label, Lang value) {
      final on = lang == value;
      return GestureDetector(
        onTap: () => ref.read(langProvider.notifier).set(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on ? (onDark ? Colors.white : scheme.primary) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: on ? (onDark ? Brand.teal : scheme.onPrimary) : (onDark ? Colors.white : scheme.onSurfaceVariant),
            ),
          ),
        ),
      );
    }

    return Tooltip(
      message: t('Language', 'ভাষা'),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), border: Border.all(color: border)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [seg('EN', Lang.en), seg('বাং', Lang.bn)]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Course building blocks
// ---------------------------------------------------------------------------

Color hexColor(String? hex, [Color fallback = Brand.teal]) {
  if (hex == null || !hex.startsWith('#') || hex.length != 7) return fallback;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

IconData categoryIcon(String? name) => switch (name) {
      'code' => Icons.code_rounded,
      'phone' => Icons.phone_iphone_rounded,
      'brush' => Icons.brush_rounded,
      'campaign' => Icons.campaign_rounded,
      'work' => Icons.work_rounded,
      'translate' => Icons.translate_rounded,
      'analytics' => Icons.insights_rounded,
      'table' => Icons.table_chart_rounded,
      'camera' => Icons.photo_camera_rounded,
      'music' => Icons.music_note_rounded,
      'business' => Icons.business_center_rounded,
      'security' => Icons.security_rounded,
      _ => Icons.school_rounded,
    };

const categoryIconNames = ['code', 'phone', 'brush', 'campaign', 'work', 'translate', 'analytics', 'table', 'camera', 'music', 'business', 'security', 'school'];

/// Course image. Without an uploaded thumbnail it draws a branded cover from the
/// category colour and icon, so the catalogue always looks finished.
class CourseThumb extends StatelessWidget {
  const CourseThumb(this.course, {super.key, this.radius = 14, this.showTitle = true});
  final Map<String, dynamic> course;
  final double radius;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final url = course['thumbnailUrl'] as String?;
    final cat = course['category'] as Map<String, dynamic>?;
    final base = hexColor(cat?['color'] as String?);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color.lerp(base, Colors.black, 0.25)!, base, Color.lerp(base, Colors.white, 0.18)!],
        ),
      ),
      child: Stack(children: [
        Positioned(
          right: -18,
          bottom: -22,
          child: Icon(categoryIcon(cat?['icon'] as String?), size: 120, color: Colors.white.withValues(alpha: 0.13)),
        ),
        Positioned(
          left: -30,
          top: -30,
          child: Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.07)),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(8)),
                child: Icon(categoryIcon(cat?['icon'] as String?), size: 16, color: Colors.white),
              ),
              const Spacer(),
              Image.asset('assets/brand/mark.png', width: 18, color: Colors.white70),
            ]),
            const Spacer(),
            if (showTitle)
              Text(
                course['title'] as String? ?? '',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 14, height: 1.25),
              ),
          ]),
        ),
      ]),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: url == null || url.isEmpty
            ? fallback
            : Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
      ),
    );
  }
}

class Stars extends StatelessWidget {
  const Stars(this.rating, {super.key, this.count, this.size = 14, this.showNumber = true});
  final double rating;
  final int? count;
  final double size;
  final bool showNumber;
  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (showNumber) ...[
        Text(rating.toStringAsFixed(1), style: TextStyle(fontWeight: FontWeight.w700, fontSize: size, color: const Color(0xFFB4690E))),
        const SizedBox(width: 4),
      ],
      for (var i = 1; i <= 5; i++)
        Icon(
          rating >= i ? Icons.star_rounded : (rating >= i - 0.5 ? Icons.star_half_rounded : Icons.star_outline_rounded),
          size: size + 2,
          color: Brand.amber,
        ),
      if (count != null) ...[const SizedBox(width: 4), Text('(${compact(count!)})', style: TextStyle(fontSize: size - 1, color: muted))],
    ]);
  }
}

/// Price with the struck-through original next to it.
class PriceTag extends StatelessWidget {
  const PriceTag(this.course, {super.key, this.size = 16});
  final Map<String, dynamic> course;
  final double size;
  @override
  Widget build(BuildContext context) {
    final was = originalPrice(course);
    final free = course['isFree'] == true;
    return Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(
        catalogPrice(course),
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: size, color: free ? Brand.success : Theme.of(context).colorScheme.onSurface),
      ),
      if (was != null) ...[
        const SizedBox(width: 6),
        Text(
          was,
          style: TextStyle(
            fontSize: size - 3,
            decoration: TextDecoration.lineThrough,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ]);
  }
}

class Tag extends StatelessWidget {
  const Tag(this.label, {super.key, this.color, this.textColor, this.icon});
  final String label;
  final Color? color;
  final Color? textColor;
  final IconData? icon;

  factory Tag.bestseller() => Tag(t('Bestseller', 'বেস্টসেলার'), color: const Color(0xFFFFE9C7), textColor: const Color(0xFF7A4A00));
  factory Tag.free() => Tag(t('Free', 'ফ্রি'), color: const Color(0xFFD7F5E6), textColor: const Color(0xFF13633F));
  factory Tag.newCourse() => Tag(t('New', 'নতুন'), color: Brand.cyan, textColor: Brand.tealDeep);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color ?? Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 12, color: textColor), const SizedBox(width: 4)],
          Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: textColor ?? Theme.of(context).colorScheme.onSurface)),
        ]),
      );
}

List<Widget> courseTags(Map<String, dynamic> c) {
  final published = DateTime.tryParse(c['publishedAt'] as String? ?? '');
  return [
    if (c['isFeatured'] == true) Tag.bestseller(),
    if (c['isFree'] == true) Tag.free(),
    if (published != null && DateTime.now().difference(published).inDays < 30 && c['isFeatured'] != true) Tag.newCourse(),
  ];
}

/// Vertical card for horizontal carousels (Udemy-style).
class CourseCard extends StatelessWidget {
  const CourseCard(this.course, {super.key, this.width = 232});
  final Map<String, dynamic> course;
  final double width;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rating = (course['ratingAvg'] as num? ?? 0).toDouble();
    final tags = courseTags(course);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.push('/courses/${course['id']}'),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CourseThumb(course),
          const SizedBox(height: 10),
          Text(course['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(height: 1.3)),
          const SizedBox(height: 4),
          Text(
            (course['teacher'] as Map?)?['name'] as String? ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          if ((course['ratingCount'] as int? ?? 0) > 0) Stars(rating, count: course['ratingCount'] as int, size: 12),
          const SizedBox(height: 4),
          PriceTag(course, size: 15),
          if (tags.isNotEmpty) ...[const SizedBox(height: 6), Wrap(spacing: 6, children: tags)],
        ]),
      ),
    );
  }
}

/// Horizontal list row used in search results and lists.
class CourseTile extends StatelessWidget {
  const CourseTile(this.course, {super.key, this.trailing});
  final Map<String, dynamic> course;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final rating = (course['ratingAvg'] as num? ?? 0).toDouble();
    final tags = courseTags(course);
    return InkWell(
      onTap: () => context.push('/courses/${course['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 128, child: CourseThumb(course, radius: 10, showTitle: false)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(course['title'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(height: 1.3)),
              const SizedBox(height: 2),
              Text(
                (course['teacher'] as Map?)?['name'] as String? ?? '',
                maxLines: 1,
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              if ((course['ratingCount'] as int? ?? 0) > 0) Stars(rating, count: course['ratingCount'] as int, size: 12),
              const SizedBox(height: 2),
              PriceTag(course, size: 14),
              if (tags.isNotEmpty) ...[const SizedBox(height: 4), Wrap(spacing: 6, children: tags)],
            ]),
          ),
          ?trailing,
        ]),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {super.key, this.subtitle, this.onSeeAll, this.padding = const EdgeInsets.fromLTRB(16, 24, 8, 12)});
  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: text.titleLarge),
            if (subtitle != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(subtitle!, style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ),
          ]),
        ),
        if (onSeeAll != null) TextButton(onPressed: onSeeAll, child: Text(t('See all', 'সব দেখুন'))),
      ]),
    );
  }
}

/// Round avatar with initials and a colour picked from the name.
class Avatar extends StatelessWidget {
  const Avatar(this.name, {super.key, this.url, this.radius = 22});
  final String name;
  final String? url;
  final double radius;
  static const _colors = [Brand.teal, Color(0xFF2F6F8F), Color(0xFFE07A45), Color(0xFFB5508A), Color(0xFF3E8E6A), Color(0xFF6B5BD2)];
  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initials = parts.isEmpty ? '?' : parts.take(2).map((p) => p.characters.first.toUpperCase()).join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: _colors[name.hashCode.abs() % _colors.length],
      foregroundImage: url != null && url!.isNotEmpty ? NetworkImage(url!) : null,
      child: Text(initials, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: radius * 0.72)),
    );
  }
}

/// The main call to action (Enroll, Buy, Book): brand orange, full width.
class CtaButton extends StatelessWidget {
  const CtaButton({super.key, required this.label, this.onPressed, this.icon, this.busy = false});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;
  @override
  Widget build(BuildContext context) => FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.secondary,
          foregroundColor: Theme.of(context).colorScheme.onSecondary,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: 'Poppins', fontFamilyFallback: ['HindSiliguri']),
        ),
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                if (icon != null) ...[Icon(icon, size: 20), const SizedBox(width: 8)],
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ]),
      );
}

/// White rounded panel for grouping content on the light canvas.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(16), this.margin = EdgeInsets.zero, this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Card(child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child))),
      );
}

/// A progress bar with the percentage next to it.
class ProgressLine extends StatelessWidget {
  const ProgressLine(this.pct, {super.key});
  final int pct;
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: pct / 100, minHeight: 6),
          ),
        ),
        const SizedBox(width: 8),
        Text('$pct%', style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
      ]);
}

/// Small coloured square with an icon (dashboards, menus).
class IconBadge extends StatelessWidget {
  const IconBadge(this.icon, {super.key, this.color, this.size = 40});
  final IconData icon;
  final Color? color;
  final double size;
  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(icon, color: c, size: size * 0.55),
    );
  }
}

/// Grouped settings-style menu (profile, admin).
class MenuGroup extends StatelessWidget {
  const MenuGroup({super.key, this.title, required this.items});
  final String? title;
  final List<Widget> items;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
              child: Text(
                title!.toUpperCase(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 0.8,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          Card(
            child: Column(children: [
              for (var i = 0; i < items.length; i++) ...[if (i > 0) const Divider(indent: 64), items[i]],
            ]),
          ),
        ]),
      );
}

class MenuItem extends StatelessWidget {
  const MenuItem({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.color, this.trailing});
  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Color? color;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: IconBadge(icon, color: color, size: 36),
        title: Text(title, style: color != null && color == Theme.of(context).colorScheme.error ? TextStyle(color: color) : null),
        subtitle: subtitle == null ? null : Text(subtitle!),
        trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      );
}
