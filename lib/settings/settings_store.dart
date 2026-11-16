import 'dart:convert';

import 'package:flutter/material.dart';
import 'key_value_store.dart';

import '../api/models.dart';

enum LibrarySort { upcomingFirst, newestFirst, oldestFirst }

/// Nicht-geheime Einstellungen (SharedPreferences / NSUserDefaults).
///
/// Zugangsdaten liegen hier **nicht** – das Session-Cookie steckt im
/// [SecureSessionStore], Passwörter werden nie gespeichert.
class SettingsStore extends ChangeNotifier {
  SettingsStore(this._prefs) {
    _load();
  }

  final KeyValueStore _prefs;

  static const _kServer = 'server.url';
  static const _kAllowInsecure = 'server.allowInsecure';
  static const _kUser = 'account.user';
  static const _kTheme = 'ui.themeMode';
  static const _kKeepAwake = 'playback.keepScreenOn';
  static const _kSort = 'library.sort';
  static const _kRemote = 'library.remoteVersions';
  static const _kLastSync = 'library.lastSync';

  String? serverUrl;
  bool allowInsecure = false;
  ChapelUser? cachedUser;
  ThemeMode themeMode = ThemeMode.system;
  bool keepScreenOn = true;
  LibrarySort sort = LibrarySort.upcomingFirst;

  /// Letzte bekannte Server-Versionen je Paketschlüssel (für den
  /// „Update verfügbar“-Hinweis auch offline).
  Map<String, String> remoteVersions = {};
  DateTime? lastSync;

  late final Future<void> ready;

  void _load() {
    ready = () async {
      serverUrl = await _prefs.getString(_kServer);
      allowInsecure = await _prefs.getBool(_kAllowInsecure) ?? false;
      final userJson = await _prefs.getString(_kUser);
      if (userJson != null) {
        try {
          cachedUser = ChapelUser.fromJson(
            (jsonDecode(userJson) as Map).cast<String, Object?>(),
          );
        } catch (_) {
          cachedUser = null;
        }
      }
      themeMode =
          ThemeMode.values.asNameMap()[await _prefs.getString(_kTheme) ?? ''] ??
          ThemeMode.system;
      keepScreenOn = await _prefs.getBool(_kKeepAwake) ?? true;
      sort =
          LibrarySort.values.asNameMap()[await _prefs.getString(_kSort) ??
              ''] ??
          LibrarySort.upcomingFirst;
      final remote = await _prefs.getString(_kRemote);
      if (remote != null) {
        try {
          remoteVersions = (jsonDecode(remote) as Map).cast<String, String>();
        } catch (_) {
          remoteVersions = {};
        }
      }
      final sync = await _prefs.getInt(_kLastSync);
      lastSync = sync == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(sync);
      notifyListeners();
    }();
  }

  Future<void> setServer(String? url, {required bool allowInsecure}) async {
    serverUrl = url;
    this.allowInsecure = allowInsecure;
    if (url == null) {
      await _prefs.remove(_kServer);
    } else {
      await _prefs.setString(_kServer, url);
    }
    await _prefs.setBool(_kAllowInsecure, allowInsecure);
    notifyListeners();
  }

  Future<void> setCachedUser(ChapelUser? user) async {
    cachedUser = user;
    if (user == null) {
      await _prefs.remove(_kUser);
    } else {
      await _prefs.setString(_kUser, jsonEncode(user.toJson()));
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    await _prefs.setString(_kTheme, mode.name);
  }

  Future<void> setKeepScreenOn(bool value) async {
    keepScreenOn = value;
    notifyListeners();
    await _prefs.setBool(_kKeepAwake, value);
  }

  Future<void> setSort(LibrarySort value) async {
    sort = value;
    notifyListeners();
    await _prefs.setString(_kSort, value.name);
  }

  Future<void> setRemoteVersions(Map<String, String> versions) async {
    remoteVersions = Map.of(versions);
    lastSync = DateTime.now();
    notifyListeners();
    await _prefs.setString(_kRemote, jsonEncode(remoteVersions));
    await _prefs.setInt(_kLastSync, lastSync!.millisecondsSinceEpoch);
  }
}
