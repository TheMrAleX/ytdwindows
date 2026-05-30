import 'package:flutter/material.dart';

import 'screens/home_screen.dart';

void main(List<String> args) {
  runApp(YtdlinuxApp(launchArgs: args));
}

class YtdlinuxApp extends StatelessWidget {
  final List<String> launchArgs;
  const YtdlinuxApp({super.key, this.launchArgs = const []});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ytdlinux',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.system,
      theme: _build(Brightness.light),
      darkTheme: _build(Brightness.dark),
      home: HomeScreen(launchArgs: launchArgs),
    );
  }

  ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    // Paleta Mint-Y inspirada — accent verde Aron (Linux Mint).
    const accent = Color(0xFF3A8A45);
    final surface = dark ? const Color(0xFF2A2A2A) : const Color(0xFFFAFAFA);
    final surfaceContainer = dark ? const Color(0xFF333333) : const Color(0xFFF1F1F1);
    final surfaceContainerHighest =
        dark ? const Color(0xFF3A3A3A) : const Color(0xFFE6E6E6);
    final outline = dark ? const Color(0xFF4A4A4A) : const Color(0xFFD0D0D0);
    final onSurface = dark ? const Color(0xFFE0E0E0) : const Color(0xFF222222);

    final scheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: b,
      primary: accent,
      onPrimary: Colors.white,
      surface: surface,
      surfaceContainer: surfaceContainer,
      surfaceContainerHighest: surfaceContainerHighest,
      surfaceContainerLow: dark ? const Color(0xFF303030) : const Color(0xFFF5F5F5),
      surfaceContainerLowest: dark ? const Color(0xFF252525) : Colors.white,
      onSurface: onSurface,
      outline: outline,
      outlineVariant: dark ? const Color(0xFF3A3A3A) : const Color(0xFFE0E0E0),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: b,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      fontFamily: 'Ubuntu Sans',
      fontFamilyFallback: const ['Ubuntu', 'Cantarell', 'Roboto', 'Noto Sans'],
      visualDensity: VisualDensity.compact,
      splashFactory: InkSparkle.splashFactory,
      dividerColor: outline,
      dividerTheme: DividerThemeData(color: outline, thickness: 1, space: 1),
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceContainer,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 56,
        shape: Border(bottom: BorderSide(color: outline, width: 1)),
        titleTextStyle: TextStyle(
          color: onSurface,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          fontFamily: 'Ubuntu Sans',
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xFF252525) : Colors.white,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: accent, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(fontSize: 13),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          padding: const EdgeInsets.all(6),
          minimumSize: const Size(32, 32),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1A1A1A) : const Color(0xFF333333),
          borderRadius: BorderRadius.circular(4),
        ),
        textStyle: const TextStyle(color: Colors.white, fontSize: 12),
        waitDuration: const Duration(milliseconds: 400),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: outline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainer,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent,
        linearTrackColor: surfaceContainerHighest,
      ),
      chipTheme: ChipThemeData(
        side: BorderSide(color: outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        labelStyle: const TextStyle(fontSize: 12),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
      ),
    );
  }
}
