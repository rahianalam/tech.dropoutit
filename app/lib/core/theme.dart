import 'package:material_ui/material_ui.dart';

const brand = Color(0xFF5B3DF5);

ThemeData buildTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: brand, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
    cardTheme: const CardThemeData(margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias),
  );
}
