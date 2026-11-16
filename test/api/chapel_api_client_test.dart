import 'dart:io';

import 'package:chakotay/api/chapel_api_client.dart';
import 'package:chakotay/api/server_address.dart';
import 'package:chakotay/auth/session_store.dart';
import 'package:chakotay/core/cancel_token.dart';
import 'package:chakotay/core/failures.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chapel_fixtures.dart';
import '../support/fake_chapel_server.dart';

Matcher failure(FailureKind kind) =>
    throwsA(isA<AppFailure>().having((f) => f.kind, 'kind', kind));

void main() {
  late FakeChapelServer server;
  late MemorySessionStore sessions;
  late ChapelApiClient client;
  late Directory dir;
  final audio = fakeAudio(7, size: 50000);

  setUp(() async {
    server = await FakeChapelServer.start();
    server.users['organist@gemeinde.de'] = FakeUser(
      'organist@gemeinde.de',
      'geheim123',
    );
    server.users['neu@gemeinde.de'] = FakeUser(
      'neu@gemeinde.de',
      'start123',
      mustChangePassword: true,
    );
    server.addPackage(
      FakePackage(
        manifestJson(
          steps: [
            stepJson(position: 0, audio: audio),
            stepJson(position: 1),
          ],
        ),
        [audio],
      ),
    );
    sessions = MemorySessionStore();
    client = ChapelApiClient(
      server: ServerAddress.parse(server.baseUrl, allowInsecure: true),
      sessions: sessions,
    );
    dir = await Directory.systemTemp.createTemp('chakotay_api_');
  });

  tearDown(() async {
    client.close();
    await server.close();
    await dir.delete(recursive: true);
  });

  group('Authentifizierung', () {
    test('Login speichert nuxt-session und sendet sie mit', () async {
      final user = await client.login(' organist@gemeinde.de ', 'geheim123');
      expect(user.email, 'organist@gemeinde.de');
      expect(user.mustChangePassword, isFalse);
      final cookie = await sessions.read(client.server.origin);
      expect(cookie, startsWith('Fe26.2**'));
      expect((await client.me())?.email, 'organist@gemeinde.de');
      expect(await client.listPackages(), hasLength(1));
    });

    test('falsche Anmeldedaten', () async {
      await expectLater(
        client.login('organist@gemeinde.de', 'falsch'),
        failure(FailureKind.invalidCredentials),
      );
      expect(await client.hasSession, isFalse);
    });

    test('ohne Sitzung → 401 → sessionExpired', () async {
      await expectLater(
        client.listPackages(),
        failure(FailureKind.sessionExpired),
      );
    });

    test('abgelaufene Sitzung löscht das gespeicherte Cookie', () async {
      await client.login('organist@gemeinde.de', 'geheim123');
      server.expireSessions();
      await expectLater(
        client.listPackages(),
        failure(FailureKind.sessionExpired),
      );
      await Future<void>.delayed(Duration.zero);
      expect(await client.hasSession, isFalse);
    });

    test('Passwortwechsel erforderlich → 403', () async {
      final user = await client.login('neu@gemeinde.de', 'start123');
      expect(user.mustChangePassword, isTrue);
      await expectLater(
        client.listPackages(),
        failure(FailureKind.passwordChangeRequired),
      );
    });

    test('Logout löscht die Sitzung lokal und auf dem Server', () async {
      await client.login('organist@gemeinde.de', 'geheim123');
      await client.logout();
      expect(await client.hasSession, isFalse);
      expect(await client.me(), isNull);
    });

    test('probe erkennt CHAPEL-Server', () async {
      await client.probe();
      final other = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      other.listen(
        (r) => r.response
          ..write('<html>')
          ..close(),
      );
      final wrong = ChapelApiClient(
        server: ServerAddress.parse(
          'http://127.0.0.1:${other.port}',
          allowInsecure: true,
        ),
        sessions: sessions,
      );
      await expectLater(wrong.probe(), failure(FailureKind.invalidResponse));
      wrong.close();
      await other.close(force: true);
    });

    test('nicht erreichbarer Server', () async {
      final port = server.baseUrl.split(':').last;
      await server.close();
      final dead = ChapelApiClient(
        server: ServerAddress.parse(
          'http://127.0.0.1:$port',
          allowInsecure: true,
        ),
        sessions: sessions,
      );
      await expectLater(dead.probe(), failure(FailureKind.serverUnreachable));
      dead.close();
      server = await FakeChapelServer.start(); // für tearDown
    });
  });

  group('Pakete', () {
    setUp(() => client.login('organist@gemeinde.de', 'geheim123'));

    test('Paketliste wird korrekt gelesen', () async {
      final list = await client.listPackages();
      final s = list.single;
      expect(s.serviceId, 12);
      expect(s.name, '1. Advent');
      expect(s.stepCount, 2);
      expect(s.totalAudioBytes, audio.bytes.length);
      expect(s.serviceDate, DateTime.utc(2026, 11, 29));
      expect(s.downloadUrl, '/api/packages/12/download');
    });

    test('Manifest mit ETag und 304', () async {
      final first = await client.fetchManifest(12);
      expect(first, isA<ManifestFetched>());
      final fetched = first as ManifestFetched;
      expect(fetched.manifest.steps, hasLength(2));
      expect(fetched.etag, '"${fetched.manifest.version}"');
      final second = await client.fetchManifest(12, etag: fetched.etag);
      expect(second, isA<ManifestNotModified>());
      await expectLater(
        client.fetchManifest(99),
        failure(FailureKind.notFound),
      );
    });

    test('Download streamt mit Fortschritt und Version', () async {
      final target = File('${dir.path}/p.zip');
      final progress = <int>[];
      int? total;
      final version = await client.downloadPackage(
        12,
        target,
        onProgress: (r, t) {
          progress.add(r);
          total = t;
        },
      );
      final pkg = server.packages[12]!;
      expect(version, pkg.version);
      expect(await target.readAsBytes(), pkg.zip);
      expect(total, pkg.zip.length);
      expect(progress.last, pkg.zip.length);
    });

    test('Verbindungsabbruch → downloadInterrupted', () async {
      server.abortDownloadAfter = 8192;
      await expectLater(
        client.downloadPackage(12, File('${dir.path}/p.zip')),
        failure(FailureKind.downloadInterrupted),
      );
    });

    test('Download ist abbrechbar', () async {
      server.chunkDelay = const Duration(milliseconds: 20);
      final token = CancelToken();
      final future = client.downloadPackage(
        12,
        File('${dir.path}/p.zip'),
        cancelToken: token,
        onProgress: (r, _) {
          if (r > 4096) token.cancel();
        },
      );
      await expectLater(future, failure(FailureKind.cancelled));
    });
  });

  group('ServerAddress', () {
    test('ergänzt HTTPS und normalisiert', () {
      final a = ServerAddress.parse('  Chapel.Gemeinde.de/ ');
      expect(a.origin, 'https://chapel.gemeinde.de');
      expect(a.isSecure, isTrue);
      expect(
        a.resolve('/api/packages').toString(),
        'https://chapel.gemeinde.de/api/packages',
      );
      final sub = ServerAddress.parse('https://example.org/chapel/');
      expect(
        sub.resolve('/api/auth/me').toString(),
        'https://example.org/chapel/api/auth/me',
      );
      expect(ServerAddress.parse('https://h:8443').origin, 'https://h:8443');
    });

    test('HTTP nur nach ausdrücklicher Freigabe', () {
      expect(
        () => ServerAddress.parse('http://192.168.1.5:3001'),
        failure(FailureKind.insecureConnection),
      );
      expect(
        ServerAddress.parse(
          'http://192.168.1.5:3001',
          allowInsecure: true,
        ).isSecure,
        isFalse,
      );
    });

    test('ungültige Adressen', () {
      for (final input in [
        '',
        'ftp://x',
        'https://',
        'a b',
        'https://u:p@x.de',
        'x.de?q=1',
      ]) {
        expect(
          () => ServerAddress.parse(input),
          failure(FailureKind.invalidServerAddress),
          reason: input,
        );
      }
    });
  });

  group('Set-Cookie', () {
    test('parst Wert und Löschungen', () {
      final c = parseSetCookie(
        'nuxt-session=Fe26.2**a*b~c; Max-Age=7776000; Path=/; HttpOnly; SameSite=Lax',
      )!;
      expect(c.name, 'nuxt-session');
      expect(c.value, 'Fe26.2**a*b~c');
      expect(c.isDeletion, isFalse);
      expect(parseSetCookie('nuxt-session=; Max-Age=0')!.isDeletion, isTrue);
      expect(
        parseSetCookie(
          'nuxt-session=x; Expires=Thu, 01 Jan 1970 00:00:00 GMT',
        )!.isDeletion,
        isTrue,
      );
      expect(parseSetCookie('kaputt'), isNull);
    });
  });
}
