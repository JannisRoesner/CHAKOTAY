import 'package:chakotay/packages/element_type.dart';
import 'package:chakotay/packages/package_repository.dart';
import 'package:chakotay/packages/manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chapel_fixtures.dart';

void main() {
  test('Elementtypen werden tolerant gelesen und auf Töne abgebildet', () {
    final t = ElementType.tryParse({
      'key': 't-1a2b3c4d',
      'label': 'Kinderchor',
      'color': 'info',
      'fixed': false,
      'icon': 'i-lucide-baby',
    })!;
    expect(t.label, 'Kinderchor');
    expect(t.tone, ElementTone.neutral);
    expect(builtinElementTypes['songSlot']!.tone, ElementTone.accent);
    expect(builtinElementTypes['liturgy']!.tone, ElementTone.liturgy);
    expect(ElementType.tryParse({'key': '', 'label': 'x'}), isNull);
    expect(ElementType.tryParse('kaputt'), isNull);
  });

  test('Auflösung wie CHAPEL: gespeichert → Vorgabe → wie Lied', () {
    const known = {
      'communion': ElementType(
        key: 'communion',
        label: 'Abendmahl',
        color: 'warning',
      ),
    };
    expect(resolveElementType(known, 'communion').label, 'Abendmahl');
    expect(resolveElementType(known, 'voluntary').label, 'Ein-/Ausgang');
    expect(resolveElementType(known, 't-unbekannt').label, 'Lied');
  });

  test('Paketdatensatz speichert Elementtypen (offline verfügbar)', () {
    final pkg = LocalPackage(
      serverOrigin: 'https://chapel.example.org',
      installedAt: DateTime.utc(2026),
      manifest: PackageManifest.fromJson(
        manifestJson(steps: [stepJson(position: 0, kind: 't-1a2b3c4d')]),
      ),
      elementTypes: const {
        't-1a2b3c4d': ElementType(
          key: 't-1a2b3c4d',
          label: 'Kinderchor',
          color: 'info',
        ),
      },
    );
    final again = LocalPackage.fromJson(pkg.toJson());
    expect(again.elementTypeOf('t-1a2b3c4d').label, 'Kinderchor');
    // Ältere Datensätze ohne Typen bleiben lesbar.
    final legacy = pkg.toJson()..remove('elementTypes');
    expect(
      LocalPackage.fromJson(legacy).elementTypeOf('liturgy').label,
      'Liturgie',
    );
  });
}
