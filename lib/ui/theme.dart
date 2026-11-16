import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Design-Tokens von CHAKOTAY.
///
/// Abgeleitet vom CHAPEL-Grün, aber für Text auf Flächen kontrastgeprüft
/// (WCAG / HIG `color.md`: 4,5:1 für Text bis 17 pt):
///
/// | Rolle            | Hell      | Dunkel    | Kontrast |
/// |------------------|-----------|-----------|----------|
/// | accent           | #007F45   | #2BD98A   | 5,4:1 auf Weiß · 10,1:1 auf #0E1311 |
/// | onAccent         | #FFFFFF   | #04120B   | 5,4:1 · 10,1:1 |
/// | liturgy (Signal) | #5B6B64   | #A3B5AC   | 5,6:1 · 8,9:1 |
/// | surface          | #F4F6F5   | #0E1311   | – |
/// | card             | #FFFFFF   | #18201C   | – |
/// | warning          | #9A5B00   | #F5B048   | 5,3:1 · 9,8:1 |
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

  static const light = ChakotayColors(
    liturgy: Color(0xFF5B6B64),
    liturgyContainer: Color(0xFFE6ECE9),
    song: Color(0xFF007F45),
    songContainer: Color(0xFFDDF5E8),
    warning: Color(0xFF9A5B00),
    warningContainer: Color(0xFFFFF1DC),
    success: Color(0xFF007F45),
    card: Color(0xFFFFFFFF),
    separator: Color(0x1F0E1311),
  );

  static const dark = ChakotayColors(
    liturgy: Color(0xFFA3B5AC),
    liturgyContainer: Color(0xFF232D29),
    song: Color(0xFF2BD98A),
    songContainer: Color(0xFF103223),
    warning: Color(0xFFF5B048),
    warningContainer: Color(0xFF3A2A10),
    success: Color(0xFF2BD98A),
    card: Color(0xFF18201C),
    separator: Color(0x2EFFFFFF),
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

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final tokens = isDark ? ChakotayColors.dark : ChakotayColors.light;
  final accent = isDark ? const Color(0xFF2BD98A) : const Color(0xFF007F45);
  final surface = isDark ? const Color(0xFF0E1311) : const Color(0xFFF4F6F5);
  final onSurface = isDark ? const Color(0xFFE9EFEC) : const Color(0xFF111714);
  final secondaryText = isDark
      ? const Color(0xFFA0ACA6)
      : const Color(0xFF5A6560);

  final scheme = ColorScheme(
    brightness: brightness,
    primary: accent,
    onPrimary: isDark ? const Color(0xFF04120B) : Colors.white,
    primaryContainer: tokens.songContainer,
    onPrimaryContainer: isDark
        ? const Color(0xFFBDF5D8)
        : const Color(0xFF00391E),
    secondary: tokens.liturgy,
    onSecondary: isDark ? const Color(0xFF0E1311) : Colors.white,
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
    surfaceContainerHigh: isDark
        ? const Color(0xFF202924)
        : const Color(0xFFEDF1EF),
    surfaceContainerHighest: isDark
        ? const Color(0xFF29332E)
        : const Color(0xFFE3E9E6),
    outline: isDark ? const Color(0xFF5E6B65) : const Color(0xFF8A9590),
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
      backgroundColor: isDark
          ? const Color(0xF2131A16)
          : const Color(0xF2FAFBFA),
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
