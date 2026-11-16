import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chakotay/packages/safe_zip_reader.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/chapel_fixtures.dart';

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chakotay_zip_');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  Future<SafeZipReader> open(List<int> bytes) async =>
      SafeZipReader.open(await writeTemp(dir, 'p.zip', bytes));

  test('liest CHAPEL-Container und entpackt mit SHA-256', () async {
    final a = fakeAudio(1, size: 10000);
    final zip = await open(
      buildZip([
        ZipSpec('manifest.json', utf8.encode('{}')),
        ZipSpec(a.file, a.bytes),
      ]),
    );
    expect(zip.entries.keys, ['manifest.json', a.file]);
    final target = File('${dir.path}/out');
    var progress = 0;
    final result = await zip.extractTo(
      zip.entries[a.file]!,
      target,
      onProgress: (n) => progress += n,
    );
    expect(result.sha256Hex, a.sha);
    expect(result.bytesWritten, 10000);
    expect(progress, 10000);
    expect(await target.readAsBytes(), a.bytes);
    expect(
      utf8.decode(
        await zip.readBytes(zip.entries['manifest.json']!, maxBytes: 100),
      ),
      '{}',
    );
  });

  test('akzeptiert ZIP-Kommentar am Ende', () async {
    final bytes = buildZip([ZipSpec('manifest.json', utf8.encode('{}'))]);
    // Kommentarlänge setzen und Kommentar anhängen.
    final comment = utf8.encode('Kommentar');
    final data = ByteData.sublistView(bytes);
    data.setUint16(bytes.length - 2, comment.length, Endian.little);
    final zip = await open([...bytes, ...comment]);
    expect(zip.entries, contains('manifest.json'));
  });

  group('Path Traversal und unzulässige Namen', () {
    for (final name in [
      '../evil.mp3',
      'audio/../../evil',
      '/absolute.mp3',
      r'audio\win.mp3',
      'C:/x.mp3',
      'audio//x.mp3',
      './x',
    ]) {
      test(name, () async {
        expect(
          () => open(
            buildZip([
              ZipSpec(name, [1, 2, 3]),
            ]),
          ),
          throwsA(isA<ZipFormatException>()),
        );
      });
    }
  });

  test('lehnt doppelte Einträge ab', () async {
    expect(
      () => open(
        buildZip([
          ZipSpec('manifest.json', [1]),
          ZipSpec('manifest.json', [2]),
        ]),
      ),
      throwsA(isA<ZipFormatException>()),
    );
  });

  test('lehnt verschlüsselte Einträge ab', () async {
    expect(
      () => open(
        buildZip([
          ZipSpec('manifest.json', [1], flags: 1),
        ]),
      ),
      throwsA(isA<ZipFormatException>()),
    );
  });

  test('lehnt abgeschnittene Dateien ab', () async {
    final bytes = buildZip([ZipSpec('manifest.json', List.filled(100, 7))]);
    expect(
      () => open(bytes.sublist(0, bytes.length - 30)),
      throwsA(isA<ZipFormatException>()),
    );
    expect(() => open([1, 2, 3]), throwsA(isA<ZipFormatException>()));
    expect(() => open(List.filled(200, 0)), throwsA(isA<ZipFormatException>()));
  });

  test('erkennt CRC-Fehler', () async {
    final zip = await open(
      buildZip([
        ZipSpec('audio/x.mp3', [1, 2, 3], crcOverride: 1234),
      ]),
    );
    expect(
      () => zip.extractTo(zip.entries['audio/x.mp3']!, File('${dir.path}/o')),
      throwsA(isA<ZipFormatException>()),
    );
  });

  test('lehnt ZIP64-Marker ab', () async {
    final bytes = buildZip([
      ZipSpec('manifest.json', [1]),
    ]);
    final data = ByteData.sublistView(bytes);
    data.setUint16(bytes.length - 22 + 10, 0xFFFF, Endian.little);
    data.setUint16(bytes.length - 22 + 8, 0xFFFF, Endian.little);
    expect(() => open(bytes), throwsA(isA<ZipFormatException>()));
  });

  test('lehnt zu viele Einträge ab', () async {
    final bytes = buildZip([
      for (var i = 0; i < 20; i++) ZipSpec('audio/$i.mp3', [i]),
    ]);
    expect(
      () async => SafeZipReader.open(
        await writeTemp(dir, 'm.zip', bytes),
        maxEntries: 5,
      ),
      throwsA(isA<ZipFormatException>()),
    );
  });

  test(
    'lehnt Einträge außerhalb der Datei ab (manipulierter Offset)',
    () async {
      final bytes = buildZip([
        ZipSpec('manifest.json', [1, 2, 3]),
      ]);
      final data = ByteData.sublistView(bytes);
      // Lokalen Header-Offset im zentralen Verzeichnis verbiegen.
      final cdOffset = data.getUint32(bytes.length - 22 + 16, Endian.little);
      data.setUint32(cdOffset + 42, 999999, Endian.little);
      expect(() => open(bytes), throwsA(isA<ZipFormatException>()));
    },
  );

  test(
    'Zip-Bombe: DEFLATE-Eintrag größer als angegeben wird abgebrochen',
    () async {
      // Eintrag manuell als DEFLATE mit falscher (zu kleiner) Größe bauen.
      final payload = List.filled(100000, 0);
      final compressed = ZLibCodec(raw: true).encode(payload);
      final name = utf8.encode('audio/bomb.mp3');
      final crc = Crc32.of(payload);
      const declared = 10;
      final local = ByteData(30)
        ..setUint32(0, 0x04034b50, Endian.little)
        ..setUint16(8, 8, Endian.little)
        ..setUint32(14, crc, Endian.little)
        ..setUint32(18, compressed.length, Endian.little)
        ..setUint32(22, declared, Endian.little)
        ..setUint16(26, name.length, Endian.little);
      final cd = ByteData(46)
        ..setUint32(0, 0x02014b50, Endian.little)
        ..setUint16(10, 8, Endian.little)
        ..setUint32(16, crc, Endian.little)
        ..setUint32(20, compressed.length, Endian.little)
        ..setUint32(24, declared, Endian.little)
        ..setUint16(28, name.length, Endian.little);
      final cdStart = 30 + name.length + compressed.length;
      final end = ByteData(22)
        ..setUint32(0, 0x06054b50, Endian.little)
        ..setUint16(8, 1, Endian.little)
        ..setUint16(10, 1, Endian.little)
        ..setUint32(12, 46 + name.length, Endian.little)
        ..setUint32(16, cdStart, Endian.little);
      final bytes = [
        ...local.buffer.asUint8List(),
        ...name,
        ...compressed,
        ...cd.buffer.asUint8List(),
        ...name,
        ...end.buffer.asUint8List(),
      ];
      final zip = await open(bytes);
      final out = File('${dir.path}/bomb');
      await expectLater(
        zip.extractTo(zip.entries['audio/bomb.mp3']!, out),
        throwsA(isA<ZipFormatException>()),
      );
      expect(await out.length(), lessThanOrEqualTo(declared));
    },
  );

  test('Crc32 entspricht dem Standard-Testvektor', () {
    expect(Crc32.of(ascii.encode('123456789')), 0xCBF43926);
    expect(sha256.convert([]).toString(), startsWith('e3b0c442'));
  });
}
