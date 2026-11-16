import 'dart:async';

/// Ereignisse, die eine [AudioEngine] von sich aus meldet.
sealed class AudioEngineEvent {
  const AudioEngineEvent();
}

/// Der geladene Titel ist bis zum Ende gelaufen.
class AudioCompleted extends AudioEngineEvent {
  const AudioCompleted();
}

/// Das System hat die Wiedergabe unterbrochen (Anruf, anderes Audio,
/// Kopfhörer entfernt …). Die Engine ist bereits pausiert.
class AudioInterrupted extends AudioEngineEvent {
  const AudioInterrupted(this.reason);
  final String reason;
}

/// Die Wiedergabe ist fehlgeschlagen.
class AudioFailed extends AudioEngineEvent {
  const AudioFailed(this.message);
  final String message;
}

/// Abstraktion der nativen Audiowiedergabe.
///
/// Wichtig für CHAPEL-Verhalten: Eine Engine spielt immer genau **eine**
/// Datei. Es gibt keine Warteschlange – ein automatischer Übergang zum
/// nächsten Titel ist dadurch technisch ausgeschlossen.
abstract interface class AudioEngine {
  Stream<AudioEngineEvent> get events;

  /// Medienposition (nicht um das Tempo bereinigt).
  Stream<Duration> get positionStream;
  Duration get position;

  /// Lädt eine lokale Datei und setzt das Tempo (tonhöhenerhaltend).
  /// Liefert die Mediendauer, sofern bekannt.
  Future<Duration?> load(String filePath, {required double rate});

  /// Startet/setzt fort. Kehrt sofort zurück (wartet nicht auf das Titelende).
  Future<void> play();
  Future<void> pause();

  /// Hält an und setzt auf den Anfang zurück.
  Future<void> stop();

  Future<void> dispose();
}
