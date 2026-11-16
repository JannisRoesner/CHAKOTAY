import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../core/cancel_token.dart';
import '../core/failures.dart';
import 'manifest.dart';
import 'package_repository.dart';
import 'safe_zip_reader.dart';

/// Obergrenzen gegen manipulierte Pakete.
class InstallLimits {
  const InstallLimits({
    this.maxManifestBytes = 4 * 1024 * 1024,
    this.maxAudioFileBytes = 1024 * 1024 * 1024,
    this.maxEntries = 5000,
  });

  final int maxManifestBytes;
  final int maxAudioFileBytes;
  final int maxEntries;
}

/// Prüft ein heruntergeladenes ZIP und übernimmt es atomar in die Bibliothek.
///
/// Ablauf: Container-Struktur prüfen → Manifest validieren → jede referenzierte
/// Datei auf Existenz, Größe, CRC32 und SHA-256 prüfen → geprüfte Dateien in
/// die gemeinsame Audiobibliothek verschieben → Paketdatensatz atomar
/// schreiben → nicht mehr referenzierte Dateien entfernen. Schlägt ein Schritt
/// fehl, bleibt ein vorher installierter Stand unverändert erhalten.
class PackageInstaller {
  PackageInstaller(this.repository, {this.limits = const InstallLimits()});

  final PackageRepository repository;
  final InstallLimits limits;

  final Random _random = Random.secure();

  /// Liest und validiert nur das Manifest aus einem Container.
  Future<PackageManifest> readManifest(SafeZipReader zip) async {
    final entry = zip.entries['manifest.json'];
    if (entry == null) {
      throw const AppFailure(
        FailureKind.corruptPackage,
        detail: 'manifest.json fehlt',
      );
    }
    final bytes = await zip.readBytes(entry, maxBytes: limits.maxManifestBytes);
    final String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      throw const AppFailure(
        FailureKind.corruptPackage,
        detail: 'Manifest ist kein UTF-8',
      );
    }
    return PackageManifest.parse(text);
  }

  Future<LocalPackage> install(
    File zipFile, {
    required String serverOrigin,
    int? expectedServiceId,
    String? expectedVersion,
    CancelToken? cancelToken,
    void Function(int done, int total)? onProgress,
  }) async {
    try {
      final zip = await SafeZipReader.open(
        zipFile,
        maxEntries: limits.maxEntries,
      );
      final manifest = await readManifest(zip);

      if (expectedServiceId != null &&
          manifest.service.id != expectedServiceId) {
        throw const AppFailure(
          FailureKind.corruptPackage,
          detail: 'Paket gehört zu einem anderen Gottesdienst',
        );
      }
      if (expectedVersion != null && manifest.version != expectedVersion) {
        throw const AppFailure(
          FailureKind.corruptPackage,
          detail: 'Paketversion weicht vom Download ab',
        );
      }

      final audio = manifest.distinctAudio;
      final allowed = {'manifest.json', for (final a in audio) a.file};
      for (final name in zip.entries.keys) {
        if (allowed.contains(name)) continue;
        if (name == 'audio/') continue;
        throw AppFailure(
          FailureKind.corruptPackage,
          detail: 'Unerwartete Datei im Paket: $name',
        );
      }

      var total = 0;
      for (final a in audio) {
        final entry = zip.entries[a.file];
        if (entry == null) {
          throw AppFailure(
            FailureKind.corruptPackage,
            detail: 'Audiodatei fehlt im Paket: ${a.file}',
          );
        }
        if (entry.uncompressedSize != a.sizeBytes) {
          throw AppFailure(
            FailureKind.corruptPackage,
            detail: 'Größe von ${a.file} weicht vom Manifest ab',
          );
        }
        if (a.sizeBytes > limits.maxAudioFileBytes) {
          throw AppFailure(
            FailureKind.corruptPackage,
            detail: '${a.file} überschreitet die zulässige Größe',
          );
        }
        total += a.sizeBytes;
      }

      return await repository.synchronized(() async {
        try {
          return await _installLocked(
            manifest,
            audio,
            zip,
            total,
            serverOrigin,
            cancelToken,
            onProgress,
          );
        } catch (_) {
          // Bereits übernommene, aber nun unreferenzierte Dateien entfernen.
          await repository.collectGarbageLocked();
          rethrow;
        }
      });
    } catch (e) {
      throw AppFailure.from(e);
    }
  }

  Future<LocalPackage> _installLocked(
    PackageManifest manifest,
    List<PackageAudio> audio,
    SafeZipReader zip,
    int total,
    String serverOrigin,
    CancelToken? cancelToken,
    void Function(int done, int total)? onProgress,
  ) async {
    await repository.init();
    var done = 0;
    onProgress?.call(0, total);
    for (final a in audio) {
      cancelToken?.throwIfCancelled();
      final target = repository.audioFile(a);
      if (await target.exists() && await target.length() == a.sizeBytes) {
        // Bereits durch ein anderes Paket geprüft vorhanden (Deduplizierung).
        done += a.sizeBytes;
        onProgress?.call(done, total);
        continue;
      }
      final part = File(
        '${repository.tempDir.path}/${a.sha256}-${_random.nextInt(1 << 32)}.part',
      );
      try {
        final result = await zip.extractTo(
          zip.entries[a.file]!,
          part,
          isCancelled: () => cancelToken?.isCancelled ?? false,
          onProgress: (n) {
            done += n;
            onProgress?.call(done, total);
          },
        );
        if (result.sha256Hex != a.sha256) {
          throw AppFailure(
            FailureKind.checksumMismatch,
            detail: 'SHA-256 von ${a.file} stimmt nicht',
          );
        }
        await part.rename(target.path);
      } finally {
        if (await part.exists()) await part.delete();
      }
    }
    cancelToken?.throwIfCancelled();

    final pkg = LocalPackage(
      serverOrigin: serverOrigin,
      manifest: manifest,
      installedAt: DateTime.now().toUtc(),
    );
    await repository.commitLocked(pkg);
    await repository.collectGarbageLocked();
    return pkg;
  }
}
