import 'dart:async';
import 'dart:io';

import '../packages/manifest.dart';
import '../packages/safe_zip_reader.dart';

/// Fachliche Fehlerarten. Jede Art hat eine verständliche, handlungsorientierte
/// Meldung (siehe [AppFailure.message]); technische Details landen nur in
/// [AppFailure.detail] und werden nie mit Zugangsdaten angereichert.
enum FailureKind {
  offline,
  serverUnreachable,
  invalidServerAddress,
  insecureConnection,
  tlsError,
  invalidCredentials,
  sessionExpired,
  passwordChangeRequired,
  notFound,
  serverError,
  invalidResponse,
  downloadInterrupted,
  insufficientStorage,
  corruptPackage,
  checksumMismatch,
  unsupportedPackageVersion,
  audioMissing,
  playbackFailed,
  cancelled,
  unknown,
}

class AppFailure implements Exception {
  const AppFailure(this.kind, {this.detail, this.statusCode});

  final FailureKind kind;
  final String? detail;
  final int? statusCode;

  String get title => switch (kind) {
    FailureKind.offline => 'Keine Internetverbindung',
    FailureKind.serverUnreachable => 'Server nicht erreichbar',
    FailureKind.invalidServerAddress => 'Ungültige Serveradresse',
    FailureKind.insecureConnection => 'Unverschlüsselte Verbindung',
    FailureKind.tlsError => 'Sichere Verbindung fehlgeschlagen',
    FailureKind.invalidCredentials => 'Anmeldung fehlgeschlagen',
    FailureKind.sessionExpired => 'Sitzung abgelaufen',
    FailureKind.passwordChangeRequired => 'Passwort ändern erforderlich',
    FailureKind.notFound => 'Nicht gefunden',
    FailureKind.serverError => 'Serverfehler',
    FailureKind.invalidResponse => 'Unerwartete Serverantwort',
    FailureKind.downloadInterrupted => 'Download unterbrochen',
    FailureKind.insufficientStorage => 'Nicht genug Speicherplatz',
    FailureKind.corruptPackage => 'Paket beschädigt',
    FailureKind.checksumMismatch => 'Prüfsumme stimmt nicht',
    FailureKind.unsupportedPackageVersion => 'Paketformat nicht unterstützt',
    FailureKind.audioMissing => 'Audiodatei fehlt',
    FailureKind.playbackFailed => 'Wiedergabe fehlgeschlagen',
    FailureKind.cancelled => 'Abgebrochen',
    FailureKind.unknown => 'Unerwarteter Fehler',
  };

  String get message => switch (kind) {
    FailureKind.offline =>
      'Das Gerät ist offline. Heruntergeladene Gottesdienste bleiben abspielbar.',
    FailureKind.serverUnreachable =>
      'Der CHAPEL-Server antwortet nicht. Bitte Adresse und Netzwerk prüfen.',
    FailureKind.invalidServerAddress =>
      'Bitte eine Adresse wie „chapel.gemeinde.de“ oder „https://chapel.gemeinde.de“ eingeben.',
    FailureKind.insecureConnection =>
      'Die Adresse verwendet kein HTTPS. Zugangsdaten würden unverschlüsselt übertragen.',
    FailureKind.tlsError =>
      'Das Zertifikat des Servers ist ungültig oder nicht vertrauenswürdig.',
    FailureKind.invalidCredentials =>
      'E-Mail-Adresse oder Passwort sind falsch.',
    FailureKind.sessionExpired =>
      'Bitte erneut anmelden. Heruntergeladene Gottesdienste bleiben abspielbar.',
    FailureKind.passwordChangeRequired =>
      'Ihr Passwort muss zuerst in der CHAPEL-Weboberfläche geändert werden.',
    FailureKind.notFound =>
      'Der Gottesdienst existiert auf dem Server nicht mehr.',
    FailureKind.serverError =>
      'Der Server konnte die Anfrage nicht verarbeiten. Bitte später erneut versuchen.',
    FailureKind.invalidResponse =>
      'Ist die Adresse wirklich ein CHAPEL-Server?',
    FailureKind.downloadInterrupted =>
      'Die Verbindung brach ab. Ein bereits vorhandener Stand bleibt erhalten.',
    FailureKind.insufficientStorage =>
      'Bitte Speicher freigeben und den Download erneut starten.',
    FailureKind.corruptPackage =>
      'Das heruntergeladene Paket ist fehlerhaft und wurde verworfen. Bitte erneut laden.',
    FailureKind.checksumMismatch =>
      'Eine Audiodatei wurde fehlerhaft übertragen und verworfen. Bitte erneut laden.',
    FailureKind.unsupportedPackageVersion =>
      'Dieses Paket ist neuer als die App. Bitte CHAKOTAY aktualisieren.',
    FailureKind.audioMissing =>
      'Die Audiodatei ist nicht auf dem Gerät. Bitte den Gottesdienst erneut laden.',
    FailureKind.playbackFailed =>
      'Die Audiodatei konnte nicht abgespielt werden.',
    FailureKind.cancelled => 'Der Vorgang wurde abgebrochen.',
    FailureKind.unknown => 'Bitte erneut versuchen.',
  };

  @override
  String toString() =>
      'AppFailure(${kind.name}${statusCode != null ? ', $statusCode' : ''}'
      '${detail != null ? ': $detail' : ''})';

  /// Übersetzt beliebige Ausnahmen in eine [AppFailure].
  static AppFailure from(Object error) {
    if (error is AppFailure) return error;
    if (error is HandshakeException || error is TlsException) {
      return AppFailure(FailureKind.tlsError, detail: '$error');
    }
    if (error is SocketException) {
      final code = error.osError?.errorCode;
      // Netz nicht erreichbar / kein Interface (Linux/Android 101, iOS 51/50).
      if (code == 101 || code == 51 || code == 50 || code == 7) {
        return AppFailure(FailureKind.offline, detail: error.message);
      }
      return AppFailure(FailureKind.serverUnreachable, detail: error.message);
    }
    if (error is HttpException) {
      return AppFailure(FailureKind.downloadInterrupted, detail: error.message);
    }
    if (error is TimeoutException) {
      return const AppFailure(
        FailureKind.serverUnreachable,
        detail: 'Zeitüberschreitung',
      );
    }
    if (error is FileSystemException) {
      if (isOutOfSpace(error)) {
        return AppFailure(
          FailureKind.insufficientStorage,
          detail: error.message,
        );
      }
      return AppFailure(FailureKind.unknown, detail: error.message);
    }
    if (error is UnsupportedPackageVersionException) {
      return AppFailure(
        FailureKind.unsupportedPackageVersion,
        detail: 'formatVersion ${error.formatVersion}',
      );
    }
    if (error is ManifestFormatException) {
      return AppFailure(FailureKind.corruptPackage, detail: error.message);
    }
    if (error is ZipFormatException) {
      return AppFailure(FailureKind.corruptPackage, detail: error.message);
    }
    if (isZipCancellation(error)) {
      return const AppFailure(FailureKind.cancelled);
    }
    return AppFailure(FailureKind.unknown, detail: '$error');
  }
}

/// ENOSPC (Linux/Android/iOS: 28) bzw. ERROR_DISK_FULL (Windows: 112).
bool isOutOfSpace(FileSystemException e) {
  final code = e.osError?.errorCode;
  return code == 28 || code == 112 || code == 39;
}
