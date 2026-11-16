/// Datenmodell des CHAPEL-Offline-Pakets (`formatVersion: 1`).
///
/// Entspricht `PackageManifestDto`, `PackageStepDto` und `PackageAudioDto` aus
/// `CHAPEL/shared/types/chapel.ts` bzw. der Erzeugung in
/// `CHAPEL/server/utils/servicePackage.ts`. Das Parsen ist bewusst strikt:
/// ein Manifest, das hier nicht validiert, wird niemals installiert.
library;

import 'dart:convert';

/// Höchste Paketformat-Version, die dieser Client versteht.
const int supportedPackageFormatVersion = 1;

/// Grenzen für Tempo-Faktoren (CHAPEL: `PLAYBACK_RATE_MIN/MAX`).
const double minPlaybackRate = 0.5;
const double maxPlaybackRate = 1.5;

/// Erlaubte Audio-Endungen (CHAPEL: `ALLOWED_AUDIO_EXTENSIONS`).
const Set<String> allowedAudioExtensions = {'.mp3', '.wav', '.flac', '.ogg'};

final RegExp _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// Fehler beim Lesen oder Prüfen eines Manifests.
class ManifestFormatException implements Exception {
  ManifestFormatException(this.message);
  final String message;
  @override
  String toString() => 'ManifestFormatException: $message';
}

/// Paket mit einer neueren, unbekannten `formatVersion`.
class UnsupportedPackageVersionException implements Exception {
  UnsupportedPackageVersionException(this.formatVersion);
  final Object? formatVersion;
  @override
  String toString() =>
      'UnsupportedPackageVersionException: formatVersion=$formatVersion';
}

enum StepKind {
  liturgy('liturgy'),
  songSlot('songSlot');

  const StepKind(this.wire);
  final String wire;

  static StepKind parse(Object? value) {
    for (final kind in values) {
      if (kind.wire == value) return kind;
    }
    throw ManifestFormatException('Unbekannte Schrittart: $value');
  }
}

class PackageAudio {
  const PackageAudio({
    required this.file,
    required this.sha256,
    required this.mimeType,
    required this.sizeBytes,
    required this.url,
  });

  /// Pfad innerhalb des ZIP-Containers, z. B. `audio/<sha256>.mp3`.
  final String file;

  /// SHA-256 (hex, klein) des Dateiinhalts.
  final String sha256;
  final String mimeType;
  final int sizeBytes;

  /// Relativer Einzel-Download-Pfad (`/api/tracks/:id/stream`).
  final String url;

  /// Dateiendung inkl. Punkt, klein geschrieben (z. B. `.mp3`).
  String get extension {
    final dot = file.lastIndexOf('.');
    return dot < 0 ? '' : file.substring(dot).toLowerCase();
  }

  /// Name der Datei in der lokalen, deduplizierten Audiobibliothek.
  String get libraryFileName => '$sha256$extension';

  factory PackageAudio.fromJson(Map<String, Object?> json) {
    final file = _string(json, 'file');
    final sha = _string(json, 'sha256').toLowerCase();
    if (!_sha256Pattern.hasMatch(sha)) {
      throw ManifestFormatException('Ungültige Prüfsumme: $sha');
    }
    if (!isSafeAudioEntryName(file)) {
      throw ManifestFormatException('Unzulässiger Audiopfad: $file');
    }
    final size = _int(json, 'sizeBytes');
    if (size < 0) throw ManifestFormatException('Negative Dateigröße');
    return PackageAudio(
      file: file,
      sha256: sha,
      mimeType: _string(json, 'mimeType'),
      sizeBytes: size,
      url: json['url'] is String ? json['url']! as String : '',
    );
  }

  Map<String, Object?> toJson() => {
    'file': file,
    'sha256': sha256,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'url': url,
  };
}

class PackageStep {
  const PackageStep({
    required this.position,
    required this.kind,
    required this.label,
    required this.title,
    required this.composer,
    required this.durationMs,
    required this.playbackRate,
    required this.audio,
  });

  final int position;
  final StepKind kind;
  final String label;
  final String? title;
  final String? composer;

  /// Dauer bei angewendetem [playbackRate] (laut CHAPEL bereits umgerechnet).
  final int? durationMs;

  /// Tempo-Faktor, tonhöhenerhaltend anzuwenden (1 = Original).
  final double playbackRate;

  /// `null` → leerer Schritt (z. B. Lied-Slot ohne Auswahl).
  final PackageAudio? audio;

  bool get isPlayable => audio != null;

  factory PackageStep.fromJson(Map<String, Object?> json) {
    final rateRaw = json['playbackRate'];
    double rate = 1;
    if (rateRaw is num && rateRaw.isFinite) {
      rate = rateRaw.toDouble().clamp(minPlaybackRate, maxPlaybackRate);
    }
    final audioRaw = json['audio'];
    final durationRaw = json['durationMs'];
    return PackageStep(
      position: _int(json, 'position'),
      kind: StepKind.parse(json['kind']),
      label: _string(json, 'label'),
      title: _optString(json, 'title'),
      composer: _optString(json, 'composer'),
      durationMs: durationRaw is num ? durationRaw.round() : null,
      playbackRate: rate,
      audio: audioRaw == null
          ? null
          : PackageAudio.fromJson(_map(audioRaw, 'audio')),
    );
  }

  Map<String, Object?> toJson() => {
    'position': position,
    'kind': kind.wire,
    'label': label,
    'title': title,
    'composer': composer,
    'durationMs': durationMs,
    'playbackRate': playbackRate,
    'audio': audio?.toJson(),
  };
}

class ServiceInfo {
  const ServiceInfo({
    required this.id,
    required this.name,
    required this.serviceDate,
    required this.notes,
    required this.updatedAt,
  });

  final int id;
  final String name;
  final DateTime serviceDate;
  final String? notes;
  final DateTime? updatedAt;

  factory ServiceInfo.fromJson(Map<String, Object?> json) => ServiceInfo(
    id: _int(json, 'id'),
    name: _string(json, 'name'),
    serviceDate: _date(json, 'serviceDate'),
    notes: _optString(json, 'notes'),
    updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'serviceDate': serviceDate.toUtc().toIso8601String(),
    'notes': notes,
    'updatedAt': updatedAt?.toUtc().toIso8601String(),
  };
}

class PackageManifest {
  const PackageManifest({
    required this.formatVersion,
    required this.version,
    required this.generatedAt,
    required this.service,
    required this.steps,
    required this.totalAudioBytes,
  });

  final int formatVersion;

  /// Inhalts-Hash; ändert sich genau dann, wenn sich der abspielbare Inhalt ändert.
  final String version;
  final DateTime? generatedAt;
  final ServiceInfo service;
  final List<PackageStep> steps;
  final int totalAudioBytes;

  /// Alle referenzierten Audiodateien, dedupliziert nach Containerpfad.
  List<PackageAudio> get distinctAudio {
    final byFile = <String, PackageAudio>{};
    for (final step in steps) {
      final audio = step.audio;
      if (audio != null) byFile.putIfAbsent(audio.file, () => audio);
    }
    return byFile.values.toList(growable: false);
  }

  int get playableStepCount => steps.where((s) => s.isPlayable).length;

  /// Parst und validiert ein Manifest. Wirft [UnsupportedPackageVersionException]
  /// bei unbekannter Formatversion, sonst [ManifestFormatException].
  factory PackageManifest.fromJson(Object? decoded) {
    final json = _map(decoded, 'manifest');
    final formatVersion = json['formatVersion'];
    if (formatVersion is! int) {
      throw ManifestFormatException('formatVersion fehlt');
    }
    if (formatVersion != supportedPackageFormatVersion) {
      throw UnsupportedPackageVersionException(formatVersion);
    }
    final version = _string(json, 'version');
    if (version.isEmpty) throw ManifestFormatException('version fehlt');

    final stepsRaw = json['steps'];
    if (stepsRaw is! List) throw ManifestFormatException('steps fehlt');
    final steps = [
      for (final s in stepsRaw) PackageStep.fromJson(_map(s, 'step')),
    ]..sort((a, b) => a.position.compareTo(b.position));

    // Gleicher Containerpfad muss immer dieselbe Datei beschreiben.
    final byFile = <String, PackageAudio>{};
    for (final step in steps) {
      final audio = step.audio;
      if (audio == null) continue;
      final existing = byFile[audio.file];
      if (existing != null &&
          (existing.sha256 != audio.sha256 ||
              existing.sizeBytes != audio.sizeBytes)) {
        throw ManifestFormatException(
          'Widersprüchliche Angaben für ${audio.file}',
        );
      }
      byFile[audio.file] = audio;
    }

    return PackageManifest(
      formatVersion: formatVersion,
      version: version,
      generatedAt: DateTime.tryParse(json['generatedAt']?.toString() ?? ''),
      service: ServiceInfo.fromJson(_map(json['service'], 'service')),
      steps: List.unmodifiable(steps),
      totalAudioBytes: _int(json, 'totalAudioBytes'),
    );
  }

  static PackageManifest parse(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (e) {
      throw ManifestFormatException('Kein gültiges JSON: ${e.message}');
    }
    return PackageManifest.fromJson(decoded);
  }

  Map<String, Object?> toJson() => {
    'formatVersion': formatVersion,
    'version': version,
    'generatedAt': generatedAt?.toUtc().toIso8601String(),
    'service': service.toJson(),
    'steps': [for (final s in steps) s.toJson()],
    'totalAudioBytes': totalAudioBytes,
  };
}

/// Erlaubt nur `audio/<name>` mit harmlosem Dateinamen und bekannter Endung.
bool isSafeAudioEntryName(String name) {
  if (!name.startsWith('audio/')) return false;
  final base = name.substring('audio/'.length);
  if (base.isEmpty || base.length > 200) return false;
  if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*$').hasMatch(base)) return false;
  if (base.contains('..')) return false;
  final dot = base.lastIndexOf('.');
  if (dot < 0) return false;
  return allowedAudioExtensions.contains(base.substring(dot).toLowerCase());
}

Map<String, Object?> _map(Object? value, String field) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.cast<String, Object?>();
  throw ManifestFormatException('$field ist kein Objekt');
}

String _string(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v is String) return v;
  throw ManifestFormatException('$key fehlt oder ist kein Text');
}

String? _optString(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v == null) return null;
  if (v is String) return v;
  throw ManifestFormatException('$key ist kein Text');
}

int _int(Map<String, Object?> json, String key) {
  final v = json[key];
  if (v is int) return v;
  if (v is double && v == v.roundToDouble()) return v.toInt();
  throw ManifestFormatException('$key fehlt oder ist keine Ganzzahl');
}

DateTime _date(Map<String, Object?> json, String key) {
  final parsed = DateTime.tryParse(json[key]?.toString() ?? '');
  if (parsed == null) throw ManifestFormatException('$key ist kein Datum');
  return parsed;
}
