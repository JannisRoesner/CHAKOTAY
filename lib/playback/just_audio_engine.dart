import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_engine.dart';

/// [AudioEngine] auf Basis von just_audio (Android: ExoPlayer/Media3,
/// iOS: AVPlayer) und audio_session (AVAudioSession / AudioFocus).
///
/// * Tempo: `setSpeed` – ExoPlayer hält die Tonhöhe über
///   `PlaybackParameters(speed, pitch: 1)`, AVPlayer über den
///   Time-Domain-Pitch-Algorithmus.
/// * Unterbrechungen werden selbst behandelt (`handleInterruptions: false`):
///   Beginn → Pause; Ende → **kein** automatisches Fortsetzen. Im Gottesdienst
///   darf nach einem Anruf o. Ä. nie unerwartet Musik einsetzen.
/// * Kopfhörer/Bluetooth getrennt („becoming noisy“) → Pause.
class JustAudioEngine implements AudioEngine {
  JustAudioEngine() : _player = AudioPlayer(handleInterruptions: false) {
    _subscriptions.add(
      _player.processingStateStream.listen((state) {
        if (state == ProcessingState.completed) {
          _events.add(const AudioCompleted());
        }
      }),
    );
    _subscriptions.add(
      _player.playbackEventStream.listen(
        (_) {},
        onError: (Object e, StackTrace _) {
          _events.add(AudioFailed('$e'));
        },
      ),
    );
  }

  final AudioPlayer _player;
  final _events = StreamController<AudioEngineEvent>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  bool _sessionConfigured = false;
  bool _ducked = false;

  Future<void> _configureSession() async {
    if (_sessionConfigured) return;
    _sessionConfigured = true;
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _subscriptions.add(
      session.interruptionEventStream.listen((event) async {
        if (event.begin) {
          if (event.type == AudioInterruptionType.duck) {
            if (_player.playing) {
              _ducked = true;
              await _player.setVolume(0.3);
            }
            return;
          }
          if (_player.playing) {
            await _player.pause();
            _events.add(
              const AudioInterrupted('Unterbrechung durch das System'),
            );
          }
        } else if (_ducked) {
          _ducked = false;
          await _player.setVolume(1);
        }
        // Ende einer Pause-Unterbrechung: bewusst kein Fortsetzen.
      }),
    );
    _subscriptions.add(
      session.becomingNoisyEventStream.listen((_) async {
        if (_player.playing) {
          await _player.pause();
          _events.add(const AudioInterrupted('Audioausgang getrennt'));
        }
      }),
    );
  }

  @override
  Stream<AudioEngineEvent> get events => _events.stream;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Duration get position => _player.position;

  @override
  Future<Duration?> load(String filePath, {required double rate}) async {
    await _configureSession();
    final duration = await _player.setFilePath(filePath, preload: true);
    await _player.setSpeed(rate);
    await _player.setVolume(1);
    return duration;
  }

  @override
  Future<void> play() async {
    await _configureSession();
    // play() kehrt erst bei Pause/Ende zurück – daher nicht abwarten.
    unawaited(
      _player.play().catchError((Object e) {
        _events.add(AudioFailed('$e'));
      }),
    );
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.pause();
    await _player.seek(Duration.zero);
  }

  @override
  Future<void> dispose() async {
    for (final s in _subscriptions) {
      await s.cancel();
    }
    await _player.dispose();
    await _events.close();
  }
}
