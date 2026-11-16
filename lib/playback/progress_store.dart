import 'dart:convert';
import 'dart:io';

/// Gespeicherter Wiedergabe-Fortschritt eines Pakets.
///
/// Entspricht `PlaybackProgressSnapshot` aus CHAPEL
/// (`app/composables/usePlaybackProgress.ts`): aktueller Schritt, bereits
/// gespielte Schritte, Zeitstempel und ein Fingerabdruck des Ablaufs. Als
/// Fingerabdruck dient hier die Paket-`version` – sie ändert sich laut CHAPEL
/// genau dann, wenn sich der abspielbare Ablauf ändert.
class PlaybackProgress {
  const PlaybackProgress({
    required this.currentIndex,
    required this.playedIndices,
    required this.savedAt,
    required this.version,
  });

  final int currentIndex;
  final List<int> playedIndices;
  final DateTime savedAt;
  final String version;

  Map<String, Object?> toJson() => {
    'currentIndex': currentIndex,
    'playedIndices': playedIndices,
    'savedAt': savedAt.millisecondsSinceEpoch,
    'version': version,
  };

  static PlaybackProgress? tryParse(Object? json) {
    if (json is! Map) return null;
    final index = json['currentIndex'];
    final played = json['playedIndices'];
    final savedAt = json['savedAt'];
    final version = json['version'];
    if (index is! int ||
        played is! List ||
        savedAt is! int ||
        version is! String) {
      return null;
    }
    return PlaybackProgress(
      currentIndex: index,
      playedIndices: played.whereType<int>().toList(),
      savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt),
      version: version,
    );
  }
}

/// Persistiert [PlaybackProgress] je Paket in einer JSON-Datei.
///
/// Verhalten wie CHAPEL: Ein Stand verfällt nach 24 Stunden und wird
/// verworfen, sobald sich die Paketversion geändert hat.
class ProgressStore {
  ProgressStore(this.file, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  static const Duration ttl = Duration(hours: 24);

  final File file;
  final DateTime Function() _clock;
  Map<String, Object?>? _cache;

  Future<Map<String, Object?>> _all() async {
    if (_cache != null) return _cache!;
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) return _cache = decoded.cast<String, Object?>();
      }
    } catch (_) {
      // Beschädigte Datei → neu beginnen.
    }
    return _cache = <String, Object?>{};
  }

  Future<void> _writes = Future.value();

  /// Wartet, bis alle ausstehenden Schreibvorgänge abgeschlossen sind.
  Future<void> get idle => _writes;

  /// Änderungen nacheinander ausführen (kein Rennen beim `rename`).
  Future<void> _enqueue(Future<void> Function() change) {
    final next = _writes.then((_) => change()).catchError((Object _) {
      // Fortschritt ist eine Komfortfunktion – Schreibfehler blockieren nichts.
    });
    _writes = next;
    return next;
  }

  Future<void> _write() async {
    final temp = File('${file.path}.tmp');
    await file.parent.create(recursive: true);
    await temp.writeAsString(jsonEncode(_cache ?? {}), flush: true);
    await temp.rename(file.path);
  }

  /// Lädt den Fortschritt; verwirft ihn bei Versionswechsel oder Ablauf.
  Future<PlaybackProgress?> load(
    String packageKey, {
    required String version,
    required int stepCount,
  }) async {
    final all = await _all();
    final snapshot = PlaybackProgress.tryParse(all[packageKey]);
    if (snapshot == null) return null;
    final expired = _clock().difference(snapshot.savedAt) > ttl;
    if (expired || snapshot.version != version) {
      await clear(packageKey);
      return null;
    }
    final last = stepCount - 1;
    return PlaybackProgress(
      currentIndex: snapshot.currentIndex.clamp(0, last < 0 ? 0 : last),
      playedIndices: snapshot.playedIndices
          .where((i) => i >= 0 && i < stepCount)
          .toList(),
      savedAt: snapshot.savedAt,
      version: snapshot.version,
    );
  }

  Future<void> save(
    String packageKey, {
    required String version,
    required int currentIndex,
    required List<int> playedIndices,
  }) {
    final snapshot = PlaybackProgress(
      currentIndex: currentIndex,
      playedIndices: List.of(playedIndices),
      savedAt: _clock(),
      version: version,
    ).toJson();
    return _enqueue(() async {
      (await _all())[packageKey] = snapshot;
      await _write();
    });
  }

  Future<void> clear(String packageKey) => _enqueue(() async {
    if ((await _all()).remove(packageKey) != null) await _write();
  });
}
