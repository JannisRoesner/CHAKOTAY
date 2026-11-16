import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/failures.dart';
import '../packages/manifest.dart';
import '../packages/package_repository.dart';
import 'audio_engine.dart';
import 'progress_store.dart';

/// Zustände des Players – angelehnt an `PlayerState` aus CHAPEL
/// (`idle | playing | paused | pausedAfterTrack`).
enum PlaybackStatus {
  /// Bereit; nichts geladen bzw. nach Stopp oder Titelende.
  idle,

  /// Datei wird vorbereitet.
  loading,
  playing,
  paused,

  /// Der letzte abspielbare Titel ist beendet (`pausedAfterTrack`).
  finishedLast,
}

/// Steuerlogik der Gottesdienst-Wiedergabe.
///
/// Bedienkonzept identisch zu CHAPEL (`useChapelPlayer.ts`):
/// * Play spielt genau den ausgewählten Schritt.
/// * Am Titelende stoppt die Wiedergabe; die Auswahl springt auf den nächsten
///   Schritt, **ohne** ihn zu starten.
/// * „Nächster“ wechselt zum nächsten Schritt und startet ihn (bewusste Aktion).
/// * Auswahl eines Schritts stoppt und wählt nur aus.
///
/// Erweiterung für leere Schritte (`audio: null`): sie bleiben sichtbar und
/// auswählbar, werden beim Weiterschalten nach Titelende und bei
/// „Nächster“/„Vorheriger“ jedoch übersprungen.
class PlayerController extends ChangeNotifier {
  PlayerController({
    required this.package,
    required AudioEngine engine,
    required File Function(PackageAudio audio) resolveAudio,
    ProgressStore? progressStore,
  }) : _engine = engine,
       _resolveAudio = resolveAudio,
       _progressStore = progressStore;

  final LocalPackage package;
  final AudioEngine _engine;
  final File Function(PackageAudio audio) _resolveAudio;
  final ProgressStore? _progressStore;

  final List<StreamSubscription<Object?>> _subscriptions = [];

  /// Abgespielte Zeit des aktuellen Titels (in Echtzeit, d. h. bereits um
  /// das Tempo bereinigt).
  final ValueNotifier<Duration> position = ValueNotifier(Duration.zero);

  List<PackageStep> get steps => package.manifest.steps;

  int _currentIndex = 0;
  int get currentIndex => _currentIndex;
  PackageStep? get currentStep =>
      steps.isEmpty ? null : steps[_currentIndex.clamp(0, steps.length - 1)];

  PlaybackStatus _status = PlaybackStatus.idle;
  PlaybackStatus get status => _status;
  bool get isPlaying => _status == PlaybackStatus.playing;

  final Set<int> _played = {};
  Set<int> get playedIndices => Set.unmodifiable(_played);

  int? _lastFinishedIndex;

  /// Index des zuletzt vollständig gespielten Schritts.
  int? get lastFinishedIndex => _lastFinishedIndex;

  /// `true` direkt nach einem Titelende, bis der Benutzer wieder handelt.
  bool _justFinished = false;
  bool get justFinished => _justFinished;

  AppFailure? _failure;
  AppFailure? get failure => _failure;

  String? _notice;

  /// Hinweis nach einer Systemunterbrechung (Anruf, Kopfhörer …).
  String? get notice => _notice;

  int? _loadedIndex;
  Duration? _mediaDuration;
  int _operation = 0;
  bool _disposed = false;

  /// Gesamtdauer des aktuellen Schritts in Echtzeit.
  ///
  /// Wie im CHAPEL-Player (`NowPlayingBar.vue`) hat die tatsächliche
  /// Mediendauer Vorrang; `durationMs` aus dem Manifest dient als Anzeige,
  /// solange die Datei noch nicht geladen ist.
  Duration? get currentDuration {
    final step = currentStep;
    if (step == null || !step.isPlayable) return null;
    final media = _loadedIndex == _currentIndex ? _mediaDuration : null;
    if (media != null && media > Duration.zero) {
      return media * (1 / step.playbackRate);
    }
    if (step.durationMs != null) {
      return Duration(milliseconds: step.durationMs!);
    }
    return null;
  }

  bool get canPlay =>
      (currentStep?.isPlayable ?? false) && _status != PlaybackStatus.loading;
  bool get hasNext => nextPlayableIndex(_currentIndex) != null;
  bool get hasPrevious => previousPlayableIndex(_currentIndex) != null;

  int? nextPlayableIndex(int from) {
    for (var i = from + 1; i < steps.length; i++) {
      if (steps[i].isPlayable) return i;
    }
    return null;
  }

  int? previousPlayableIndex(int from) {
    for (var i = from - 1; i >= 0; i--) {
      if (steps[i].isPlayable) return i;
    }
    return null;
  }

  /// Stellt den gespeicherten Fortschritt wieder her und verbindet die Engine.
  Future<void> init() async {
    _subscriptions
      ..add(_engine.events.listen(_onEngineEvent))
      ..add(_engine.positionStream.listen(_onPosition));

    final saved = await _progressStore?.load(
      package.key,
      version: package.version,
      stepCount: steps.length,
    );
    if (saved != null) {
      _currentIndex = saved.currentIndex;
      _played.addAll(saved.playedIndices);
    } else {
      _currentIndex = steps.indexWhere((s) => s.isPlayable);
      if (_currentIndex < 0) _currentIndex = 0;
    }
    _notify();
  }

  // ------------------------------------------------------------ Aktionen

  Future<void> togglePlay() =>
      _status == PlaybackStatus.playing ? pause() : play();

  /// Spielt den aktuell ausgewählten Schritt (bzw. setzt ihn fort).
  Future<void> play() async {
    final step = currentStep;
    if (step == null || step.audio == null) return;
    if (_status == PlaybackStatus.loading ||
        _status == PlaybackStatus.playing) {
      return;
    }
    _clearTransient();
    final op = ++_operation;

    if (_status == PlaybackStatus.paused && _loadedIndex == _currentIndex) {
      _status = PlaybackStatus.playing;
      _notify();
      await _engine.play();
      return;
    }

    final file = _resolveAudio(step.audio!);
    if (!await file.exists()) {
      _failure = const AppFailure(FailureKind.audioMissing);
      _status = PlaybackStatus.idle;
      _notify();
      return;
    }

    _status = PlaybackStatus.loading;
    position.value = Duration.zero;
    _notify();
    try {
      final duration = await _engine.load(file.path, rate: step.playbackRate);
      if (op != _operation || _disposed) return; // inzwischen anders gewählt
      _mediaDuration = duration;
      _loadedIndex = _currentIndex;
      _status = PlaybackStatus.playing;
      _notify();
      await _engine.play();
    } catch (e) {
      if (op != _operation || _disposed) return;
      _failure = AppFailure(FailureKind.playbackFailed, detail: '$e');
      _loadedIndex = null;
      _status = PlaybackStatus.idle;
      _notify();
    }
  }

  Future<void> pause() async {
    if (_status != PlaybackStatus.playing) return;
    _operation++;
    _status = PlaybackStatus.paused;
    _notify();
    await _engine.pause();
  }

  /// Stoppt und setzt den aktuellen Titel auf den Anfang zurück.
  Future<void> stop() async {
    _clearTransient();
    await _reset();
    _notify();
  }

  /// Wechselt zum nächsten abspielbaren Schritt **und startet ihn**
  /// (CHAPEL: „Nächster“).
  Future<void> next() async {
    final target = nextPlayableIndex(_currentIndex);
    if (target == null) return;
    _clearTransient();
    await _reset();
    _currentIndex = target;
    _persist();
    _notify();
    await play();
  }

  /// Wählt den vorherigen abspielbaren Schritt aus, ohne ihn zu starten.
  Future<void> previous() async {
    final target = previousPlayableIndex(_currentIndex);
    if (target == null) return;
    await select(target);
  }

  /// Wählt einen Schritt aus. Laufende Wiedergabe wird gestoppt.
  Future<void> select(int index) async {
    if (index < 0 || index >= steps.length) return;
    _clearTransient();
    await _reset();
    _currentIndex = index;
    _persist();
    _notify();
  }

  // ------------------------------------------------------------- Intern

  Future<void> _reset() async {
    _operation++;
    final wasLoaded = _loadedIndex != null || _status != PlaybackStatus.idle;
    _status = PlaybackStatus.idle;
    _loadedIndex = null;
    _mediaDuration = null;
    position.value = Duration.zero;
    if (wasLoaded) await _engine.stop();
  }

  void _clearTransient() {
    _justFinished = false;
    _failure = null;
    _notice = null;
  }

  void _onEngineEvent(AudioEngineEvent event) {
    switch (event) {
      case AudioCompleted():
        unawaited(_onCompleted());
      case AudioInterrupted(:final reason):
        if (_status == PlaybackStatus.playing) {
          _operation++;
          _status = PlaybackStatus.paused;
          _notice = reason;
          _notify();
        }
      case AudioFailed(:final message):
        if (_status == PlaybackStatus.playing ||
            _status == PlaybackStatus.loading) {
          _failure = AppFailure(FailureKind.playbackFailed, detail: message);
          unawaited(_reset().then((_) => _notify()));
        }
    }
  }

  /// Titelende: stoppen, als gespielt markieren, Auswahl weiterschieben –
  /// aber **nichts** starten.
  Future<void> _onCompleted() async {
    if (_status != PlaybackStatus.playing || _loadedIndex != _currentIndex) {
      return;
    }
    final finished = _currentIndex;
    _lastFinishedIndex = finished;
    _played.add(finished);
    await _reset();
    final next = nextPlayableIndex(finished);
    if (next != null) {
      _currentIndex = next;
      _status = PlaybackStatus.idle;
    } else {
      _status = PlaybackStatus.finishedLast;
    }
    _justFinished = true;
    _persist();
    _notify();
  }

  void _onPosition(Duration media) {
    if (_loadedIndex != _currentIndex) return;
    if (_status != PlaybackStatus.playing && _status != PlaybackStatus.paused) {
      return;
    }
    final rate = currentStep?.playbackRate ?? 1;
    position.value = media * (1 / rate);
  }

  /// Sichert den Fortschritt (z. B. beim Wechsel in den Hintergrund).
  /// Sichert den Fortschritt (z. B. beim Wechsel in den Hintergrund).
  Future<void> saveProgress() => _save();

  void _persist() => unawaited(_save());

  Future<void> _save() async {
    final store = _progressStore;
    if (store == null) return;
    await store.save(
      package.key,
      version: package.version,
      currentIndex: _currentIndex,
      playedIndices: _played.toList()..sort(),
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Speichert den Fortschritt und gibt die Engine frei.
  Future<void> close() async {
    await _save();
    _disposed = true;
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _engine.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    position.dispose();
    super.dispose();
  }
}
