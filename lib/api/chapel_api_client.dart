import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../auth/session_store.dart';
import '../core/cancel_token.dart';
import '../core/failures.dart';
import '../packages/element_type.dart';
import '../packages/manifest.dart';
import 'models.dart';
import 'server_address.dart';

/// Name des Session-Cookies von nuxt-auth-utils (CHAPEL).
const String chapelSessionCookie = 'nuxt-session';

/// Ergebnis von `GET /api/packages/:id` mit ETag-Unterstützung.
sealed class ManifestResponse {
  const ManifestResponse();
}

class ManifestNotModified extends ManifestResponse {
  const ManifestNotModified();
}

class ManifestFetched extends ManifestResponse {
  const ManifestFetched(this.manifest, this.etag);
  final PackageManifest manifest;
  final String? etag;
}

/// HTTP-Client für die CHAPEL-API.
///
/// Verwendet `dart:io` direkt: Downloads werden gestreamt, sind abbrechbar und
/// TLS-Zertifikate werden immer vollständig geprüft (kein
/// `badCertificateCallback`). Das Session-Cookie wird manuell verwaltet, damit
/// es ausschließlich im [SessionStore] (Keychain/Keystore) liegt und nie in
/// Logs oder unverschlüsselten Dateien landet.
class ChapelApiClient {
  ChapelApiClient({
    required this.server,
    required SessionStore sessions,
    HttpClient Function()? httpClientFactory,
    this.requestTimeout = const Duration(seconds: 20),
    this.idleTimeout = const Duration(seconds: 30),
  }) : _sessions = sessions,
       _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final ServerAddress server;
  final SessionStore _sessions;
  final HttpClient Function() _httpClientFactory;
  final Duration requestTimeout;
  final Duration idleTimeout;

  HttpClient? _client;

  HttpClient get _http => _client ??= _httpClientFactory()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'CHAKOTAY';

  void close() {
    _client?.close(force: true);
    _client = null;
  }

  Future<bool> get hasSession async =>
      (await _sessions.read(server.origin))?.isNotEmpty ?? false;

  // ---------------------------------------------------------------- Auth

  /// Prüft, ob unter der Adresse ein CHAPEL-Server antwortet
  /// (`GET /api/auth/me` ist ohne Anmeldung erreichbar und liefert `{user}`).
  Future<void> probe() async {
    final response = await _send('GET', '/api/auth/me', authenticated: false);
    final body = await _readJson(response);
    if (response.statusCode != HttpStatus.ok ||
        body is! Map ||
        !body.containsKey('user')) {
      throw AppFailure(
        FailureKind.invalidResponse,
        statusCode: response.statusCode,
      );
    }
  }

  /// `POST /api/auth/login` – speichert bei Erfolg das Session-Cookie.
  Future<ChapelUser> login(String email, String password) async {
    final response = await _send(
      'POST',
      '/api/auth/login',
      jsonBody: {'email': email.trim(), 'password': password},
      authenticated: false,
    );
    final body = await _readJson(response);
    if (response.statusCode == 401 || response.statusCode == 400) {
      throw AppFailure(
        FailureKind.invalidCredentials,
        statusCode: response.statusCode,
      );
    }
    _ensureSuccess(response, body);
    if (!await hasSession) {
      throw const AppFailure(
        FailureKind.invalidResponse,
        detail: 'Server hat kein Session-Cookie gesetzt',
      );
    }
    return _userFrom(body) ??
        (throw const AppFailure(FailureKind.invalidResponse));
  }

  /// `GET /api/auth/me` – `null`, wenn die Sitzung nicht (mehr) gültig ist.
  Future<ChapelUser?> me() async {
    if (!await hasSession) return null;
    final response = await _send('GET', '/api/auth/me');
    final body = await _readJson(response);
    _ensureSuccess(response, body);
    final user = _userFrom(body);
    if (user == null) await _sessions.clear(server.origin);
    return user;
  }

  /// `POST /api/auth/logout` (best effort) und lokales Cookie löschen.
  Future<void> logout() async {
    try {
      if (await hasSession) {
        final response = await _send(
          'POST',
          '/api/auth/logout',
        ).timeout(const Duration(seconds: 5));
        await response.drain<void>();
      }
    } catch (_) {
      // Offline-Abmeldung ist erlaubt – lokal wird trotzdem gelöscht.
    } finally {
      await _sessions.clear(server.origin);
    }
  }

  // ------------------------------------------------------------ Packages

  /// `GET /api/packages`
  Future<List<PackageSummary>> listPackages() async {
    final response = await _send('GET', '/api/packages');
    final body = await _readJson(response);
    _ensureSuccess(response, body);
    if (body is! List) {
      throw const AppFailure(
        FailureKind.invalidResponse,
        detail: 'Paketliste ist kein Array',
      );
    }
    return [
      for (final e in body)
        if (e is Map) PackageSummary.fromJson(e.cast<String, Object?>()),
    ];
  }

  /// `GET /api/element-types` – Namen und Farben der Schrittarten.
  Future<Map<String, ElementType>> listElementTypes() async {
    final response = await _send('GET', '/api/element-types');
    final body = await _readJson(response);
    _ensureSuccess(response, body);
    if (body is! List) {
      throw const AppFailure(
        FailureKind.invalidResponse,
        detail: 'Elementtypen sind kein Array',
      );
    }
    return {for (final t in body.map(ElementType.tryParse).nonNulls) t.key: t};
  }

  /// `GET /api/packages/:id` mit optionalem `If-None-Match`.
  Future<ManifestResponse> fetchManifest(int serviceId, {String? etag}) async {
    final response = await _send(
      'GET',
      '/api/packages/$serviceId',
      headers: {HttpHeaders.ifNoneMatchHeader: ?etag},
    );
    if (response.statusCode == HttpStatus.notModified) {
      await response.drain<void>();
      return const ManifestNotModified();
    }
    final body = await _readJson(response);
    _ensureSuccess(response, body);
    try {
      return ManifestFetched(
        PackageManifest.fromJson(body),
        response.headers.value(HttpHeaders.etagHeader),
      );
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  /// `GET /api/packages/:id/download` – streamt das ZIP nach [target].
  ///
  /// Gibt die Paketversion aus `X-Chapel-Package-Version` zurück (falls
  /// gesendet). Bei Abbruch/Fehler bleibt [target] ggf. unvollständig – der
  /// Aufrufer verwirft die temporäre Datei.
  Future<String?> downloadPackage(
    int serviceId,
    File target, {
    void Function(int received, int? total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final response = await _send(
      'GET',
      '/api/packages/$serviceId/download',
      cancelToken: cancelToken,
    );
    if (response.statusCode != HttpStatus.ok) {
      final body = await _readJson(response);
      _ensureSuccess(response, body);
      throw AppFailure(
        FailureKind.invalidResponse,
        statusCode: response.statusCode,
      );
    }
    final total = response.contentLength >= 0 ? response.contentLength : null;
    final sink = target.openWrite();
    var received = 0;
    StreamSubscription<List<int>>? sub;
    final done = Completer<void>();
    void Function()? unregister;
    try {
      sub = response
          .timeout(idleTimeout)
          .listen(
            (chunk) {
              received += chunk.length;
              if (total != null && received > total) {
                sub?.cancel();
                if (!done.isCompleted) {
                  done.completeError(
                    const AppFailure(
                      FailureKind.corruptPackage,
                      detail: 'Mehr Daten als angekündigt',
                    ),
                  );
                }
                return;
              }
              sink.add(chunk);
              onProgress?.call(received, total);
            },
            onError: (Object e) {
              if (!done.isCompleted) done.completeError(e);
            },
            onDone: () {
              if (!done.isCompleted) done.complete();
            },
            cancelOnError: true,
          );
      unregister = cancelToken?.onCancel(() {
        sub?.cancel();
        if (!done.isCompleted) {
          done.completeError(const AppFailure(FailureKind.cancelled));
        }
      });
      await done.future;
      await sink.flush();
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) {
        throw const AppFailure(FailureKind.cancelled);
      }
      final failure = AppFailure.from(e);
      if (failure.kind == FailureKind.serverUnreachable ||
          failure.kind == FailureKind.unknown && e is! FileSystemException) {
        throw AppFailure(FailureKind.downloadInterrupted, detail: '$e');
      }
      throw failure;
    } finally {
      unregister?.call();
      await sink.close();
    }
    if (total != null && received != total) {
      throw AppFailure(
        FailureKind.downloadInterrupted,
        detail: '$received von $total Bytes',
      );
    }
    return response.headers.value('x-chapel-package-version');
  }

  // ------------------------------------------------------------- Helpers

  Future<HttpClientResponse> _send(
    String method,
    String path, {
    Object? jsonBody,
    Map<String, String> headers = const {},
    bool authenticated = true,
    CancelToken? cancelToken,
  }) async {
    cancelToken?.throwIfCancelled();
    final uri = server.resolve(path);
    try {
      final request = await _http.openUrl(method, uri).timeout(requestTimeout);
      final unregister = cancelToken?.onCancel(
        () => request.abort(const AppFailure(FailureKind.cancelled)),
      );
      try {
        request.followRedirects = false;
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        headers.forEach(request.headers.set);
        if (authenticated) {
          final cookie = await _sessions.read(server.origin);
          if (cookie != null && cookie.isNotEmpty) {
            request.headers.set(
              HttpHeaders.cookieHeader,
              '$chapelSessionCookie=$cookie',
            );
          }
        }
        if (jsonBody != null) {
          request.headers.contentType = ContentType.json;
          request.add(utf8.encode(jsonEncode(jsonBody)));
        }
        final response = await request.close().timeout(requestTimeout);
        await _captureSessionCookie(response);
        return response;
      } finally {
        unregister?.call();
      }
    } on AppFailure {
      rethrow;
    } catch (e) {
      if (cancelToken?.isCancelled ?? false) {
        throw const AppFailure(FailureKind.cancelled);
      }
      throw AppFailure.from(e);
    }
  }

  /// Übernimmt `Set-Cookie: nuxt-session=…` (auch Löschungen) in den Store.
  Future<void> _captureSessionCookie(HttpClientResponse response) async {
    final headers = response.headers[HttpHeaders.setCookieHeader];
    if (headers == null) return;
    for (final header in headers) {
      final parsed = parseSetCookie(header);
      if (parsed == null || parsed.name != chapelSessionCookie) continue;
      if (parsed.isDeletion) {
        await _sessions.clear(server.origin);
      } else {
        await _sessions.write(server.origin, parsed.value);
      }
    }
  }

  Future<Object?> _readJson(HttpClientResponse response) async {
    final text = await response
        .transform(utf8.decoder)
        .join()
        .timeout(requestTimeout)
        .catchError((Object e) => throw AppFailure.from(e));
    if (text.isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        throw const AppFailure(
          FailureKind.invalidResponse,
          detail: 'Antwort ist kein JSON',
        );
      }
      return null;
    }
  }

  void _ensureSuccess(HttpClientResponse response, Object? body) {
    final status = response.statusCode;
    if (status >= 200 && status < 300) return;
    final detail = body is Map ? body['statusMessage']?.toString() : null;
    if (status == 401) {
      // Abgelaufene/ungültige Sitzung: Cookie verwerfen, Pakete bleiben.
      unawaited(_sessions.clear(server.origin));
      throw AppFailure(
        FailureKind.sessionExpired,
        statusCode: status,
        detail: detail,
      );
    }
    if (status == 403) {
      throw AppFailure(
        FailureKind.passwordChangeRequired,
        statusCode: status,
        detail: detail,
      );
    }
    if (status == 404) {
      throw AppFailure(
        FailureKind.notFound,
        statusCode: status,
        detail: detail,
      );
    }
    if (status >= 300 && status < 400) {
      throw AppFailure(
        FailureKind.invalidResponse,
        statusCode: status,
        detail: 'Weiterleitung – Adresse prüfen',
      );
    }
    if (status >= 500) {
      throw AppFailure(
        FailureKind.serverError,
        statusCode: status,
        detail: detail,
      );
    }
    throw AppFailure(
      FailureKind.invalidResponse,
      statusCode: status,
      detail: detail,
    );
  }

  ChapelUser? _userFrom(Object? body) {
    if (body is! Map) return null;
    final user = body['user'];
    if (user is! Map) return null;
    return ChapelUser.fromJson(user.cast<String, Object?>());
  }
}

class SetCookie {
  const SetCookie(this.name, this.value, {this.isDeletion = false});
  final String name;
  final String value;
  final bool isDeletion;
}

/// Minimaler, toleranter `Set-Cookie`-Parser (RFC 6265 Abschnitt 5.2).
SetCookie? parseSetCookie(String header, {DateTime? now}) {
  final parts = header.split(';');
  final first = parts.first;
  final eq = first.indexOf('=');
  if (eq <= 0) return null;
  final name = first.substring(0, eq).trim();
  var value = first.substring(eq + 1).trim();
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }
  var deletion = value.isEmpty;
  for (final attr in parts.skip(1)) {
    final i = attr.indexOf('=');
    final key = (i < 0 ? attr : attr.substring(0, i)).trim().toLowerCase();
    final v = i < 0 ? '' : attr.substring(i + 1).trim();
    if (key == 'max-age') {
      final seconds = int.tryParse(v);
      if (seconds != null && seconds <= 0) deletion = true;
    } else if (key == 'expires') {
      try {
        final expires = HttpDate.parse(v);
        if (!expires.isAfter(now ?? DateTime.now())) deletion = true;
      } on Object {
        // Unlesbares Datum ignorieren.
      }
    }
  }
  return SetCookie(name, value, isDeletion: deletion);
}
