import 'package:flutter/painting.dart';
import 'package:flutter/services.dart' show Brightness;

// GENERIERT aus einem kontrastgeprüften Palettenskript – alle Text/Fläche-
// Kombinationen erfüllen WCAG AA (≥ 4,5:1) in Hell und Dunkel:
// Akzent auf Fläche/Karte/Akzentcontainer, Text auf Akzent, Liturgie auf
// Karte/Liturgiecontainer, Sekundärtext, Warnung. Neutrale Töne sind leicht
// im Farbton des Schemas eingefärbt, damit jedes Schema ruhig und
// zusammenhängend wirkt.

/// Farbschemata – Namen und Reihenfolge wie in CHAPEL
/// (`shared/constants/colorSchemes.ts`).
enum AppColorScheme {
  chapelGreen(
    'chapel-green',
    'Chapel Grün',
    'Frisches Grün – der klassische CHAPEL-Look',
  ),
  liturgicalBlue(
    'liturgical-blue',
    'Liturgisch Blau',
    'Tiefes Blau, ruhig und sakral',
  ),
  goldenLiturgy(
    'golden-liturgy',
    'Goldenes Ambiente',
    'Warmes Gold, festlich und einladend',
  ),
  adventPurple(
    'advent-purple',
    'Advent Violett',
    'Gedämpftes Violett, würdevoll',
  ),
  forestCalm('forest-calm', 'Waldgrün', 'Gedämpftes Teal, natürlich und ruhig');

  const AppColorScheme(this.chapelId, this.label, this.description);

  /// Kennung wie in CHAPEL (`ColorSchemeId`).
  final String chapelId;
  final String label;
  final String description;

  SchemeColors colors(Brightness brightness) =>
      _palettes[this]![brightness == Brightness.dark ? 1 : 0];

  static AppColorScheme parse(String? value) {
    for (final s in values) {
      if (s.name == value || s.chapelId == value) return s;
    }
    return AppColorScheme.chapelGreen;
  }
}

class SchemeColors {
  const SchemeColors({
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.surface,
    required this.card,
    required this.onSurface,
    required this.secondary,
    required this.liturgy,
    required this.liturgyContainer,
    required this.high,
    required this.highest,
    required this.outline,
    required this.nav,
    required this.warning,
    required this.warningContainer,
  });

  final Color accent;
  final Color onAccent;
  final Color accentContainer;
  final Color onAccentContainer;
  final Color surface;
  final Color card;
  final Color onSurface;
  final Color secondary;
  final Color liturgy;
  final Color liturgyContainer;
  final Color high;
  final Color highest;
  final Color outline;
  final Color nav;
  final Color warning;
  final Color warningContainer;
}

const Map<AppColorScheme, List<SchemeColors>> _palettes = {
  AppColorScheme.chapelGreen: [
    SchemeColors(
      accent: Color(0xFF007F45),
      onAccent: Color(0xFFFFFFFF),
      accentContainer: Color(0xFFE3F7EE),
      onAccentContainer: Color(0xFF074026),
      surface: Color(0xFFF4F6F5),
      card: Color(0xFFFFFFFF),
      onSurface: Color(0xFF0F1512),
      secondary: Color(0xFF5C7067),
      liturgy: Color(0xFF51695E),
      liturgyContainer: Color(0xFFE5EBE8),
      high: Color(0xFFEBEFED),
      highest: Color(0xFFE0E6E3),
      outline: Color(0xFF869C92),
      nav: Color(0xFFF9FAFA),
      warning: Color(0xFF9A5B00),
      warningContainer: Color(0xFFFFF1DC),
    ),
    SchemeColors(
      accent: Color(0xFF2BD98A),
      onAccent: Color(0xFF061810),
      accentContainer: Color(0xFF153727),
      onAccentContainer: Color(0xFFC2F0DA),
      surface: Color(0xFF0E1311),
      card: Color(0xFF18201C),
      onSurface: Color(0xFFE8EDEB),
      secondary: Color(0xFF94A89F),
      liturgy: Color(0xFFA3B8AE),
      liturgyContainer: Color(0xFF232F29),
      high: Color(0xFF1F2924),
      highest: Color(0xFF27342E),
      outline: Color(0xFF5C7067),
      nav: Color(0xFF131916),
      warning: Color(0xFFF5B048),
      warningContainer: Color(0xFF3A2A10),
    ),
  ],
  AppColorScheme.liturgicalBlue: [
    SchemeColors(
      accent: Color(0xFF1D4ED8),
      onAccent: Color(0xFFFFFFFF),
      accentContainer: Color(0xFFE3EAF7),
      onAccentContainer: Color(0xFF071A40),
      surface: Color(0xFFF3F4F7),
      card: Color(0xFFFFFFFF),
      onSurface: Color(0xFF0F1115),
      secondary: Color(0xFF5C667A),
      liturgy: Color(0xFF536079),
      liturgyContainer: Color(0xFFE4E7ED),
      high: Color(0xFFEAECF0),
      highest: Color(0xFFDEE1E8),
      outline: Color(0xFF828CA1),
      nav: Color(0xFFF9FAFB),
      warning: Color(0xFF9A5B00),
      warningContainer: Color(0xFFFFF1DC),
    ),
    SchemeColors(
      accent: Color(0xFF7FA8FF),
      onAccent: Color(0xFF060C18),
      accentContainer: Color(0xFF152137),
      onAccentContainer: Color(0xFFC2D1F0),
      surface: Color(0xFF0D0F14),
      card: Color(0xFF171A22),
      onSurface: Color(0xFFE8EAED),
      secondary: Color(0xFF919AAC),
      liturgy: Color(0xFF9FA8BC),
      liturgyContainer: Color(0xFF212631),
      high: Color(0xFF1D212B),
      highest: Color(0xFF252B37),
      outline: Color(0xFF586174),
      nav: Color(0xFF11141A),
      warning: Color(0xFFF5B048),
      warningContainer: Color(0xFF3A2A10),
    ),
  ],
  AppColorScheme.goldenLiturgy: [
    SchemeColors(
      accent: Color(0xFF8A5300),
      onAccent: Color(0xFFFFFFFF),
      accentContainer: Color(0xFFF7F0E3),
      onAccentContainer: Color(0xFF402B07),
      surface: Color(0xFFF7F5F3),
      card: Color(0xFFFFFFFF),
      onSurface: Color(0xFF15130F),
      secondary: Color(0xFF766B59),
      liturgy: Color(0xFF70634D),
      liturgyContainer: Color(0xFFEDE9E4),
      high: Color(0xFFF0EEEA),
      highest: Color(0xFFE8E4DE),
      outline: Color(0xFFA19582),
      nav: Color(0xFFFBFAF9),
      warning: Color(0xFFB23C17),
      warningContainer: Color(0xFFFCE8E1),
    ),
    SchemeColors(
      accent: Color(0xFFF0B54A),
      onAccent: Color(0xFF181206),
      accentContainer: Color(0xFF372B15),
      onAccentContainer: Color(0xFFF0DFC2),
      surface: Color(0xFF14120D),
      card: Color(0xFF221E17),
      onSurface: Color(0xFFEDEBE8),
      secondary: Color(0xFFACA291),
      liturgy: Color(0xFFBCB19F),
      liturgyContainer: Color(0xFF312B21),
      high: Color(0xFF2B261D),
      highest: Color(0xFF373025),
      outline: Color(0xFF746A58),
      nav: Color(0xFF1A1711),
      warning: Color(0xFFFF9C7A),
      warningContainer: Color(0xFF3D1D14),
    ),
  ],
  AppColorScheme.adventPurple: [
    SchemeColors(
      accent: Color(0xFF6D28D9),
      onAccent: Color(0xFFFFFFFF),
      accentContainer: Color(0xFFEBE3F7),
      onAccentContainer: Color(0xFF1C0740),
      surface: Color(0xFFF4F3F6),
      card: Color(0xFFFFFFFF),
      onSurface: Color(0xFF110F15),
      secondary: Color(0xFF685E78),
      liturgy: Color(0xFF625676),
      liturgyContainer: Color(0xFFE7E4EC),
      high: Color(0xFFECEBF0),
      highest: Color(0xFFE2DFE7),
      outline: Color(0xFF8E849F),
      nav: Color(0xFFFAF9FB),
      warning: Color(0xFF9A5B00),
      warningContainer: Color(0xFFFFF1DC),
    ),
    SchemeColors(
      accent: Color(0xFFB9A0FF),
      onAccent: Color(0xFF0D0618),
      accentContainer: Color(0xFF221537),
      onAccentContainer: Color(0xFFD3C2F0),
      surface: Color(0xFF100D14),
      card: Color(0xFF1B1721),
      onSurface: Color(0xFFEAE8ED),
      secondary: Color(0xFF9B92AA),
      liturgy: Color(0xFFAAA1BA),
      liturgyContainer: Color(0xFF272230),
      high: Color(0xFF221E2A),
      highest: Color(0xFF2C2636),
      outline: Color(0xFF635A72),
      nav: Color(0xFF151219),
      warning: Color(0xFFF5B048),
      warningContainer: Color(0xFF3A2A10),
    ),
  ],
  AppColorScheme.forestCalm: [
    SchemeColors(
      accent: Color(0xFF0F766E),
      onAccent: Color(0xFFFFFFFF),
      accentContainer: Color(0xFFE3F7F5),
      onAccentContainer: Color(0xFF07403B),
      surface: Color(0xFFF3F6F6),
      card: Color(0xFFFFFFFF),
      onSurface: Color(0xFF0F1514),
      secondary: Color(0xFF59716E),
      liturgy: Color(0xFF4D6A67),
      liturgyContainer: Color(0xFFE4ECEB),
      high: Color(0xFFEBF0EF),
      highest: Color(0xFFDFE7E6),
      outline: Color(0xFF849F9C),
      nav: Color(0xFFF9FBFA),
      warning: Color(0xFF9A5B00),
      warningContainer: Color(0xFFFFF1DC),
    ),
    SchemeColors(
      accent: Color(0xFF45D3C1),
      onAccent: Color(0xFF061817),
      accentContainer: Color(0xFF153734),
      onAccentContainer: Color(0xFFC2F0EB),
      surface: Color(0xFF0D1413),
      card: Color(0xFF172120),
      onSurface: Color(0xFFE8EDED),
      secondary: Color(0xFF92AAA7),
      liturgy: Color(0xFFA1BAB8),
      liturgyContainer: Color(0xFF22302E),
      high: Color(0xFF1E2A28),
      highest: Color(0xFF263634),
      outline: Color(0xFF5A7270),
      nav: Color(0xFF121919),
      warning: Color(0xFFF5B048),
      warningContainer: Color(0xFF3A2A10),
    ),
  ],
};
