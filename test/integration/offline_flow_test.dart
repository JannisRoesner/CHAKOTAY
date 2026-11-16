// Integrationstest des Kernablaufs (Auftrag Abschnitt 13):
//
// 1. Anmeldung an einem simulierten CHAPEL-Server (echter HTTP-Server)
// 2. Download eines vollständigen Gottesdienstpakets
// 3. Validierung und lokale Speicherung
// 4. Netzwerkzugriff wird deaktiviert
// 5. Gottesdienst wird geöffnet (aus einer frisch geladenen Bibliothek)
// 6. Ein Titel wird abgespielt
// 7. Nach dem Titelende stoppt der Player
// 8. Der nächste Titel startet erst nach ausdrücklicher Benutzeraktion
import 'dart:async';
import 'dart:io';

import 'package:chakotay/auth/account_controller.dart';
import 'package:chakotay/auth/session_store.dart';
import 'package:chakotay/library/library_controller.dart';
import 'package:chakotay/packages/package_installer.dart';
import 'package:chakotay/packages/package_repository.dart';
import 'package:chakotay/playback/player_controller.dart';
import 'package:chakotay/playback/progress_store.dart';
import 'package:chakotay/settings/key_value_store.dart';
import 'package:chakotay/settings/settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chapel_fixtures.dart';
import '../support/fake_audio_engine.dart';
import '../support/fake_chapel_server.dart';

/// Blockiert jeden HTTP-Verbindungsversuch und zählt ihn.
class _NoNetwork extends HttpOverrides {
  int attempts = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    attempts++;
    throw const SocketException('Netzwerk deaktiviert (Test)');
  }
}

Future<void> _waitForDownloads(LibraryController library) async {
  if (!library.hasActiveDownloads) return;
  final done = Completer<void>();
  void listener() {
    if (!library.hasActiveDownloads && !done.isCompleted) done.complete();
  }

  library.addListener(listener);
  await done.future.timeout(const Duration(seconds: 20));
  library.removeListener(listener);
}

void main() {
  late Directory dir;
  late FakeChapelServer server;

  final kyrie = fakeAudio(1, size: 30000);
  final hymn = fakeAudio(2, size: 40000);

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chakotay_flow_');
    server = await FakeChapelServer.start();
    server.users['organist@gemeinde.de'] = FakeUser(
      'organist@gemeinde.de',
      'geheim123',
    );
    server.addPackage(
      FakePackage(
        manifestJson(
          serviceId: 12,
          name: '1. Advent',
          steps: [
            stepJson(
              position: 0,
              kind: 'liturgy',
              label: 'Kyrie',
              audio: kyrie,
            ),
            stepJson(position: 1, label: 'Eingangslied'), // leerer Slot
            stepJson(
              position: 2,
              label: 'Wochenlied',
              audio: hymn,
              playbackRate: 0.92,
            ),
            // Tempo-Variante derselben Aufnahme → gleiche Datei.
            stepJson(
              position: 3,
              kind: 'liturgy',
              label: 'Gloria',
              audio: kyrie,
              playbackRate: 1.1,
            ),
          ],
        ),
        [kyrie, hymn],
      ),
    );
  });

  tearDown(() async {
    await server.close();
    await dir.delete(recursive: true);
  });

  test(
    'Anmelden → Laden → offline öffnen → abspielen → Stopp → bewusst weiter',
    () async {
      // ---------------------------------------------------------- 1. Anmeldung
      final settings = SettingsStore(MemoryKeyValueStore());
      final sessions = MemorySessionStore();
      final account = AccountController(settings: settings, sessions: sessions);
      await account.restore();
      expect(account.state, AccountState.noServer);

      await account.setServer(server.baseUrl, allowInsecure: true);
      expect(account.state, AccountState.signedOut);
      final user = await account.login('organist@gemeinde.de', 'geheim123');
      expect(user.email, 'organist@gemeinde.de');
      expect(account.state, AccountState.connected);

      // ------------------------------------------------------- 2. Download
      final libraryRoot = Directory('${dir.path}/library');
      final repo = PackageRepository(libraryRoot);
      final library = LibraryController(
        repository: repo,
        installer: PackageInstaller(repo),
        account: account,
        settings: settings,
      );
      await library.load();
      await library.refreshRemote();
      final summary = library.remote!.single;
      expect(library.statusFor(summary), PackageStatus.notDownloaded);

      library.download([summary]);
      expect(library.statusFor(summary), PackageStatus.downloading);
      await _waitForDownloads(library);

      // ------------------------------------------ 3. Validiert & gespeichert
      expect(
        library.taskFor(packageKey(account.server!.origin, 12)),
        isNull,
        reason: 'kein fehlgeschlagener Task',
      );
      expect(library.statusFor(summary), PackageStatus.upToDate);
      final installed = library.packages.single;
      expect(installed.manifest.steps, hasLength(4));
      expect(await repo.missingAudio(installed), isEmpty);
      expect(await repo.audioDir.list().length, 2, reason: 'dedupliziert');
      expect(await repo.tempDir.list().toList(), isEmpty, reason: 'aufgeräumt');

      // ---------------------------------------- 4. Netzwerk deaktivieren
      await server.close();
      final noNetwork = _NoNetwork();
      await HttpOverrides.runZoned(() async {
        // Sitzungsprüfung scheitert – Bibliothek bleibt unberührt.
        final offlineAccount = AccountController(
          settings: settings,
          sessions: sessions,
        );
        await offlineAccount.restore();
        await offlineAccount.verify();
        expect(offlineAccount.state, AccountState.offline);

        // --------------------------- 5. Öffnen aus frisch geladener Bibliothek
        final repo2 = PackageRepository(libraryRoot);
        final library2 = LibraryController(
          repository: repo2,
          installer: PackageInstaller(repo2),
          account: offlineAccount,
          settings: settings,
        );
        await library2.load();
        final pkg = library2.packages.single;
        expect(pkg.manifest.service.name, '1. Advent');
        expect(library2.hasUpdate(pkg), isFalse);

        final attemptsBeforePlayback = noNetwork.attempts;
        final engine = FakeAudioEngine();
        final progress = ProgressStore(File('${dir.path}/progress.json'));
        final player = PlayerController(
          package: pkg,
          engine: engine,
          resolveAudio: repo2.audioFile,
          progressStore: progress,
        );
        await player.init();
        expect(player.currentIndex, 0);

        // ------------------------------------------- 6. Titel abspielen
        await player.play();
        expect(player.status, PlaybackStatus.playing);
        expect(
          engine.loadedPath,
          repo2.audioFile(pkg.manifest.steps[0].audio!).path,
        );
        expect(File(engine.loadedPath!).existsSync(), isTrue);

        // ------------------------------------- 7. Titelende → Player stoppt
        engine.complete();
        await pumpEventQueue();
        expect(player.status, PlaybackStatus.idle);
        expect(engine.playing, isFalse);
        expect(player.playedIndices, {0});
        expect(player.currentIndex, 2, reason: 'leerer Slot übersprungen');

        // Es vergeht Zeit – nichts startet von selbst.
        await Future<void>.delayed(const Duration(milliseconds: 50));
        expect(engine.playCount, 1);
        expect(player.status, PlaybackStatus.idle);

        // ----------------------- 8. Nächster Titel nur durch Benutzeraktion
        await player.togglePlay();
        expect(engine.playCount, 2);
        expect(player.status, PlaybackStatus.playing);
        expect(engine.rate, 0.92, reason: 'Tempo-Variante aus dem Manifest');
        expect(
          engine.loadedPath,
          repo2.audioFile(pkg.manifest.steps[2].audio!).path,
        );

        engine.complete();
        await pumpEventQueue();
        expect(player.currentIndex, 3);
        expect(engine.playCount, 2);

        await player.close();
        await progress.idle;
        expect(
          noNetwork.attempts,
          attemptsBeforePlayback,
          reason: 'Wiedergabe greift nie auf das Netzwerk zu',
        );
      }, createHttpClient: noNetwork.createHttpClient);
    },
  );

  test(
    'abgebrochener/fehlgeschlagener Update-Download beschädigt das alte Paket nicht',
    () async {
      final settings = SettingsStore(MemoryKeyValueStore());
      final account = AccountController(
        settings: settings,
        sessions: MemorySessionStore(),
      );
      await account.restore();
      await account.setServer(server.baseUrl, allowInsecure: true);
      await account.login('organist@gemeinde.de', 'geheim123');
      final repo = PackageRepository(Directory('${dir.path}/library'));
      final library = LibraryController(
        repository: repo,
        installer: PackageInstaller(repo),
        account: account,
        settings: settings,
      );
      await library.load();
      await library.refreshRemote();
      library.download(library.remote!);
      await _waitForDownloads(library);
      final v1 = library.packages.single;

      // Server veröffentlicht Update, Verbindung bricht beim Laden ab.
      final extra = fakeAudio(3, size: 60000);
      server.addPackage(
        FakePackage(
          manifestJson(
            version: 'neue-version',
            steps: [stepJson(position: 0, audio: extra)],
          ),
          [extra],
        ),
      );
      await library.refreshRemote();
      expect(
        library.statusFor(library.remote!.single),
        PackageStatus.updateAvailable,
      );
      expect(library.hasUpdate(v1), isTrue);

      server.abortDownloadAfter = 4096;
      library.download(library.remote!);
      await _waitForDownloads(library);
      expect(library.statusFor(library.remote!.single), PackageStatus.failed);
      expect(library.packages.single.version, v1.version);
      expect(await repo.missingAudio(library.packages.single), isEmpty);
      expect(await repo.tempDir.list().toList(), isEmpty);

      // Abbruch durch den Benutzer.
      server.abortDownloadAfter = null;
      server.chunkDelay = const Duration(milliseconds: 30);
      library.download(library.remote!);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      library.cancel(packageKey(account.server!.origin, 12));
      await _waitForDownloads(library);
      expect(library.packages.single.version, v1.version);
      expect(
        library.statusFor(library.remote!.single),
        PackageStatus.updateAvailable,
      );

      // Erfolgreiches Update ersetzt atomar.
      server.chunkDelay = Duration.zero;
      library.download(library.remote!);
      await _waitForDownloads(library);
      expect(library.packages.single.version, 'neue-version');
      expect(library.statusFor(library.remote!.single), PackageStatus.upToDate);
      expect(
        await repo.audioDir.list().length,
        1,
        reason: 'alte Dateien entfernt',
      );
    },
  );

  test('abgelaufene Sitzung verhindert keine Offline-Wiedergabe', () async {
    final settings = SettingsStore(MemoryKeyValueStore());
    final account = AccountController(
      settings: settings,
      sessions: MemorySessionStore(),
    );
    await account.restore();
    await account.setServer(server.baseUrl, allowInsecure: true);
    await account.login('organist@gemeinde.de', 'geheim123');
    final repo = PackageRepository(Directory('${dir.path}/library'));
    final library = LibraryController(
      repository: repo,
      installer: PackageInstaller(repo),
      account: account,
      settings: settings,
    );
    await library.load();
    await library.refreshRemote();
    library.download(library.remote!);
    await _waitForDownloads(library);

    server.expireSessions();
    await library.refreshRemote();
    expect(account.state, AccountState.sessionExpired);
    expect(library.packages, hasLength(1));

    await account.logout();
    expect(
      library.packages,
      hasLength(1),
      reason: 'Abmelden löscht keine Pakete',
    );

    final engine = FakeAudioEngine();
    final player = PlayerController(
      package: library.packages.single,
      engine: engine,
      resolveAudio: repo.audioFile,
    );
    await player.init();
    await player.play();
    expect(player.status, PlaybackStatus.playing);
  });
}
