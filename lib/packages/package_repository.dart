import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'manifest.dart';

/// Ein vollständig installierter, geprüfter Gottesdienst.
class LocalPackage {
  const LocalPackage({
    required this.serverOrigin,
    required this.manifest,
    required this.installedAt,
  });

  final String serverOrigin;
  final PackageManifest manifest;
  final DateTime installedAt;

  int get serviceId => manifest.service.id;
  String get version => manifest.version;
  String get key => packageKey(serverOrigin, serviceId);

  factory LocalPackage.fromJson(Map<String, Object?> json) => LocalPackage(
    serverOrigin: json['serverOrigin']! as String,
    installedAt: DateTime.parse(json['installedAt']! as String),
    manifest: PackageManifest.fromJson(json['manifest']),
  );

  Map<String, Object?> toJson() => {
    'schema': 1,
    'serverOrigin': serverOrigin,
    'installedAt': installedAt.toUtc().toIso8601String(),
    'manifest': manifest.toJson(),
  };
}

/// Stabiler, dateisystemsicherer Schlüssel je Server und Gottesdienst.
String packageKey(String serverOrigin, int serviceId) {
  final serverHash = sha256
      .convert(utf8.encode(serverOrigin))
      .toString()
      .substring(0, 12);
  return '${serverHash}_$serviceId';
}

/// Lokale Offline-Bibliothek.
///
/// Layout unterhalb von [root]:
/// ```
/// audio/<sha256>.<ext>     gemeinsame, deduplizierte Audiodateien
/// packages/<key>.json      Paketdatensätze (Manifest + Metadaten)
/// tmp/                     Downloads und Entpack-Zwischenstände
/// ```
/// Ein Paket gilt erst als installiert, wenn sein Datensatz atomar (Schreiben
/// in Temp-Datei + `rename`) abgelegt wurde – und das passiert erst, nachdem
/// alle Audiodateien geprüft in `audio/` liegen. Audiodateien werden nur
/// gelöscht, wenn kein Datensatz mehr auf sie verweist.
class PackageRepository {
  PackageRepository(this.root);

  final Directory root;

  Directory get audioDir => Directory('${root.path}/audio');
  Directory get packagesDir => Directory('${root.path}/packages');
  Directory get tempDir => Directory('${root.path}/tmp');

  Future<void> _lock = Future.value();

  /// Serialisiert Installationen, Löschungen und Aufräumen.
  Future<T> synchronized<T>(Future<T> Function() action) {
    final previous = _lock;
    final completer = Completer<void>();
    _lock = completer.future;
    return previous.then((_) => action()).whenComplete(completer.complete);
  }

  Future<void> init() async {
    await audioDir.create(recursive: true);
    await packagesDir.create(recursive: true);
    await tempDir.create(recursive: true);
  }

  /// Entfernt Reste abgebrochener Downloads (z. B. nach App-Beendigung)
  /// und verwaiste Audiodateien.
  Future<void> recover() => synchronized(() async {
    await init();
    await for (final e in tempDir.list()) {
      await _deleteQuietly(e);
    }
    await for (final e in packagesDir.list()) {
      if (e is File && e.path.endsWith('.tmp')) await _deleteQuietly(e);
    }
    await _collectGarbage();
  });

  File audioFile(PackageAudio audio) =>
      File('${audioDir.path}/${audio.libraryFileName}');

  File _recordFile(String key) => File('${packagesDir.path}/$key.json');

  Future<List<LocalPackage>> loadAll() async {
    await init();
    final result = <LocalPackage>[];
    await for (final entity in packagesDir.list()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final pkg = await _readRecord(entity);
      if (pkg != null) result.add(pkg);
    }
    return result;
  }

  Future<LocalPackage?> get(String key) async {
    final file = _recordFile(key);
    if (!await file.exists()) return null;
    return _readRecord(file);
  }

  Future<LocalPackage?> _readRecord(File file) async {
    try {
      final json = jsonDecode(await file.readAsString());
      return LocalPackage.fromJson((json as Map).cast<String, Object?>());
    } catch (_) {
      // Unlesbarer Datensatz wird ignoriert; andere Pakete bleiben nutzbar.
      return null;
    }
  }

  /// Liste der Audiodateien eines Pakets, die lokal fehlen oder falsch groß sind.
  Future<List<PackageAudio>> missingAudio(LocalPackage pkg) async {
    final missing = <PackageAudio>[];
    for (final audio in pkg.manifest.distinctAudio) {
      final file = audioFile(audio);
      if (!await file.exists() || await file.length() != audio.sizeBytes) {
        missing.add(audio);
      }
    }
    return missing;
  }

  /// Schreibt den Datensatz atomar. Nur innerhalb von [synchronized] aufrufen.
  Future<void> commitLocked(LocalPackage pkg) async {
    final target = _recordFile(pkg.key);
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(jsonEncode(pkg.toJson()), flush: true);
    await temp.rename(target.path);
  }

  Future<void> delete(String key) => synchronized(() async {
    await _deleteQuietly(_recordFile(key));
    await _collectGarbage();
  });

  /// Nur innerhalb von [synchronized] aufrufen.
  Future<void> collectGarbageLocked() => _collectGarbage();

  Future<void> _collectGarbage() async {
    final referenced = <String>{};
    for (final pkg in await loadAll()) {
      for (final audio in pkg.manifest.distinctAudio) {
        referenced.add(audio.libraryFileName);
      }
    }
    await for (final entity in audioDir.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (!referenced.contains(name)) await _deleteQuietly(entity);
    }
  }

  /// Belegter Speicher der Bibliothek in Bytes.
  Future<int> storageBytes() async {
    var total = 0;
    if (!await root.exists()) return 0;
    await for (final entity in root.list(recursive: true)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } on FileSystemException {
          // Datei verschwand zwischenzeitlich.
        }
      }
    }
    return total;
  }

  /// Bytes, die ausschließlich dieses Paket belegt (beim Löschen frei werdend).
  Future<int> exclusiveBytes(LocalPackage pkg, List<LocalPackage> all) async {
    final others = <String>{
      for (final p in all)
        if (p.key != pkg.key)
          for (final a in p.manifest.distinctAudio) a.libraryFileName,
    };
    return pkg.manifest.distinctAudio
        .where((a) => !others.contains(a.libraryFileName))
        .fold<int>(0, (sum, a) => sum + a.sizeBytes);
  }

  static Future<void> _deleteQuietly(FileSystemEntity entity) async {
    try {
      await entity.delete(recursive: true);
    } on FileSystemException {
      // Bereits entfernt.
    }
  }
}
