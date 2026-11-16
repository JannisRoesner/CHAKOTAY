import 'dart:io';

import 'package:chakotay/playback/progress_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  late DateTime now;
  late ProgressStore store;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('chakotay_progress_');
    now = DateTime(2026, 11, 29, 9, 30);
    store = ProgressStore(File('${dir.path}/progress.json'), clock: () => now);
  });
  tearDown(() => dir.delete(recursive: true));

  test('speichert und lädt Fortschritt (auch nach Neustart)', () async {
    await store.save(
      'k',
      version: 'v1',
      currentIndex: 3,
      playedIndices: [0, 2],
    );
    final reloaded = ProgressStore(
      File('${dir.path}/progress.json'),
      clock: () => now,
    );
    final p = await reloaded.load('k', version: 'v1', stepCount: 6);
    expect(p!.currentIndex, 3);
    expect(p.playedIndices, [0, 2]);
  });

  test('Versionswechsel setzt den Fortschritt zurück (wie CHAPEL)', () async {
    await store.save('k', version: 'v1', currentIndex: 3, playedIndices: [0]);
    expect(await store.load('k', version: 'v2', stepCount: 6), isNull);
    // Auch die alte Version ist danach verworfen.
    expect(await store.load('k', version: 'v1', stepCount: 6), isNull);
  });

  test('verfällt nach 24 Stunden (wie CHAPEL)', () async {
    await store.save('k', version: 'v1', currentIndex: 1, playedIndices: []);
    now = now.add(const Duration(hours: 23));
    expect(await store.load('k', version: 'v1', stepCount: 3), isNotNull);
    now = now.add(const Duration(hours: 2));
    expect(await store.load('k', version: 'v1', stepCount: 3), isNull);
  });

  test('klemmt Indizes auf den Ablauf', () async {
    await store.save(
      'k',
      version: 'v1',
      currentIndex: 9,
      playedIndices: [1, 7, -1],
    );
    final p = await store.load('k', version: 'v1', stepCount: 4);
    expect(p!.currentIndex, 3);
    expect(p.playedIndices, [1]);
  });

  test('beschädigte Datei führt zu leerem Stand statt Absturz', () async {
    await File('${dir.path}/progress.json').writeAsString('{kaputt');
    expect(await store.load('k', version: 'v1', stepCount: 2), isNull);
    await store.save('k', version: 'v1', currentIndex: 1, playedIndices: []);
    expect(await store.load('k', version: 'v1', stepCount: 2), isNotNull);
  });
}
