import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../api/models.dart';
import '../auth/account_controller.dart';
import '../core/cancel_token.dart';
import '../core/failures.dart';
import '../packages/package_installer.dart';
import '../packages/package_repository.dart';
import '../settings/settings_store.dart';

/// Status eines Gottesdienstes aus Sicht des Geräts.
enum PackageStatus {
  notDownloaded,
  upToDate,
  updateAvailable,
  downloading,
  failed,
}

enum DownloadPhase { queued, downloading, verifying }

/// Laufender oder fehlgeschlagener Download.
class DownloadTask {
  DownloadTask(this.summary, this.serverOrigin);

  final PackageSummary summary;
  final String serverOrigin;
  final CancelToken cancelToken = CancelToken();

  DownloadPhase phase = DownloadPhase.queued;
  int received = 0;
  int? total;
  int verified = 0;
  int verifyTotal = 0;
  AppFailure? failure;

  String get key => packageKey(serverOrigin, summary.serviceId);
  bool get isActive => failure == null;

  /// Fortschritt 0…1 oder `null` (unbestimmt).
  double? get fraction {
    switch (phase) {
      case DownloadPhase.queued:
        return null;
      case DownloadPhase.downloading:
        final t = total ?? summary.totalAudioBytes;
        return t > 0 ? (received / t).clamp(0, 1) : null;
      case DownloadPhase.verifying:
        return verifyTotal > 0 ? (verified / verifyTotal).clamp(0, 1) : null;
    }
  }
}

/// Offline-Bibliothek und Downloads.
class LibraryController extends ChangeNotifier {
  LibraryController({
    required this.repository,
    required this.installer,
    required this.account,
    required this.settings,
  });

  final PackageRepository repository;
  final PackageInstaller installer;
  final AccountController account;
  final SettingsStore settings;

  List<LocalPackage> _packages = [];
  bool _loaded = false;
  bool get loaded => _loaded;

  /// Lokale Pakete, sortiert gemäß Einstellung.
  List<LocalPackage> get packages {
    final list = List.of(_packages);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    int byDate(LocalPackage a, LocalPackage b) => a.manifest.service.serviceDate
        .compareTo(b.manifest.service.serviceDate);
    switch (settings.sort) {
      case LibrarySort.newestFirst:
        list.sort((a, b) => byDate(b, a));
      case LibrarySort.oldestFirst:
        list.sort(byDate);
      case LibrarySort.upcomingFirst:
        // Anstehende Gottesdienste aufsteigend (nächster zuerst), danach
        // vergangene absteigend (jüngster zuerst).
        bool upcoming(LocalPackage p) =>
            !p.manifest.service.serviceDate.toLocal().isBefore(today);
        list.sort((a, b) {
          final ua = upcoming(a), ub = upcoming(b);
          if (ua != ub) return ua ? -1 : 1;
          return ua ? byDate(a, b) : byDate(b, a);
        });
    }
    return list;
  }

  List<PackageSummary>? _remote;
  List<PackageSummary>? get remote => _remote;
  bool _loadingRemote = false;
  bool get loadingRemote => _loadingRemote;
  AppFailure? _remoteFailure;
  AppFailure? get remoteFailure => _remoteFailure;

  final Map<String, DownloadTask> _tasks = {};
  final List<DownloadTask> _queue = [];
  bool _processing = false;

  DownloadTask? taskFor(String key) => _tasks[key];
  bool get hasActiveDownloads => _tasks.values.any((t) => t.isActive);

  Future<void> load() async {
    await repository.recover();
    _packages = await repository.loadAll();
    _loaded = true;
    notifyListeners();
  }

  LocalPackage? localFor(String key) {
    for (final p in _packages) {
      if (p.key == key) return p;
    }
    return null;
  }

  /// Hinweis „Update verfügbar“ – auch offline anhand der letzten Abfrage.
  bool hasUpdate(LocalPackage pkg) {
    final remoteVersion = settings.remoteVersions[pkg.key];
    return remoteVersion != null && remoteVersion != pkg.version;
  }

  PackageStatus statusFor(PackageSummary summary) {
    final origin = account.server?.origin;
    if (origin == null) return PackageStatus.notDownloaded;
    final key = packageKey(origin, summary.serviceId);
    final task = _tasks[key];
    if (task != null) {
      return task.isActive ? PackageStatus.downloading : PackageStatus.failed;
    }
    final local = localFor(key);
    if (local == null) return PackageStatus.notDownloaded;
    return local.version == summary.version
        ? PackageStatus.upToDate
        : PackageStatus.updateAvailable;
  }

  /// Ruft `GET /api/packages` ab und merkt sich die Versionen.
  Future<void> refreshRemote() async {
    final client = account.client;
    if (client == null) return;
    _loadingRemote = true;
    _remoteFailure = null;
    notifyListeners();
    try {
      final list = await client.listPackages();
      _remote = list;
      final origin = account.server!.origin;
      final versions = Map.of(settings.remoteVersions)
        ..removeWhere(
          (k, _) => k.startsWith(packageKey(origin, 0).split('_').first),
        );
      for (final s in list) {
        versions[packageKey(origin, s.serviceId)] = s.version;
      }
      await settings.setRemoteVersions(versions);
      if (account.state != AccountState.connected) await account.verify();
    } on AppFailure catch (e) {
      _remoteFailure = e;
      account.handleFailure(e);
    } finally {
      _loadingRemote = false;
      notifyListeners();
    }
  }

  void clearRemote() {
    _remote = null;
    _remoteFailure = null;
    notifyListeners();
  }

  /// Reiht Downloads ein; sie laufen nacheinander.
  void download(Iterable<PackageSummary> summaries) {
    final origin = account.server?.origin;
    if (origin == null) return;
    for (final s in summaries) {
      final key = packageKey(origin, s.serviceId);
      final existing = _tasks[key];
      if (existing != null && existing.isActive) continue;
      final task = DownloadTask(s, origin);
      _tasks[key] = task;
      _queue.add(task);
    }
    notifyListeners();
    unawaited(_process());
  }

  void cancel(String key) {
    final task = _tasks[key];
    if (task == null) return;
    task.cancelToken.cancel();
    if (task.phase == DownloadPhase.queued) {
      _queue.remove(task);
      _tasks.remove(key);
    }
    notifyListeners();
  }

  void dismissFailure(String key) {
    final task = _tasks[key];
    if (task != null && !task.isActive) {
      _tasks.remove(key);
      notifyListeners();
    }
  }

  Future<void> _process() async {
    if (_processing) return;
    _processing = true;
    try {
      while (_queue.isNotEmpty) {
        final task = _queue.removeAt(0);
        await _run(task);
      }
    } finally {
      _processing = false;
    }
  }

  Future<void> _run(DownloadTask task) async {
    final client = account.client;
    if (client == null || client.server.origin != task.serverOrigin) {
      task.failure = const AppFailure(FailureKind.invalidServerAddress);
      notifyListeners();
      return;
    }
    await repository.init();
    final temp = File(
      '${repository.tempDir.path}/'
      '${task.key}-${Random.secure().nextInt(1 << 32)}.zip',
    );
    var lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
    void throttled() {
      final now = DateTime.now();
      if (now.difference(lastNotify) > const Duration(milliseconds: 120)) {
        lastNotify = now;
        notifyListeners();
      }
    }

    try {
      task.phase = DownloadPhase.downloading;
      notifyListeners();
      final version = await client.downloadPackage(
        task.summary.serviceId,
        temp,
        cancelToken: task.cancelToken,
        onProgress: (received, total) {
          task
            ..received = received
            ..total = total;
          throttled();
        },
      );
      task.phase = DownloadPhase.verifying;
      notifyListeners();
      final pkg = await installer.install(
        temp,
        serverOrigin: task.serverOrigin,
        expectedServiceId: task.summary.serviceId,
        expectedVersion: version,
        cancelToken: task.cancelToken,
        onProgress: (done, total) {
          task
            ..verified = done
            ..verifyTotal = total;
          throttled();
        },
      );
      _packages = [
        for (final p in _packages)
          if (p.key != pkg.key) p,
        pkg,
      ];
      final versions = Map.of(settings.remoteVersions)..[pkg.key] = pkg.version;
      await settings.setRemoteVersions(versions);
      _tasks.remove(task.key);
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.cancelled) {
        _tasks.remove(task.key);
      } else {
        task.failure = e;
        account.handleFailure(e);
      }
    } catch (e) {
      task.failure = AppFailure.from(e);
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } on FileSystemException {
        // Wird beim nächsten Start aufgeräumt.
      }
      notifyListeners();
    }
  }

  Future<void> delete(LocalPackage pkg) async {
    await repository.delete(pkg.key);
    _packages = _packages.where((p) => p.key != pkg.key).toList();
    notifyListeners();
  }

  Future<int> storageBytes() => repository.storageBytes();
}
