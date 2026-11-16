import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chakotay/packages/safe_zip_reader.dart';
import 'package:crypto/crypto.dart';

/// Testdaten im exakten CHAPEL-Paketformat.

class FixtureAudio {
  FixtureAudio(this.bytes, {this.ext = '.mp3'});
  final List<int> bytes;
  final String ext;
  String get sha => sha256.convert(bytes).toString();
  String get file => 'audio/$sha$ext';
}

/// Deterministische „Audiodaten“ (Inhalt ist für die Paketlogik egal).
FixtureAudio fakeAudio(int seed, {int size = 4096}) =>
    FixtureAudio(List<int>.generate(size, (i) => (i * 31 + seed * 17) & 0xFF));

Map<String, Object?> stepJson({
  required int position,
  String kind = 'songSlot',
  String label = 'Lied',
  String? title,
  String? composer,
  int? durationMs,
  double playbackRate = 1,
  FixtureAudio? audio,
  int trackId = 1,
}) => {
  'position': position,
  'kind': kind,
  'label': label,
  'title': title ?? (audio == null ? null : 'Titel $position'),
  'composer': composer,
  'durationMs': durationMs ?? (audio == null ? null : 60000),
  'playbackRate': playbackRate,
  'audio': audio == null
      ? null
      : {
          'file': audio.file,
          'sha256': audio.sha,
          'mimeType': 'audio/mpeg',
          'sizeBytes': audio.bytes.length,
          'url': '/api/tracks/$trackId/stream',
        },
};

Map<String, Object?> manifestJson({
  int serviceId = 12,
  String name = '1. Advent',
  String version = 'ea8c8f53b9835a2dbbc0e3568d7aa6f6',
  String serviceDate = '2026-11-29T00:00:00.000Z',
  required List<Map<String, Object?>> steps,
  int formatVersion = 1,
}) {
  final seen = <String, int>{};
  for (final s in steps) {
    final a = s['audio'] as Map?;
    if (a != null) seen[a['file'] as String] = a['sizeBytes'] as int;
  }
  return {
    'formatVersion': formatVersion,
    'version': version,
    'generatedAt': '2026-11-15T17:00:00.000Z',
    'service': {
      'id': serviceId,
      'name': name,
      'serviceDate': serviceDate,
      'notes': null,
      'updatedAt': '2026-11-15T16:58:57.120Z',
    },
    'steps': steps,
    'totalAudioBytes': seen.values.fold<int>(0, (a, b) => a + b),
  };
}

/// Ein ZIP-Eintrag für [buildZip].
class ZipSpec {
  ZipSpec(this.name, this.data, {this.crcOverride, this.flags = 0});
  final String name;
  final List<int> data;
  final int? crcOverride;
  final int flags;
}

/// Baut ein ZIP wie `createPackageZip` in CHAPEL (STORE, UTF-8, ohne ZIP64).
Uint8List buildZip(List<ZipSpec> entries) {
  final out = BytesBuilder();
  final central = BytesBuilder();
  var offset = 0;
  for (final e in entries) {
    final name = utf8.encode(e.name);
    final crc = e.crcOverride ?? Crc32.of(e.data);
    final local = ByteData(30)
      ..setUint32(0, 0x04034b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 0x0800 | e.flags, Endian.little)
      ..setUint16(8, 0, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint16(12, (1 << 5) | 1, Endian.little)
      ..setUint32(14, crc, Endian.little)
      ..setUint32(18, e.data.length, Endian.little)
      ..setUint32(22, e.data.length, Endian.little)
      ..setUint16(26, name.length, Endian.little)
      ..setUint16(28, 0, Endian.little);
    final cd = ByteData(46)
      ..setUint32(0, 0x02014b50, Endian.little)
      ..setUint16(4, 20, Endian.little)
      ..setUint16(6, 20, Endian.little)
      ..setUint16(8, 0x0800 | e.flags, Endian.little)
      ..setUint16(10, 0, Endian.little)
      ..setUint16(12, 0, Endian.little)
      ..setUint16(14, (1 << 5) | 1, Endian.little)
      ..setUint32(16, crc, Endian.little)
      ..setUint32(20, e.data.length, Endian.little)
      ..setUint32(24, e.data.length, Endian.little)
      ..setUint16(28, name.length, Endian.little)
      ..setUint32(42, offset, Endian.little);
    out
      ..add(local.buffer.asUint8List())
      ..add(name)
      ..add(e.data);
    central
      ..add(cd.buffer.asUint8List())
      ..add(name);
    offset += 30 + name.length + e.data.length;
  }
  final cdBytes = central.takeBytes();
  final end = ByteData(22)
    ..setUint32(0, 0x06054b50, Endian.little)
    ..setUint16(8, entries.length, Endian.little)
    ..setUint16(10, entries.length, Endian.little)
    ..setUint32(12, cdBytes.length, Endian.little)
    ..setUint32(16, offset, Endian.little);
  out
    ..add(cdBytes)
    ..add(end.buffer.asUint8List());
  return out.takeBytes();
}

/// Paket-ZIP aus Manifest und Audiodateien.
Uint8List buildPackageZip(
  Map<String, Object?> manifest,
  List<FixtureAudio> audio, {
  List<ZipSpec> extra = const [],
}) {
  final seen = <String>{};
  return buildZip([
    ZipSpec(
      'manifest.json',
      utf8.encode(const JsonEncoder.withIndent('  ').convert(manifest)),
    ),
    for (final a in audio)
      if (seen.add(a.file)) ZipSpec(a.file, a.bytes),
    ...extra,
  ]);
}

Future<File> writeTemp(Directory dir, String name, List<int> bytes) async {
  final f = File('${dir.path}/$name');
  await f.writeAsBytes(bytes, flush: true);
  return f;
}
