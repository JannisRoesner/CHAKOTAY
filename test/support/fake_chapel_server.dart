import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'chapel_fixtures.dart';

class FakeUser {
  FakeUser(this.email, this.password, {this.mustChangePassword = false});
  final String email;
  final String password;
  final bool mustChangePassword;
}

class FakePackage {
  FakePackage(this.manifest, this.audio, {Uint8List? zipOverride})
    : zip = zipOverride ?? buildPackageZip(manifest, audio);
  final Map<String, Object?> manifest;
  final List<FixtureAudio> audio;
  final Uint8List zip;
  int get id => (manifest['service'] as Map)['id'] as int;
  String get version => manifest['version'] as String;
}

/// Nachbildung der CHAPEL-API (Statuscodes, Cookie, Fehlerformat von h3)
/// auf einem echten lokalen HTTP-Server.
class FakeChapelServer {
  FakeChapelServer._(this._server);

  final HttpServer _server;
  final Map<String, FakeUser> users = {};
  final Map<int, FakePackage> packages = {};
  final Map<String, FakeUser> _sessions = {};
  final List<String> requests = [];
  int _counter = 0;

  /// Bricht Downloads nach so vielen Bytes ab (simuliert Verbindungsabbruch).
  int? abortDownloadAfter;

  /// Verzögerung je Chunk beim Download (für Abbruchtests).
  Duration chunkDelay = Duration.zero;

  static Future<FakeChapelServer> start() async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final fake = FakeChapelServer._(server);
    server.listen(fake._handle);
    return fake;
  }

  String get baseUrl => 'http://${_server.address.host}:${_server.port}';

  Future<void> close() => _server.close(force: true);

  void addPackage(FakePackage pkg) => packages[pkg.id] = pkg;

  /// Macht alle bestehenden Sitzungen ungültig (z. B. Server-Neustart mit
  /// neuem Session-Passwort).
  void expireSessions() => _sessions.clear();

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    requests.add('${req.method} $path');
    final res = req.response;
    try {
      final cookie = req.cookies
          .where((c) => c.name == 'nuxt-session')
          .map((c) => c.value)
          .firstOrNull;
      final user = cookie == null ? null : _sessions[cookie];

      if (path == '/api/auth/login' && req.method == 'POST') {
        final body = jsonDecode(await utf8.decoder.bind(req).join()) as Map;
        final email = (body['email'] as String?)?.trim().toLowerCase();
        final password = body['password'] as String?;
        if (email == null || email.isEmpty || password == null) {
          return _error(res, 400, 'E-Mail und Passwort erforderlich');
        }
        final u = users[email];
        if (u == null || u.password != password) {
          return _error(res, 401, 'Ungültige Anmeldedaten');
        }
        final token = 'Fe26.2**sealed-${++_counter}*abc~def';
        _sessions[token] = u;
        res.headers.add(
          'set-cookie',
          'nuxt-session=$token; Max-Age=7776000; Path=/; HttpOnly; SameSite=Lax',
        );
        return _json(res, {'user': _userJson(u)});
      }
      if (path == '/api/auth/me') {
        return _json(res, {'user': user == null ? null : _userJson(user)});
      }
      if (path == '/api/auth/logout') {
        if (cookie != null) _sessions.remove(cookie);
        res.headers.add('set-cookie', 'nuxt-session=; Max-Age=0; Path=/');
        return _json(res, {'ok': true});
      }

      // Middleware wie in CHAPEL: erst Passwortwechsel, dann Anmeldung.
      if (user?.mustChangePassword ?? false) {
        return _error(res, 403, 'Passwort muss zuerst geändert werden');
      }
      if (user == null) return _error(res, 401, 'Nicht angemeldet');

      if (path == '/api/packages') {
        final list = packages.values.toList()
          ..sort(
            (a, b) => ((b.manifest['service'] as Map)['serviceDate'] as String)
                .compareTo(
                  (a.manifest['service'] as Map)['serviceDate'] as String,
                ),
          );
        return _json(res, [
          for (final p in list)
            {
              'serviceId': p.id,
              'name': (p.manifest['service'] as Map)['name'],
              'serviceDate': (p.manifest['service'] as Map)['serviceDate'],
              'version': p.version,
              'updatedAt': (p.manifest['service'] as Map)['updatedAt'],
              'stepCount': (p.manifest['steps'] as List).length,
              'totalAudioBytes': p.manifest['totalAudioBytes'],
              'manifestUrl': '/api/packages/${p.id}',
              'downloadUrl': '/api/packages/${p.id}/download',
            },
        ]);
      }
      final download = RegExp(
        r'^/api/packages/(\d+)/download$',
      ).firstMatch(path);
      if (download != null) {
        final pkg = packages[int.parse(download.group(1)!)];
        if (pkg == null) return _error(res, 404, 'Gottesdienst nicht gefunden');
        res.headers
          ..contentType = ContentType('application', 'zip')
          ..contentLength = pkg.zip.length
          ..set('etag', '"${pkg.version}"')
          ..set('x-chapel-package-version', pkg.version);
        const chunk = 1024;
        for (var o = 0; o < pkg.zip.length; o += chunk) {
          if (abortDownloadAfter != null && o >= abortDownloadAfter!) {
            // Verbindung vorzeitig schließen: weniger Bytes als Content-Length.
            try {
              await res.close();
            } catch (_) {}
            return;
          }
          final end = (o + chunk).clamp(0, pkg.zip.length);
          res.add(pkg.zip.sublist(o, end));
          if (chunkDelay > Duration.zero) {
            await res.flush();
            await Future<void>.delayed(chunkDelay);
          }
        }
        await res.close();
        return;
      }
      final manifest = RegExp(r'^/api/packages/(\d+)$').firstMatch(path);
      if (manifest != null) {
        final pkg = packages[int.parse(manifest.group(1)!)];
        if (pkg == null) return _error(res, 404, 'Gottesdienst nicht gefunden');
        final etag = '"${pkg.version}"';
        res.headers
          ..set('etag', etag)
          ..set('cache-control', 'private, no-cache');
        if (req.headers.value('if-none-match') == etag) {
          res.statusCode = 304;
          await res.close();
          return;
        }
        return _json(res, pkg.manifest);
      }
      return _error(res, 404, 'Not Found');
    } catch (e) {
      try {
        await _error(res, 500, '$e');
      } catch (_) {}
    }
  }

  Map<String, Object?> _userJson(FakeUser u) => {
    'id': 1,
    'email': u.email,
    'name': 'Organist',
    'role': 'editor',
    'mustChangePassword': u.mustChangePassword,
    'colorScheme': 'chapel-green',
    'appearanceMode': 'system',
  };

  Future<void> _json(HttpResponse res, Object? body) async {
    res.headers.contentType = ContentType.json;
    res.write(jsonEncode(body));
    await res.close();
  }

  Future<void> _error(HttpResponse res, int status, String message) async {
    res.statusCode = status;
    await _json(res, {
      'error': true,
      'statusCode': status,
      'statusMessage': message,
      'message': message,
    });
  }
}
