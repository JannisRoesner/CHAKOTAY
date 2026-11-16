import 'package:flutter/foundation.dart';

import '../api/chapel_api_client.dart';
import '../api/models.dart';
import '../api/server_address.dart';
import '../core/failures.dart';
import '../settings/settings_store.dart';
import 'session_store.dart';

enum AccountState {
  /// Noch keine Serveradresse hinterlegt.
  noServer,

  /// Server bekannt, aber keine Sitzung.
  signedOut,

  /// Sitzung vorhanden, Server noch nicht geprüft.
  unverified,

  /// Sitzung vom Server bestätigt.
  connected,

  /// Server hat die Sitzung abgelehnt (401).
  sessionExpired,

  /// Benutzer muss sein Passwort in der Weboberfläche ändern (403).
  passwordChangeRequired,

  /// Server nicht erreichbar / Gerät offline.
  offline,
}

/// Serverkonfiguration, Anmeldung und Sitzungsstatus.
///
/// Der Zustand beeinflusst ausschließlich das Herunterladen. Die Wiedergabe
/// bereits installierter Pakete hängt nie davon ab.
class AccountController extends ChangeNotifier {
  AccountController({
    required this.settings,
    required this.sessions,
    this.clientFactory,
  });

  final SettingsStore settings;
  final SessionStore sessions;

  /// Für Tests austauschbar.
  final ChapelApiClient Function(ServerAddress server, SessionStore sessions)?
  clientFactory;

  ServerAddress? _server;
  ServerAddress? get server => _server;

  ChapelApiClient? _client;
  ChapelApiClient? get client => _client;

  ChapelUser? get user => settings.cachedUser;

  AccountState _state = AccountState.noServer;
  AccountState get state => _state;

  AppFailure? _lastFailure;
  AppFailure? get lastFailure => _lastFailure;

  bool _busy = false;
  bool get busy => _busy;

  bool get canDownload =>
      _state == AccountState.connected || _state == AccountState.unverified;

  /// Lädt die gespeicherte Serveradresse und prüft lokal, ob eine Sitzung existiert.
  Future<void> restore() async {
    await settings.ready;
    final url = settings.serverUrl;
    if (url == null) {
      _setState(AccountState.noServer);
      return;
    }
    try {
      _useServer(
        ServerAddress.parse(url, allowInsecure: settings.allowInsecure),
      );
    } on AppFailure {
      _setState(AccountState.noServer);
      return;
    }
    final has = await _client!.hasSession;
    _setState(has ? AccountState.unverified : AccountState.signedOut);
  }

  void _useServer(ServerAddress server) {
    _client?.close();
    _server = server;
    _client =
        clientFactory?.call(server, sessions) ??
        ChapelApiClient(server: server, sessions: sessions);
  }

  /// Validiert und speichert eine neue Serveradresse. Wechselt der Server,
  /// wird die alte Sitzung verworfen (heruntergeladene Pakete bleiben).
  Future<void> setServer(String input, {required bool allowInsecure}) async {
    final address = ServerAddress.parse(input, allowInsecure: allowInsecure);
    _busy = true;
    notifyListeners();
    try {
      // Erreichbarkeit und CHAPEL-API prüfen, bevor etwas gespeichert wird.
      final probe =
          clientFactory?.call(address, sessions) ??
          ChapelApiClient(server: address, sessions: sessions);
      try {
        await probe.probe();
      } finally {
        probe.close();
      }
    } finally {
      _busy = false;
      notifyListeners();
    }
    if (address == _server) {
      await settings.setServer(address.origin, allowInsecure: allowInsecure);
      final has = await _client!.hasSession;
      _setState(has ? AccountState.unverified : AccountState.signedOut);
      return;
    }
    if (_server != null) await sessions.clear(_server!.origin);
    _useServer(address);
    await settings.setServer(address.origin, allowInsecure: allowInsecure);
    await settings.setCachedUser(null);
    _lastFailure = null;
    final has = await _client!.hasSession;
    _setState(has ? AccountState.unverified : AccountState.signedOut);
  }

  Future<ChapelUser> login(String email, String password) async {
    final client = _client;
    if (client == null) {
      throw const AppFailure(FailureKind.invalidServerAddress);
    }
    _busy = true;
    _lastFailure = null;
    notifyListeners();
    try {
      final user = await client.login(email, password);
      await settings.setCachedUser(user);
      _setState(
        user.mustChangePassword
            ? AccountState.passwordChangeRequired
            : AccountState.connected,
      );
      return user;
    } on AppFailure catch (e) {
      _lastFailure = e;
      rethrow;
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Prüft die Sitzung über `GET /api/auth/me`. Netzwerkfehler ändern nur
  /// den Status, nie die lokale Bibliothek.
  Future<void> verify() async {
    final client = _client;
    if (client == null) return;
    try {
      final user = await client.me();
      if (user == null) {
        final hadUser = settings.cachedUser != null;
        _setState(
          hadUser ? AccountState.sessionExpired : AccountState.signedOut,
        );
        return;
      }
      await settings.setCachedUser(user);
      _lastFailure = null;
      _setState(
        user.mustChangePassword
            ? AccountState.passwordChangeRequired
            : AccountState.connected,
      );
    } on AppFailure catch (e) {
      handleFailure(e);
    }
  }

  /// Übernimmt Sitzungsfolgen eines API-Fehlers in den Status.
  void handleFailure(AppFailure e) {
    _lastFailure = e;
    switch (e.kind) {
      case FailureKind.sessionExpired:
        _setState(AccountState.sessionExpired);
      case FailureKind.passwordChangeRequired:
        _setState(AccountState.passwordChangeRequired);
      case FailureKind.offline:
      case FailureKind.serverUnreachable:
      case FailureKind.tlsError:
        _setState(AccountState.offline);
      default:
        notifyListeners();
    }
  }

  /// Öffnet die Servereingabe erneut, ohne Daten zu verwerfen.
  void editServer() => _setState(AccountState.noServer);

  Future<void> logout() async {
    await _client?.logout();
    await settings.setCachedUser(null);
    _lastFailure = null;
    _setState(_server == null ? AccountState.noServer : AccountState.signedOut);
  }

  /// Seite der CHAPEL-Weboberfläche zum Ändern des Passworts.
  Uri? get passwordChangeUri => _server?.resolve('/settings');

  void _setState(AccountState state) {
    _state = state;
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.close();
    super.dispose();
  }
}
