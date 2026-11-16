import 'dart:io';

import 'package:chakotay/core/failures.dart';
import 'package:chakotay/packages/manifest.dart';
import 'package:chakotay/packages/package_repository.dart';
import 'package:chakotay/playback/player_controller.dart';
import 'package:chakotay/playback/progress_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chapel_fixtures.dart';
import '../support/fake_audio_engine.dart';

void main() {
  late Directory dir;
  late FakeAudioEngine engine;
  late ProgressStore progress;

  final a1 = fakeAudio(1);
  final a2 = fakeAudio(2);
  final a3 = fakeAudio(3);

  /// Ablauf: [0] Kyrie (Audio) · [1] leer · [2] Lied 92 % · [3] leer · [4] Segen
  LocalPackage package({String version = 'v1'}) => LocalPackage(
    serverOrigin: 'https://chapel.example.org',
    installedAt: DateTime.utc(2026),
    manifest: PackageManifest.fromJson(
      manifestJson(
        version: version,
        steps: [
          stepJson(position: 0, kind: 'liturgy', label: 'Kyrie', audio: a1),
          stepJson(position: 1, label: 'Eingangslied'),
          stepJson(
            position: 2,
            label: 'Lied',
            audio: a2,
            playbackRate: 0.92,
            durationMs: 65217,
          ),
          stepJson(position: 3, label: 'Predigtlied'),
          stepJson(position: 4, kind: 'liturgy', label: 'Segen', audio: a3),
        ],
      ),
    ),
  );

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chakotay_player_');
    for (final a in [a1, a2, a3]) {
      await File('${dir.path}/${a.sha}.mp3').writeAsBytes(a.bytes);
    }
    engine = FakeAudioEngine();
    progress = ProgressStore(File('${dir.path}/progress.json'));
  });
  tearDown(() async {
    await progress.idle;
    await dir.delete(recursive: true);
  });

  Future<PlayerController> controller([LocalPackage? pkg]) async {
    final c = PlayerController(
      package: pkg ?? package(),
      engine: engine,
      resolveAudio: (a) => File('${dir.path}/${a.libraryFileName}'),
      progressStore: progress,
    );
    await c.init();
    return c;
  }

  test(
    'startet ausgewählt beim ersten abspielbaren Schritt, ohne abzuspielen',
    () async {
      final c = await controller();
      expect(c.currentIndex, 0);
      expect(c.status, PlaybackStatus.idle);
      expect(engine.calls, isEmpty);
    },
  );

  test('Titelende stoppt automatisch – nächster Titel startet NICHT', () async {
    final c = await controller();
    await c.play();
    expect(c.status, PlaybackStatus.playing);
    expect(engine.playCount, 1);

    engine.complete();
    await pumpEventQueue();

    expect(c.status, PlaybackStatus.idle);
    expect(c.justFinished, isTrue);
    expect(c.currentIndex, 2, reason: 'leerer Schritt 1 wird übersprungen');
    expect(c.playedIndices, {0});
    expect(engine.playCount, 1, reason: 'kein Autoplay');
    expect(engine.playing, isFalse);
    expect(engine.loads, hasLength(1));
  });

  test(
    '„Nächster“ ist die bewusste Aktion, die den nächsten Titel startet',
    () async {
      final c = await controller();
      await c.play();
      engine.complete();
      await pumpEventQueue();

      await c.play(); // Benutzer tippt „Abspielen“ auf vorausgewähltem Schritt
      expect(engine.playCount, 2);
      expect(engine.loadedPath, endsWith('${a2.sha}.mp3'));

      await c.next(); // „Nächster“: überspringt leeren Schritt 3, startet Segen
      expect(c.currentIndex, 4);
      expect(c.status, PlaybackStatus.playing);
      expect(engine.loadedPath, endsWith('${a3.sha}.mp3'));
      expect(engine.playCount, 3);
    },
  );

  test('Tempo aus dem Manifest wird an die Engine übergeben', () async {
    final c = await controller();
    await c.select(2);
    await c.play();
    expect(engine.rate, 0.92);
    // Anzeige in Echtzeit: Medienzeit / Tempo.
    engine.emitPosition(const Duration(seconds: 46));
    expect(c.position.value.inMilliseconds, closeTo(50000, 1));
    expect(c.currentDuration, const Duration(milliseconds: 65217));
  });

  test('letzter Titel → finishedLast, kein weiterer Start', () async {
    final c = await controller();
    await c.select(4);
    await c.play();
    engine.complete();
    await pumpEventQueue();
    expect(c.status, PlaybackStatus.finishedLast);
    expect(c.currentIndex, 4);
    expect(c.hasNext, isFalse);
    await c.next();
    expect(engine.playCount, 1);
  });

  test(
    'leere Schritte bleiben sichtbar, sind auswählbar, aber nicht abspielbar',
    () async {
      final c = await controller();
      expect(c.steps, hasLength(5));
      expect(c.steps[1].isPlayable, isFalse);
      await c.select(1);
      expect(c.currentIndex, 1);
      expect(c.canPlay, isFalse);
      await c.play();
      expect(engine.calls, isEmpty);
      expect(c.status, PlaybackStatus.idle);
      // „Nächster“ von einem leeren Schritt aus startet den nächsten Titel.
      await c.next();
      expect(c.currentIndex, 2);
      expect(c.status, PlaybackStatus.playing);
    },
  );

  test('Pause und Fortsetzen ohne Neuladen', () async {
    final c = await controller();
    await c.togglePlay();
    await c.togglePlay();
    expect(c.status, PlaybackStatus.paused);
    await c.togglePlay();
    expect(c.status, PlaybackStatus.playing);
    expect(engine.loads, hasLength(1));
    expect(engine.playCount, 2);
  });

  test('Stopp setzt zurück und bleibt beim Schritt', () async {
    final c = await controller();
    await c.play();
    engine.emitPosition(const Duration(seconds: 10));
    await c.stop();
    expect(c.status, PlaybackStatus.idle);
    expect(c.currentIndex, 0);
    expect(c.position.value, Duration.zero);
    expect(engine.calls.last, 'stop');
  });

  test(
    'Auswahl eines Schritts stoppt laufende Wiedergabe ohne Neustart',
    () async {
      final c = await controller();
      await c.play();
      await c.select(4);
      expect(c.status, PlaybackStatus.idle);
      expect(c.currentIndex, 4);
      expect(engine.playing, isFalse);
      expect(engine.playCount, 1);
    },
  );

  test('„Vorheriger“ wählt nur aus und überspringt leere Schritte', () async {
    final c = await controller();
    await c.select(4);
    await c.previous();
    expect(c.currentIndex, 2);
    expect(c.status, PlaybackStatus.idle);
    await c.previous();
    expect(c.currentIndex, 0);
    expect(c.hasPrevious, isFalse);
    expect(engine.playCount, 0);
  });

  test('Unterbrechung (Anruf) pausiert und setzt nie selbst fort', () async {
    final c = await controller();
    await c.play();
    engine.interrupt('Unterbrechung durch das System');
    await pumpEventQueue();
    expect(c.status, PlaybackStatus.paused);
    expect(c.notice, isNotNull);
    expect(engine.playCount, 1);
    // Ein verspätetes Titelende-Ereignis darf nichts auslösen.
    engine.complete();
    await pumpEventQueue();
    expect(c.status, PlaybackStatus.paused);
    expect(c.currentIndex, 0);
  });

  test('Titelende-Ereignis nach Stopp wird ignoriert', () async {
    final c = await controller();
    await c.play();
    await c.stop();
    engine.complete();
    await pumpEventQueue();
    expect(c.currentIndex, 0);
    expect(c.playedIndices, isEmpty);
  });

  test('fehlende Audiodatei → verständlicher Fehler, kein Absturz', () async {
    await File('${dir.path}/${a1.sha}.mp3').delete();
    final c = await controller();
    await c.play();
    expect(c.failure?.kind, FailureKind.audioMissing);
    expect(c.status, PlaybackStatus.idle);
    expect(engine.playCount, 0);
  });

  test('Wiedergabefehler der Engine', () async {
    engine.loadError = Exception('Decoder');
    final c = await controller();
    await c.play();
    expect(c.failure?.kind, FailureKind.playbackFailed);
    expect(c.status, PlaybackStatus.idle);

    engine.loadError = null;
    await c.play();
    expect(c.failure, isNull);
    engine.fail('Ausgabe');
    await pumpEventQueue();
    expect(c.failure?.kind, FailureKind.playbackFailed);
    expect(c.status, PlaybackStatus.idle);
  });

  test('Fortschritt wird gespeichert und wiederhergestellt', () async {
    final c = await controller();
    await c.play();
    engine.complete();
    await pumpEventQueue();
    await c.close();

    final engine2 = FakeAudioEngine();
    final store2 = ProgressStore(File('${dir.path}/progress.json'));
    final c2 = PlayerController(
      package: package(),
      engine: engine2,
      resolveAudio: (a) => File('${dir.path}/${a.libraryFileName}'),
      progressStore: store2,
    );
    await c2.init();
    expect(c2.currentIndex, 2);
    expect(c2.playedIndices, {0});
    expect(engine2.playCount, 0, reason: 'Wiederherstellen startet nichts');
    await store2.idle;
  });

  test('Paketupdate (neue Version) setzt den Fortschritt zurück', () async {
    final c = await controller();
    await c.select(4);
    await c.close();
    await pumpEventQueue();

    final store2 = ProgressStore(File('${dir.path}/progress.json'));
    final c2 = PlayerController(
      package: package(version: 'v2'),
      engine: FakeAudioEngine(),
      resolveAudio: (a) => File('${dir.path}/${a.libraryFileName}'),
      progressStore: store2,
    );
    await c2.init();
    await store2.idle;
    expect(c2.currentIndex, 0);
    expect(c2.playedIndices, isEmpty);
  });
}
