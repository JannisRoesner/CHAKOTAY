import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Ablage des CHAPEL-Session-Cookies (`nuxt-session`) je Server.
///
/// Das Cookie ist das einzige gespeicherte Geheimnis – Passwörter werden
/// niemals gespeichert. Es wird ausschließlich im Keychain (iOS) bzw. mit
/// Android-Keystore-gestützter Verschlüsselung abgelegt.
abstract interface class SessionStore {
  Future<String?> read(String origin);
  Future<void> write(String origin, String cookieValue);
  Future<void> clear(String origin);
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  final FlutterSecureStorage _storage;

  static String _key(String origin) => 'chapel-session:$origin';

  @override
  Future<String?> read(String origin) => _storage.read(key: _key(origin));

  @override
  Future<void> write(String origin, String cookieValue) =>
      _storage.write(key: _key(origin), value: cookieValue);

  @override
  Future<void> clear(String origin) => _storage.delete(key: _key(origin));
}

/// Flüchtige Ablage, z. B. für Tests.
class MemorySessionStore implements SessionStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String origin) async => _values[origin];

  @override
  Future<void> write(String origin, String cookieValue) async =>
      _values[origin] = cookieValue;

  @override
  Future<void> clear(String origin) async => _values.remove(origin);
}
