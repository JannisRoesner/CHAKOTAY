import 'dart:convert';

import 'package:chakotay/packages/manifest.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chapel_fixtures.dart';

void main() {
  final a1 = fakeAudio(1);
  final a2 = fakeAudio(2);

  Map<String, Object?> sample() => manifestJson(
    steps: [
      stepJson(position: 0, kind: 'liturgy', label: 'Kyrie', audio: a1),
      stepJson(position: 1, label: 'Eingangslied'),
      stepJson(position: 2, label: 'Lied', audio: a2, playbackRate: 0.92),
      // Tempo-Variante: gleiche Datei wie Schritt 0.
      stepJson(position: 3, label: 'Gloria', audio: a1, playbackRate: 1.1),
    ],
  );

  test('parst ein CHAPEL-Manifest inkl. leerer Schritte und Tempo', () {
    final m = PackageManifest.parse(jsonEncode(sample()));
    expect(m.formatVersion, 1);
    expect(m.version, 'ea8c8f53b9835a2dbbc0e3568d7aa6f6');
    expect(m.service.id, 12);
    expect(m.service.name, '1. Advent');
    expect(m.steps, hasLength(4));
    expect(m.steps[0].kind, 'liturgy');
    expect(m.steps[1].audio, isNull);
    expect(m.steps[1].isPlayable, isFalse);
    expect(m.steps[1].durationMs, isNull);
    expect(m.steps[2].playbackRate, 0.92);
    expect(m.steps[0].audio!.sha256, a1.sha);
    expect(m.distinctAudio, hasLength(2), reason: 'dedupliziert');
    expect(m.playableStepCount, 3);
    expect(m.totalAudioBytes, a1.bytes.length + a2.bytes.length);
    expect(m.steps[0].audio!.libraryFileName, '${a1.sha}.mp3');
  });

  test('sortiert Schritte nach position', () {
    final json = manifestJson(
      steps: [
        stepJson(position: 2, audio: a1),
        stepJson(position: 0, audio: a2),
        stepJson(position: 1),
      ],
    );
    final m = PackageManifest.fromJson(json);
    expect(m.steps.map((s) => s.position), [0, 1, 2]);
  });

  test('lehnt unbekannte formatVersion ab', () {
    final json = manifestJson(steps: const [], formatVersion: 2);
    expect(
      () => PackageManifest.fromJson(json),
      throwsA(isA<UnsupportedPackageVersionException>()),
    );
  });

  test('lehnt kein JSON / fehlende Felder ab', () {
    expect(
      () => PackageManifest.parse('kein json'),
      throwsA(isA<ManifestFormatException>()),
    );
    final json = sample()..remove('version');
    expect(
      () => PackageManifest.fromJson(json),
      throwsA(isA<ManifestFormatException>()),
    );
  });

  test('lehnt unsichere Audiopfade ab', () {
    for (final file in [
      '../evil.mp3',
      'audio/../../evil.mp3',
      '/etc/passwd',
      'audio/sub/x.mp3',
      'audio/x.exe',
      'manifest.json',
    ]) {
      final json = sample();
      final steps = (json['steps'] as List).cast<Map<String, Object?>>();
      (steps[0]['audio'] as Map)['file'] = file;
      expect(
        () => PackageManifest.fromJson(json),
        throwsA(isA<ManifestFormatException>()),
        reason: file,
      );
    }
  });

  test('lehnt ungültige Prüfsummen ab', () {
    final json = sample();
    final steps = (json['steps'] as List).cast<Map<String, Object?>>();
    (steps[0]['audio'] as Map)['sha256'] = 'xyz';
    expect(
      () => PackageManifest.fromJson(json),
      throwsA(isA<ManifestFormatException>()),
    );
  });

  test('lehnt widersprüchliche Angaben für dieselbe Datei ab', () {
    final json = sample();
    final steps = (json['steps'] as List).cast<Map<String, Object?>>();
    (steps[3]['audio'] as Map)['sizeBytes'] = 1;
    expect(
      () => PackageManifest.fromJson(json),
      throwsA(isA<ManifestFormatException>()),
    );
  });

  test('klemmt Tempo auf CHAPEL-Grenzen und ersetzt ungültige Werte', () {
    final json = manifestJson(
      steps: [
        stepJson(position: 0, audio: a1, playbackRate: 3),
        {...stepJson(position: 1, audio: a2), 'playbackRate': 'schnell'},
      ],
    );
    final m = PackageManifest.fromJson(json);
    expect(m.steps[0].playbackRate, 1.5);
    expect(m.steps[1].playbackRate, 1);
  });

  test('übersteht Serialisierung (toJson → fromJson)', () {
    final m = PackageManifest.fromJson(sample());
    final again = PackageManifest.fromJson(jsonDecode(jsonEncode(m.toJson())));
    expect(again.version, m.version);
    expect(again.steps.length, m.steps.length);
    expect(again.steps[2].playbackRate, 0.92);
    expect(again.steps[1].audio, isNull);
  });

  test('akzeptiert frei definierte Elementtypen (CHAPEL element_types)', () {
    final m = PackageManifest.fromJson(
      manifestJson(
        steps: [
          stepJson(
            position: 0,
            kind: 'voluntary',
            label: 'Eingangsmusik',
            audio: a1,
          ),
          stepJson(position: 1, kind: 'communion', label: 'Abendmahl'),
          stepJson(
            position: 2,
            kind: 't-1a2b3c4d',
            label: 'Kinderchor',
            audio: a2,
          ),
        ],
      ),
    );
    expect(m.steps.map((s) => s.kind), [
      'voluntary',
      'communion',
      't-1a2b3c4d',
    ]);
    expect(m.steps[1].isPlayable, isFalse);
  });

  test('lehnt leere oder fehlende Schrittart ab', () {
    for (final kind in ['', null, 42]) {
      final json = manifestJson(steps: [stepJson(position: 0, audio: a1)]);
      ((json['steps'] as List).first as Map)['kind'] = kind;
      expect(
        () => PackageManifest.fromJson(json),
        throwsA(isA<ManifestFormatException>()),
        reason: '$kind',
      );
    }
  });
}
