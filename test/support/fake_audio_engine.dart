import 'dart:async';

import 'package:chakotay/playback/audio_engine.dart';

/// Steuerbare [AudioEngine] für Tests – protokolliert alle Aufrufe.
class FakeAudioEngine implements AudioEngine {
  final _events = StreamController<AudioEngineEvent>.broadcast(sync: true);
  final _positions = StreamController<Duration>.broadcast(sync: true);

  final List<String> calls = [];
  String? loadedPath;
  double? rate;
  bool playing = false;
  bool disposed = false;
  Duration mediaDuration = const Duration(seconds: 60);
  Object? loadError;

  int get playCount => calls.where((c) => c == 'play').length;
  List<String> get loads =>
      calls.where((c) => c.startsWith('load ')).toList(growable: false);

  @override
  Stream<AudioEngineEvent> get events => _events.stream;

  @override
  Stream<Duration> get positionStream => _positions.stream;

  Duration _position = Duration.zero;
  @override
  Duration get position => _position;

  @override
  Future<Duration?> load(String filePath, {required double rate}) async {
    calls.add('load $filePath @$rate');
    if (loadError != null) throw loadError!;
    loadedPath = filePath;
    this.rate = rate;
    _position = Duration.zero;
    return mediaDuration;
  }

  @override
  Future<void> play() async {
    calls.add('play');
    playing = true;
  }

  @override
  Future<void> pause() async {
    calls.add('pause');
    playing = false;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    playing = false;
    _position = Duration.zero;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _events.close();
    await _positions.close();
  }

  /// Simuliert Fortschritt (Medienzeit).
  void emitPosition(Duration media) {
    _position = media;
    _positions.add(media);
  }

  /// Simuliert das natürliche Titelende.
  void complete() {
    playing = false;
    _events.add(const AudioCompleted());
  }

  void interrupt([String reason = 'Anruf']) {
    playing = false;
    _events.add(AudioInterrupted(reason));
  }

  void fail(String message) {
    playing = false;
    _events.add(AudioFailed(message));
  }
}
