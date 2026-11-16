/// Defensiver ZIP-Leser für CHAPEL-Paketcontainer.
///
/// CHAPEL erzeugt unkomprimierte ZIPs (Methode STORE, kein ZIP64, max. 4 GB,
/// siehe `createPackageZip` in `servicePackage.ts`). Statt einer generischen
/// Bibliothek, die Archive oft komplett in den Speicher lädt, liest dieser
/// Leser das zentrale Verzeichnis selbst und streamt Einträge direkt in
/// Dateien. Jede Angabe des Archivs wird gegen Dateigröße, Lage und
/// Namensregeln geprüft (Path Traversal, Überlappungen, Zip-Bomben,
/// verschlüsselte Einträge, ZIP64).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class ZipFormatException implements Exception {
  ZipFormatException(this.message);
  final String message;
  @override
  String toString() => 'ZipFormatException: $message';
}

class ZipEntry {
  ZipEntry._({
    required this.name,
    required this.method,
    required this.crc32,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.dataOffset,
  });

  final String name;

  /// 0 = STORE, 8 = DEFLATE.
  final int method;
  final int crc32;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  final int dataOffset;

  bool get isDirectory => name.endsWith('/');
}

class ZipExtractResult {
  const ZipExtractResult(this.sha256Hex, this.bytesWritten);
  final String sha256Hex;
  final int bytesWritten;
}

class SafeZipReader {
  SafeZipReader._(this.file, this.entries);

  static const int _eocdSignature = 0x06054b50;
  static const int _centralSignature = 0x02014b50;
  static const int _localSignature = 0x04034b50;
  static const int _maxCommentLength = 0xFFFF;

  final File file;

  /// Einträge nach Namen. Doppelte Namen werden beim Öffnen abgelehnt.
  final Map<String, ZipEntry> entries;

  /// Öffnet und prüft das Archiv. Liest nur Verzeichnisstrukturen, keine Inhalte.
  static Future<SafeZipReader> open(File file, {int maxEntries = 5000}) async {
    final raf = await file.open();
    try {
      final length = await raf.length();
      if (length < 22) throw ZipFormatException('Datei zu kurz');
      if (length > 0xFFFFFFFF) {
        throw ZipFormatException('ZIP64 wird nicht unterstützt');
      }

      // End of central directory suchen (am Ende, ggf. hinter einem Kommentar).
      final tailLength = length < 22 + _maxCommentLength
          ? length
          : 22 + _maxCommentLength;
      await raf.setPosition(length - tailLength);
      final tail = await raf.read(tailLength);
      final tailData = ByteData.sublistView(tail);
      int eocd = -1;
      for (var i = tail.length - 22; i >= 0; i--) {
        if (tailData.getUint32(i, Endian.little) == _eocdSignature) {
          final commentLength = tailData.getUint16(i + 20, Endian.little);
          if (i + 22 + commentLength == tail.length) {
            eocd = i;
            break;
          }
        }
      }
      if (eocd < 0) throw ZipFormatException('Kein ZIP-Verzeichnis gefunden');

      final eocdAbs = length - tailLength + eocd;
      final diskNumber = tailData.getUint16(eocd + 4, Endian.little);
      final cdDisk = tailData.getUint16(eocd + 6, Endian.little);
      final entriesOnDisk = tailData.getUint16(eocd + 8, Endian.little);
      final entryCount = tailData.getUint16(eocd + 10, Endian.little);
      final cdSize = tailData.getUint32(eocd + 12, Endian.little);
      final cdOffset = tailData.getUint32(eocd + 16, Endian.little);

      if (diskNumber != 0 || cdDisk != 0 || entriesOnDisk != entryCount) {
        throw ZipFormatException(
          'Mehrteilige Archive werden nicht unterstützt',
        );
      }
      if (entryCount == 0xFFFF ||
          cdSize == 0xFFFFFFFF ||
          cdOffset == 0xFFFFFFFF) {
        throw ZipFormatException('ZIP64 wird nicht unterstützt');
      }
      if (entryCount > maxEntries) {
        throw ZipFormatException('Zu viele Einträge ($entryCount)');
      }
      if (cdOffset + cdSize > eocdAbs) {
        throw ZipFormatException('Zentrales Verzeichnis außerhalb der Datei');
      }

      await raf.setPosition(cdOffset);
      final cd = await raf.read(cdSize);
      if (cd.length != cdSize) throw ZipFormatException('Verzeichnis gekürzt');
      final cdData = ByteData.sublistView(cd);

      final result = <String, ZipEntry>{};
      var p = 0;
      for (var n = 0; n < entryCount; n++) {
        if (p + 46 > cd.length ||
            cdData.getUint32(p, Endian.little) != _centralSignature) {
          throw ZipFormatException('Beschädigter Verzeichniseintrag');
        }
        final flags = cdData.getUint16(p + 8, Endian.little);
        final method = cdData.getUint16(p + 10, Endian.little);
        final crc = cdData.getUint32(p + 16, Endian.little);
        final compSize = cdData.getUint32(p + 20, Endian.little);
        final uncompSize = cdData.getUint32(p + 24, Endian.little);
        final nameLength = cdData.getUint16(p + 28, Endian.little);
        final extraLength = cdData.getUint16(p + 30, Endian.little);
        final commentLength = cdData.getUint16(p + 32, Endian.little);
        final localOffset = cdData.getUint32(p + 42, Endian.little);
        final recordEnd = p + 46 + nameLength + extraLength + commentLength;
        if (recordEnd > cd.length) {
          throw ZipFormatException('Beschädigter Verzeichniseintrag');
        }
        final nameBytes = cd.sublist(p + 46, p + 46 + nameLength);
        p = recordEnd;

        if (flags & 0x1 != 0) {
          throw ZipFormatException('Verschlüsselte Einträge sind unzulässig');
        }
        if (method != 0 && method != 8) {
          throw ZipFormatException('Kompressionsmethode $method unzulässig');
        }
        if (compSize == 0xFFFFFFFF || uncompSize == 0xFFFFFFFF) {
          throw ZipFormatException('ZIP64 wird nicht unterstützt');
        }
        if (method == 0 && compSize != uncompSize) {
          throw ZipFormatException('Inkonsistente Größen');
        }

        final String name;
        try {
          name = utf8.decode(nameBytes);
        } on FormatException {
          throw ZipFormatException('Ungültiger Dateiname');
        }
        validateEntryName(name);
        if (result.containsKey(name)) {
          throw ZipFormatException('Doppelter Eintrag: $name');
        }

        // Lokalen Header prüfen – Name muss übereinstimmen, Daten im Rahmen.
        if (localOffset + 30 > cdOffset) {
          throw ZipFormatException('Eintrag außerhalb der Datei: $name');
        }
        await raf.setPosition(localOffset);
        final local = await raf.read(30);
        final localData = ByteData.sublistView(local);
        if (local.length != 30 ||
            localData.getUint32(0, Endian.little) != _localSignature) {
          throw ZipFormatException('Beschädigter lokaler Header: $name');
        }
        final localNameLength = localData.getUint16(26, Endian.little);
        final localExtraLength = localData.getUint16(28, Endian.little);
        final localName = await raf.read(localNameLength);
        if (!_bytesEqual(localName, nameBytes)) {
          throw ZipFormatException('Abweichender lokaler Name: $name');
        }
        final dataOffset =
            localOffset + 30 + localNameLength + localExtraLength;
        if (dataOffset + compSize > cdOffset) {
          throw ZipFormatException('Eintrag außerhalb der Datei: $name');
        }

        result[name] = ZipEntry._(
          name: name,
          method: method,
          crc32: crc,
          compressedSize: compSize,
          uncompressedSize: uncompSize,
          localHeaderOffset: localOffset,
          dataOffset: dataOffset,
        );
      }

      // Überlappende Datenbereiche (z. B. präparierte "Quines") ablehnen.
      final sorted = result.values.toList()
        ..sort((a, b) => a.localHeaderOffset.compareTo(b.localHeaderOffset));
      for (var i = 1; i < sorted.length; i++) {
        final prev = sorted[i - 1];
        if (prev.dataOffset + prev.compressedSize >
            sorted[i].localHeaderOffset) {
          throw ZipFormatException('Überlappende Einträge');
        }
      }

      return SafeZipReader._(file, Map.unmodifiable(result));
    } finally {
      await raf.close();
    }
  }

  /// Wirft bei Namen, die beim Entpacken gefährlich wären.
  static void validateEntryName(String name) {
    if (name.isEmpty || name.length > 512) {
      throw ZipFormatException('Unzulässiger Dateiname');
    }
    if (name.contains('\\') ||
        name.contains('\u0000') ||
        name.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name)) {
      throw ZipFormatException('Unzulässiger Pfad: $name');
    }
    final segments = name.split('/');
    for (var i = 0; i < segments.length; i++) {
      final s = segments[i];
      final isTrailingSlash = i == segments.length - 1 && s.isEmpty;
      if (s == '..' || s == '.' || (s.isEmpty && !isTrailingSlash)) {
        throw ZipFormatException('Unzulässiger Pfad: $name');
      }
    }
  }

  Stream<List<int>> _rawStream(ZipEntry entry) {
    final raw = file.openRead(
      entry.dataOffset,
      entry.dataOffset + entry.compressedSize,
    );
    if (entry.method == 8) return raw.transform(ZLibDecoder(raw: true));
    return raw;
  }

  /// Liest einen (kleinen) Eintrag vollständig in den Speicher.
  Future<Uint8List> readBytes(ZipEntry entry, {required int maxBytes}) async {
    if (entry.uncompressedSize > maxBytes) {
      throw ZipFormatException('${entry.name} ist zu groß');
    }
    final builder = BytesBuilder(copy: false);
    final crc = Crc32();
    await for (final chunk in _rawStream(entry)) {
      if (builder.length + chunk.length > entry.uncompressedSize) {
        throw ZipFormatException('${entry.name} größer als angegeben');
      }
      crc.add(chunk);
      builder.add(chunk);
    }
    if (builder.length != entry.uncompressedSize) {
      throw ZipFormatException('${entry.name} unvollständig');
    }
    if (crc.value != entry.crc32) {
      throw ZipFormatException('CRC-Fehler in ${entry.name}');
    }
    return builder.takeBytes();
  }

  /// Streamt einen Eintrag in [target] und berechnet dabei SHA-256.
  ///
  /// Größe und CRC32 werden gegen das Verzeichnis geprüft; mehr Daten als
  /// angekündigt führen sofort zum Abbruch (Schutz vor Zip-Bomben).
  Future<ZipExtractResult> extractTo(
    ZipEntry entry,
    File target, {
    void Function(int bytes)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final sink = target.openWrite();
    final digestSink = _DigestSink();
    final hasher = sha256.startChunkedConversion(digestSink);
    final crc = Crc32();
    var written = 0;
    try {
      await for (final chunk in _rawStream(entry)) {
        if (isCancelled?.call() ?? false) throw const _Cancelled();
        written += chunk.length;
        if (written > entry.uncompressedSize) {
          throw ZipFormatException('${entry.name} größer als angegeben');
        }
        hasher.add(chunk);
        crc.add(chunk);
        sink.add(chunk);
        onProgress?.call(chunk.length);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    hasher.close();
    if (written != entry.uncompressedSize) {
      throw ZipFormatException('${entry.name} unvollständig');
    }
    if (crc.value != entry.crc32) {
      throw ZipFormatException('CRC-Fehler in ${entry.name}');
    }
    return ZipExtractResult(digestSink.value.toString(), written);
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Signalisiert einen Abbruch während des Entpackens.
class _Cancelled implements Exception {
  const _Cancelled();
}

bool isZipCancellation(Object error) => error is _Cancelled;

class _DigestSink implements Sink<Digest> {
  Digest? _value;
  Digest get value => _value!;
  @override
  void add(Digest data) => _value = data;
  @override
  void close() {}
}

/// CRC-32 (IEEE 802.3), wie im ZIP-Format verwendet.
class Crc32 {
  static final Uint32List _table = _buildTable();
  int _crc = 0xFFFFFFFF;

  static Uint32List _buildTable() {
    final table = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1;
      }
      table[n] = c;
    }
    return table;
  }

  void add(List<int> data) {
    var c = _crc;
    for (final b in data) {
      c = _table[(c ^ b) & 0xFF] ^ (c >>> 8);
    }
    _crc = c;
  }

  int get value => (_crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;

  static int of(List<int> data) => (Crc32()..add(data)).value;
}
