import 'package:material_ui/material_ui.dart';

/// Brand palette, taken from the Tech.Dropout IT logo.
class Brand {
  static const teal = Color(0xFF355457); // logo background
  static const tealDark = Color(0xFF243B3D);
  static const tealDeep = Color(0xFF1A2C2E);
  static const cyan = Color(0xFFC6FBFF); // logo brain
  static const cyanSoft = Color(0xFFE8FDFF);
  static const orange = Color(0xFFF0955F); // the "D" in the logo
  static const orangeStrong = Color(0xFFE0703A); // buttons: readable with white text
  static const amber = Color(0xFFF5A524); // rating stars
  static const success = Color(0xFF2E9E6A);
  static const ink = Color(0xFF14262A);
  static const muted = Color(0xFF5E7275);
  static const line = Color(0xFFE1EAEB);
  static const canvas = Color(0xFFF5F9F9);

  /// Gradient used on the home banner, course placeholders and headers.
  /// Instructor screens: warm orange from the logo's D into teal.
  static const teachGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [tealDark, Color(0xFF4A3B30), Color(0xFFB8572B)],
  );
  /// Affiliate screens: teal into a deep blue-green, so partners see a third look.
  static const affiliateGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [tealDeep, Color(0xFF1E4A5C), Color(0xFF2B7A78)],
  );
  static const heroGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF2B4648), teal, Color(0xFF3F6B6E)],
  );
}

/// Corner radii and spacing used everywhere, so screens feel like one product.
class Gap {
  static const xs = 4.0, s = 8.0, m = 12.0, l = 16.0, xl = 24.0, xxl = 32.0;
}

const _fonts = ['HindSiliguri'];

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark
      ? const ColorScheme.dark(
          primary: Color(0xFF8FE3EA),
          onPrimary: Brand.tealDeep,
          primaryContainer: Color(0xFF2D4C4F),
          onPrimaryContainer: Brand.cyan,
          secondary: Brand.orange,
          onSecondary: Color(0xFF3A1A08),
          secondaryContainer: Color(0xFF5A3420),
          onSecondaryContainer: Color(0xFFFFDCC8),
          tertiary: Brand.amber,
          surface: Color(0xFF132326),
          onSurface: Color(0xFFE3EEEF),
          onSurfaceVariant: Color(0xFFA9BDBF),
          surfaceContainerLowest: Color(0xFF0E1B1D),
          surfaceContainerLow: Color(0xFF172A2D),
          surfaceContainer: Color(0xFF1B3033),
          surfaceContainerHigh: Color(0xFF213739),
          surfaceContainerHighest: Color(0xFF283F42),
          outline: Color(0xFF5F7678),
          outlineVariant: Color(0xFF2E4447),
          error: Color(0xFFFFB4AB),
        )
      : const ColorScheme.light(
          primary: Brand.teal,
          onPrimary: Colors.white,
          primaryContainer: Brand.cyan,
          onPrimaryContainer: Brand.tealDeep,
          secondary: Brand.orangeStrong,
          onSecondary: Colors.white,
          secondaryContainer: Color(0xFFFFE3D2),
          onSecondaryContainer: Color(0xFF6B2E0E),
          tertiary: Brand.amber,
          surface: Colors.white,
          onSurface: Brand.ink,
          onSurfaceVariant: Brand.muted,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Brand.canvas,
          surfaceContainer: Color(0xFFEFF5F5),
          surfaceContainerHigh: Color(0xFFE8F0F1),
          surfaceContainerHighest: Color(0xFFE0EAEB),
          outline: Color(0xFFB4C5C7),
          outlineVariant: Brand.line,
          error: Color(0xFFC6362B),
        );

  final base = ThemeData(brightness: brightness, useMaterial3: true, fontFamily: 'Poppins', fontFamilyFallback: _fonts);
  final text = base.textTheme
      .copyWith(
        displaySmall: base.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.4),
        headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
        titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, fontSize: 20),
        titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        titleSmall: base.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        labelLarge: base.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.45),
        bodyLarge: base.textTheme.bodyLarge?.copyWith(height: 1.5),
      )
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface, fontFamily: 'Poppins', fontFamilyFallback: _fonts);

  final radius = BorderRadius.circular(14);
  const buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12)));
  const buttonPadding = EdgeInsets.symmetric(horizontal: 20, vertical: 14);
  const buttonMin = Size(64, 48); // 48dp touch target everywhere
  OutlineInputBorder field(Color c, [double w = 1]) =>
      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: c, width: w));

  return base.copyWith(
    colorScheme: scheme,
    textTheme: text,
    scaffoldBackgroundColor: dark ? scheme.surfaceContainerLowest : Brand.canvas,
    appBarTheme: AppBarTheme(
      backgroundColor: dark ? scheme.surfaceContainerLowest : Brand.canvas,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
    ),
    cardTheme: CardThemeData(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: scheme.outlineVariant)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(shape: buttonShape, padding: buttonPadding, minimumSize: buttonMin, textStyle: text.labelLarge?.copyWith(fontSize: 15)),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: buttonShape,
        padding: buttonPadding,
        minimumSize: buttonMin,
        side: BorderSide(color: scheme.outline),
        textStyle: text.labelLarge?.copyWith(fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(textStyle: text.labelLarge, shape: buttonShape)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? scheme.surfaceContainer : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      // Labels always sit on the border, so a filled-in form still says what each box is
      // and the hint inside can show an example.
      floatingLabelBehavior: FloatingLabelBehavior.always,
      labelStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, fontWeight: FontWeight.w500),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith((s) => text.bodyMedium!.copyWith(
            fontWeight: FontWeight.w600,
            color: s.contains(WidgetState.error) ? scheme.error : (s.contains(WidgetState.focused) ? scheme.primary : scheme.onSurfaceVariant),
          )),
      hintStyle: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.7)),
      helperStyle: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      helperMaxLines: 3,
      errorMaxLines: 3,
      prefixIconColor: WidgetStateColor.resolveWith((s) => s.contains(WidgetState.focused) ? scheme.primary : scheme.onSurfaceVariant),
      border: field(scheme.outlineVariant),
      enabledBorder: field(scheme.outlineVariant),
      disabledBorder: field(scheme.outlineVariant.withValues(alpha: 0.5)),
      focusedBorder: field(scheme.primary, 1.6),
      errorBorder: field(scheme.error),
      focusedErrorBorder: field(scheme.error, 1.6),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.secondary,
      foregroundColor: scheme.onSecondary,
      elevation: 2,
      highlightElevation: 4,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
      extendedTextStyle: text.labelLarge?.copyWith(fontSize: 15),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: scheme.primaryContainer,
        selectedForegroundColor: scheme.onPrimaryContainer,
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: text.labelLarge,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : null),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Brand.success : null),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.transparent : null),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(), // iOS keeps its native slide
    }),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: BorderRadius.circular(8)),
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
    chipTheme: ChipThemeData(
      shape: const StadiumBorder(),
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: scheme.surface,
      selectedColor: scheme.primaryContainer,
      labelStyle: text.labelLarge?.copyWith(fontSize: 13),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: dark ? scheme.primaryContainer : Brand.cyan,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelSmall?.copyWith(
          fontWeight: s.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
          color: s.contains(WidgetState.selected) ? scheme.primary : scheme.onSurfaceVariant,
        ),
      ),
    ),
    tabBarTheme: TabBarThemeData(
      labelStyle: text.titleSmall,
      unselectedLabelStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w500),
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: scheme.outlineVariant,
    ),
    listTileTheme: ListTileThemeData(iconColor: scheme.onSurfaceVariant, titleTextStyle: text.titleSmall?.copyWith(fontWeight: FontWeight.w500)),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.secondary, linearTrackColor: scheme.surfaceContainerHighest),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      showDragHandle: true,
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    ),
    dialogTheme: DialogThemeData(
      surfaceTintColor: Colors.transparent,
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: text.titleLarge,
    ),
  );
}
