import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../packages/element_type.dart';
import 'palettes.dart';

/// Design-Tokens von CHAKOTAY.
///
/// Die Farbwerte stammen aus den kontrastgeprüften Schemata in
/// `palettes.dart` (WCAG AA ≥ 4,5:1 für Text bis 17 pt, HIG `color.md`).
/// Jedes Schema liefert eine helle und eine dunkle Variante.
///
/// Signatur: das „Kalenderblatt“ – Datumskachel in Liturgiefarbe, die jeden
/// Gottesdienst wie im Kirchenkalender verortet.
class ChakotayColors extends ThemeExtension<ChakotayColors> {
  const ChakotayColors({
    required this.liturgy,
    required this.liturgyContainer,
    required this.song,
    required this.songContainer,
    required this.warning,
    required this.warningContainer,
    required this.success,
    required this.card,
    required this.separator,
  });

  final Color liturgy;
  final Color liturgyContainer;
  final Color song;
  final Color songContainer;
  final Color warning;
  final Color warningContainer;
  final Color success;
  final Color card;
  final Color separator;

  factory ChakotayColors.from(SchemeColors c) => ChakotayColors(
    liturgy: c.liturgy,
    liturgyContainer: c.liturgyContainer,
    song: c.accent,
    songContainer: c.accentContainer,
    warning: c.warning,
    warningContainer: c.warningContainer,
    success: c.accent,
    card: c.card,
    separator: c.onSurface.withValues(alpha: 0.12),
  );

  static ChakotayColors of(BuildContext context) =>
      Theme.of(context).extension<ChakotayColors>()!;

  @override
  ChakotayColors copyWith() => this;

  @override
  ChakotayColors lerp(ChakotayColors? other, double t) {
    if (other == null) return this;
    return ChakotayColors(
      liturgy: Color.lerp(liturgy, other.liturgy, t)!,
      liturgyContainer: Color.lerp(
        liturgyContainer,
        other.liturgyContainer,
        t,
      )!,
      song: Color.lerp(song, other.song, t)!,
      songContainer: Color.lerp(songContainer, other.songContainer, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      warningContainer: Color.lerp(
        warningContainer,
        other.warningContainer,
        t,
      )!,
      success: Color.lerp(success, other.success, t)!,
      card: Color.lerp(card, other.card, t)!,
      separator: Color.lerp(separator, other.separator, t)!,
    );
  }
}

ThemeData buildTheme(
  Brightness brightness, [
  AppColorScheme colorScheme = AppColorScheme.chapelGreen,
]) {
  final isDark = brightness == Brightness.dark;
  final c = colorScheme.colors(brightness);
  final tokens = ChakotayColors.from(c);
  final accent = c.accent;
  final surface = c.surface;
  final onSurface = c.onSurface;
  final secondaryText = c.secondary;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: c.onAccent,
    primaryContainer: tokens.songContainer,
    onPrimaryContainer: c.onAccentContainer,
    secondary: tokens.liturgy,
    onSecondary: isDark ? c.surface : Colors.white,
    secondaryContainer: tokens.liturgyContainer,
    onSecondaryContainer: onSurface,
    error: isDark ? const Color(0xFFFF8A80) : const Color(0xFFB3261E),
    onError: isDark ? const Color(0xFF3B0907) : Colors.white,
    surface: surface,
    onSurface: onSurface,
    onSurfaceVariant: secondaryText,
    surfaceContainerLowest: tokens.card,
    surfaceContainerLow: tokens.card,
    surfaceContainer: tokens.card,
    surfaceContainerHigh: c.high,
    surfaceContainerHighest: c.highest,
    outline: c.outline,
    outlineVariant: tokens.separator,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    scaffoldBackgroundColor: surface,
    splashFactory: InkSparkle.splashFactory,
    extensions: [tokens],
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );

  final text = base.textTheme.apply(
    bodyColor: onSurface,
    displayColor: onSurface,
  );

  return base.copyWith(
    textTheme: text.copyWith(
      // Mobile Standard 17 pt (HIG typography.md), Fußnoten ≥ 13 pt.
      bodyLarge: text.bodyLarge?.copyWith(fontSize: 17, height: 1.3),
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 15, height: 1.3),
      bodySmall: text.bodySmall?.copyWith(fontSize: 13, color: secondaryText),
      titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      titleMedium: text.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
      labelLarge: text.labelLarge?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      headlineSmall: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      foregroundColor: onSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.nav.withValues(alpha: 0.95),
      indicatorColor: tokens.songContainer,
      surfaceTintColor: Colors.transparent,
      height: 64,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
        ),
      ),
    ),
    cardTheme: CardThemeData(
      color: tokens.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    listTileTheme: ListTileThemeData(
      minTileHeight: 52,
      iconColor: secondaryText,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(44, 44),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.separator),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: tokens.separator),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    dividerTheme: DividerThemeData(
      color: tokens.separator,
      thickness: 0.5,
      space: 0.5,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: accent,
      linearTrackColor: scheme.surfaceContainerHighest,
      // ignore: deprecated_member_use
      year2023: false,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
    ),
    cupertinoOverrideTheme: CupertinoThemeData(primaryColor: accent),
  );
}

/// Farbe eines Elementtyps: Akzent (Lied), Liturgiefarbe oder neutral.
/// Name **und** Farbe kennzeichnen die Art – nie die Farbe allein.
extension ElementTypeColor on ElementType {
  Color toneColor(BuildContext context) {
    final tokens = ChakotayColors.of(context);
    return switch (tone) {
      ElementTone.accent => tokens.song,
      ElementTone.liturgy => tokens.liturgy,
      ElementTone.neutral => Theme.of(context).colorScheme.onSurfaceVariant,
    };
  }
}
