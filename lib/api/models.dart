import '../core/failures.dart';

/// Angemeldeter Benutzer (Teilmenge von `SessionUser` aus CHAPEL).
class ChapelUser {
  const ChapelUser({
    required this.id,
    required this.email,
    required this.name,
    required this.role,
    required this.mustChangePassword,
  });

  final int id;
  final String email;
  final String name;
  final String role;
  final bool mustChangePassword;

  factory ChapelUser.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final email = json['email'];
    if (id is! int || email is! String) {
      throw const AppFailure(
        FailureKind.invalidResponse,
        detail: 'Benutzerobjekt unvollständig',
      );
    }
    return ChapelUser(
      id: id,
      email: email,
      name: json['name'] is String ? json['name']! as String : email,
      role: json['role'] is String ? json['role']! as String : 'editor',
      mustChangePassword: json['mustChangePassword'] == true,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'email': email,
    'name': name,
    'role': role,
    'mustChangePassword': mustChangePassword,
  };
}

/// Eintrag aus `GET /api/packages` (`PackageSummaryDto`).
class PackageSummary {
  const PackageSummary({
    required this.serviceId,
    required this.name,
    required this.serviceDate,
    required this.version,
    required this.updatedAt,
    required this.stepCount,
    required this.totalAudioBytes,
    required this.manifestUrl,
    required this.downloadUrl,
  });

  final int serviceId;
  final String name;
  final DateTime serviceDate;
  final String version;
  final DateTime? updatedAt;
  final int stepCount;
  final int totalAudioBytes;
  final String manifestUrl;
  final String downloadUrl;

  factory PackageSummary.fromJson(Map<String, Object?> json) {
    final id = json['serviceId'];
    final name = json['name'];
    final version = json['version'];
    final date = DateTime.tryParse(json['serviceDate']?.toString() ?? '');
    if (id is! int || name is! String || version is! String || date == null) {
      throw const AppFailure(
        FailureKind.invalidResponse,
        detail: 'Paketliste unvollständig',
      );
    }
    final steps = json['stepCount'];
    final bytes = json['totalAudioBytes'];
    return PackageSummary(
      serviceId: id,
      name: name,
      serviceDate: date,
      version: version,
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
      stepCount: steps is int ? steps : 0,
      totalAudioBytes: bytes is int ? bytes : 0,
      manifestUrl: json['manifestUrl'] is String
          ? json['manifestUrl']! as String
          : '/api/packages/$id',
      downloadUrl: json['downloadUrl'] is String
          ? json['downloadUrl']! as String
          : '/api/packages/$id/download',
    );
  }
}
