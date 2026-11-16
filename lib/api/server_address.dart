import '../core/failures.dart';

/// Normalisierte Basis-URL eines CHAPEL-Servers.
///
/// Eingaben ohne Schema werden als HTTPS interpretiert. `http://` wird nur
/// akzeptiert, wenn der Benutzer unverschlüsselte Verbindungen ausdrücklich
/// erlaubt hat (siehe Einstellungen) – nie stillschweigend.
class ServerAddress {
  const ServerAddress._(this.uri);

  /// Basis-URL ohne abschließenden Schrägstrich, z. B. `https://chapel.example.org`.
  final Uri uri;

  bool get isSecure => uri.scheme == 'https';

  /// Schlüssel zur Ablage des Session-Cookies und zur Zuordnung von Paketen.
  String get origin => uri.toString();

  /// Anzeigeform ohne Schema für sichere Adressen.
  String get display => isSecure ? origin.substring('https://'.length) : origin;

  Uri resolve(String path) {
    final base = uri.path.endsWith('/') ? uri.path : '${uri.path}/';
    final relative = path.startsWith('/') ? path.substring(1) : path;
    return uri.replace(path: '$base$relative');
  }

  /// Wirft [AppFailure] mit [FailureKind.invalidServerAddress] bzw.
  /// [FailureKind.insecureConnection].
  static ServerAddress parse(String input, {bool allowInsecure = false}) {
    var text = input.trim();
    if (text.isEmpty || text.contains(RegExp(r'\s'))) {
      throw const AppFailure(FailureKind.invalidServerAddress);
    }
    if (!text.contains('://')) text = 'https://$text';
    final Uri parsed;
    try {
      parsed = Uri.parse(text);
    } on FormatException {
      throw const AppFailure(FailureKind.invalidServerAddress);
    }
    final scheme = parsed.scheme.toLowerCase();
    if (scheme != 'https' && scheme != 'http') {
      throw const AppFailure(FailureKind.invalidServerAddress);
    }
    if (parsed.host.isEmpty ||
        parsed.userInfo.isNotEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      throw const AppFailure(FailureKind.invalidServerAddress);
    }
    if (!RegExp(r'^[A-Za-z0-9.\-\[\]:]+$').hasMatch(parsed.host)) {
      throw const AppFailure(FailureKind.invalidServerAddress);
    }
    if (scheme == 'http' && !allowInsecure) {
      throw const AppFailure(FailureKind.insecureConnection);
    }
    var path = parsed.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return ServerAddress._(
      Uri(
        scheme: scheme,
        host: parsed.host.toLowerCase(),
        port: parsed.hasPort ? parsed.port : null,
        path: path,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ServerAddress && other.origin == origin;

  @override
  int get hashCode => origin.hashCode;

  @override
  String toString() => origin;
}
