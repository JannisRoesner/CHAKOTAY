import 'dart:math';

import 'package:chakotay/settings/key_value_store.dart';
import 'package:chakotay/settings/settings_store.dart';
import 'package:chakotay/ui/palettes.dart';
import 'package:chakotay/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (max(la, lb) + 0.05) / (min(la, lb) + 0.05);
}

void main() {
  for (final scheme in AppColorScheme.values) {
    for (final brightness in Brightness.values) {
      test('${scheme.label} (${brightness.name}) erfüllt WCAG AA', () {
        final c = scheme.colors(brightness);
        final pairs = <String, (Color, Color)>{
          'Akzent/Fläche': (c.accent, c.surface),
          'Akzent/Karte': (c.accent, c.card),
          'Akzent/Akzentcontainer': (c.accent, c.accentContainer),
          'Text auf Akzent': (c.onAccent, c.accent),
          'Text auf Akzentcontainer': (c.onAccentContainer, c.accentContainer),
          'Liturgie/Karte': (c.liturgy, c.card),
          'Liturgie/Liturgiecontainer': (c.liturgy, c.liturgyContainer),
          'Sekundärtext/Fläche': (c.secondary, c.surface),
          'Sekundärtext/Karte': (c.secondary, c.card),
          'Text/Fläche': (c.onSurface, c.surface),
          'Text/Karte': (c.onSurface, c.card),
          'Warnung/Karte': (c.warning, c.card),
          'Warnung/Warncontainer': (c.warning, c.warningContainer),
        };
        pairs.forEach((name, pair) {
          expect(
            _contrast(pair.$1, pair.$2),
            greaterThanOrEqualTo(4.5),
            reason: name,
          );
        });
      });
    }
  }

  test('Theme übernimmt das gewählte Schema', () {
    final theme = buildTheme(Brightness.dark, AppColorScheme.adventPurple);
    final c = AppColorScheme.adventPurple.colors(Brightness.dark);
    expect(theme.colorScheme.primary, c.accent);
    expect(theme.scaffoldBackgroundColor, c.surface);
    expect(theme.extension<ChakotayColors>()!.liturgy, c.liturgy);
  });

  test('Schema wird gespeichert und akzeptiert CHAPEL-Kennungen', () async {
    final store = MemoryKeyValueStore();
    final settings = SettingsStore(store);
    await settings.ready;
    expect(settings.colorScheme, AppColorScheme.chapelGreen);
    await settings.setColorScheme(AppColorScheme.liturgicalBlue);
    final reloaded = SettingsStore(store);
    await reloaded.ready;
    expect(reloaded.colorScheme, AppColorScheme.liturgicalBlue);
    expect(
      AppColorScheme.parse('golden-liturgy'),
      AppColorScheme.goldenLiturgy,
    );
    expect(AppColorScheme.parse('unbekannt'), AppColorScheme.chapelGreen);
  });
}
