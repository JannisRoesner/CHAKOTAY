import 'dart:convert';
import 'dart:io';

import 'package:chakotay/core/cancel_token.dart';
import 'package:chakotay/core/failures.dart';
import 'package:chakotay/packages/package_installer.dart';
import 'package:chakotay/packages/package_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chapel_fixtures.dart';

const origin = 'https://chapel.example.org';

void main() {
  late Directory dir;
  late PackageRepository repo;
  late PackageInstaller installer;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chakotay_install_');
    repo = PackageRepository(Directory('${dir.path}/library'));
    await repo.init();
    installer = PackageInstaller(repo);
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  final a1 = fakeAudio(1);
  final a2 = fakeAudio(2);
  final a3 = fakeAudio(3);

  Map<String, Object?> manifest({
    int id = 12,
    String version = 'v1',
    List<FixtureAudio>? audio,
  }) {
    final list = audio ?? [a1, a2];
    return manifestJson(
      serviceId: id,
      version: version,
      steps: [
        for (var i = 0; i < list.length; i++)
          stepJson(position: i * 2, audio: list[i]),
        stepJson(position: 1), // leerer Schritt
      ],
    );
  }

  Future<File> zipFile(List<int> bytes) =>
      writeTemp(dir, 'dl-${DateTime.now().microsecondsSinceEpoch}.zip', bytes);

  Future<List<String>> library() async {
    final names = await repo.audioDir
        .list()
        .map((e) => e.uri.pathSegments.last)
        .toList();
    names.sort();
    return names;
  }

  test('installiert, prüft und legt Dateien dedupliziert ab', () async {
    final pkg = await installer.install(
      await zipFile(buildPackageZip(manifest(), [a1, a2])),
      serverOrigin: origin,
      expectedServiceId: 12,
      expectedVersion: 'v1',
    );
    expect(pkg.version, 'v1');
    expect(pkg.manifest.steps, hasLength(3));
    expect(
      await repo.audioFile(pkg.manifest.steps[0].audio!).readAsBytes(),
      a1.bytes,
    );
    expect(await repo.missingAudio(pkg), isEmpty);
    final all = await repo.loadAll();
    expect(all.single.key, packageKey(origin, 12));
    expect(await repo.tempDir.list().toList(), isEmpty);
  });

  test(
    'gemeinsame Dateien bleiben beim Löschen eines Pakets erhalten',
    () async {
      await installer.install(
        await zipFile(buildPackageZip(manifest(id: 1), [a1, a2])),
        serverOrigin: origin,
      );
      await installer.install(
        await zipFile(
          buildPackageZip(manifest(id: 2, audio: [a2, a3]), [a2, a3]),
        ),
        serverOrigin: origin,
      );
      expect(
        await library(),
        [a1, a2, a3].map((a) => '${a.sha}.mp3').toList()..sort(),
      );

      await repo.delete(packageKey(origin, 1));
      final remaining = (await library()).join(',');
      expect(remaining, contains(a2.sha), reason: 'noch von Paket 2 benötigt');
      expect(remaining, contains(a3.sha));
      expect(remaining, isNot(contains(a1.sha)));

      await repo.delete(packageKey(origin, 2));
      expect(await library(), isEmpty);
    },
  );

  test('Update ersetzt atomar und räumt alte Dateien auf', () async {
    await installer.install(
      await zipFile(buildPackageZip(manifest(), [a1, a2])),
      serverOrigin: origin,
    );
    final updated = await installer.install(
      await zipFile(
        buildPackageZip(manifest(version: 'v2', audio: [a1, a3]), [a1, a3]),
      ),
      serverOrigin: origin,
    );
    expect(updated.version, 'v2');
    final all = await repo.loadAll();
    expect(all, hasLength(1));
    expect(all.single.version, 'v2');
    expect(
      await library(),
      [a1, a3].map((a) => '${a.sha}.mp3').toList()..sort(),
    );
  });

  test('falsche Prüfsumme: Fehler, bestehendes Paket bleibt intakt', () async {
    await installer.install(
      await zipFile(buildPackageZip(manifest(), [a1, a2])),
      serverOrigin: origin,
    );
    // Manipuliert: Datei a3 trägt den Namen/Hash von a3, enthält aber andere Bytes.
    final tampered = FixtureAudio(a3.bytes);
    final m = manifest(version: 'v2', audio: [a1, tampered]);
    final bytes = buildZip([
      ZipSpec('manifest.json', utf8.encode(jsonEncode(m))),
      ZipSpec(a1.file, a1.bytes),
      ZipSpec(tampered.file, List.of(a3.bytes)..[0] ^= 0xFF),
    ]);
    await expectLater(
      installer.install(await zipFile(bytes), serverOrigin: origin),
      throwsA(
        isA<AppFailure>().having(
          (f) => f.kind,
          'kind',
          FailureKind.checksumMismatch,
        ),
      ),
    );
    final all = await repo.loadAll();
    expect(all.single.version, 'v1');
    expect(await repo.missingAudio(all.single), isEmpty);
    expect(
      await library(),
      [a1, a2].map((a) => '${a.sha}.mp3').toList()..sort(),
    );
    expect(await repo.tempDir.list().toList(), isEmpty);
  });

  test('beschädigtes ZIP wird abgelehnt', () async {
    final bytes = buildPackageZip(manifest(), [a1, a2]);
    await expectLater(
      installer.install(
        await zipFile(bytes.sublist(0, bytes.length ~/ 2)),
        serverOrigin: origin,
      ),
      throwsA(
        isA<AppFailure>().having(
          (f) => f.kind,
          'kind',
          FailureKind.corruptPackage,
        ),
      ),
    );
    expect(await repo.loadAll(), isEmpty);
  });

  test('fehlende Audiodatei im Container wird abgelehnt', () async {
    await expectLater(
      installer.install(
        await zipFile(buildPackageZip(manifest(), [a1])),
        serverOrigin: origin,
      ),
      throwsA(
        isA<AppFailure>().having(
          (f) => f.kind,
          'kind',
          FailureKind.corruptPackage,
        ),
      ),
    );
  });

  test('unerwartete Zusatzdateien werden abgelehnt', () async {
    await expectLater(
      installer.install(
        await zipFile(
          buildPackageZip(
            manifest(),
            [a1, a2],
            extra: [ZipSpec('payload.sh', utf8.encode('rm -rf /'))],
          ),
        ),
        serverOrigin: origin,
      ),
      throwsA(
        isA<AppFailure>().having(
          (f) => f.kind,
          'kind',
          FailureKind.corruptPackage,
        ),
      ),
    );
  });

  test('unbekannte Paketversion → App-Update empfehlen', () async {
    final m = manifestJson(steps: const [], formatVersion: 99);
    await expectLater(
      installer.install(
        await zipFile(buildPackageZip(m, const [])),
        serverOrigin: origin,
      ),
      throwsA(
        isA<AppFailure>().having(
          (f) => f.kind,
          'kind',
          FailureKind.unsupportedPackageVersion,
        ),
      ),
    );
  });

  test('falscher Gottesdienst / falsche Version wird erkannt', () async {
    final file = await zipFile(buildPackageZip(manifest(id: 5), [a1, a2]));
    await expectLater(
      installer.install(file, serverOrigin: origin, expectedServiceId: 6),
      throwsA(isA<AppFailure>()),
    );
    await expectLater(
      installer.install(file, serverOrigin: origin, expectedVersion: 'anders'),
      throwsA(isA<AppFailure>()),
    );
  });

  test('Abbruch hinterlässt keinen Datensatz und keine Dateien', () async {
    final token = CancelToken()..cancel();
    await expectLater(
      installer.install(
        await zipFile(buildPackageZip(manifest(), [a1, a2])),
        serverOrigin: origin,
        cancelToken: token,
      ),
      throwsA(
        isA<AppFailure>().having((f) => f.kind, 'kind', FailureKind.cancelled),
      ),
    );
    expect(await repo.loadAll(), isEmpty);
    expect(await library(), isEmpty);
  });

  test('recover() entfernt Reste eines beendeten Downloads', () async {
    await repo.init();
    await File('${repo.tempDir.path}/halb.zip').writeAsBytes([1, 2, 3]);
    await File('${repo.audioDir.path}/verwaist.mp3').writeAsBytes([1]);
    await File('${repo.packagesDir.path}/x.json.tmp').writeAsString('{');
    await repo.recover();
    expect(await repo.tempDir.list().toList(), isEmpty);
    expect(await library(), isEmpty);
    expect(await repo.packagesDir.list().toList(), isEmpty);
  });

  test(
    'unlesbare Datensätze machen die übrige Bibliothek nicht unbrauchbar',
    () async {
      await installer.install(
        await zipFile(buildPackageZip(manifest(), [a1, a2])),
        serverOrigin: origin,
      );
      await File('${repo.packagesDir.path}/kaputt.json').writeAsString('{nope');
      final all = await repo.loadAll();
      expect(all, hasLength(1));
    },
  );
}
