import 'dart:io';

import 'package:chakotay/app/app_scope.dart';
import 'package:chakotay/app/chakotay_app.dart';
import 'package:chakotay/auth/account_controller.dart';
import 'package:chakotay/auth/session_store.dart';
import 'package:chakotay/library/library_controller.dart';
import 'package:chakotay/packages/package_installer.dart';
import 'package:chakotay/packages/package_repository.dart';
import 'package:chakotay/playback/progress_store.dart';
import 'package:chakotay/settings/key_value_store.dart';
import 'package:chakotay/settings/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../support/chapel_fixtures.dart';
import '../support/fake_audio_engine.dart';

void main() {
  late Directory dir;
  late FakeAudioEngine engine;

  setUpAll(() async {
    await initializeDateFormatting('de');
    PackageInfo.setMockInitialValues(
      appName: 'CHAKOTAY',
      packageName: 'family.roesner.chakotay',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<AppServices> services({bool withPackage = true}) async {
    dir = await Directory.systemTemp.createTemp('chakotay_ui_');
    final store = MemoryKeyValueStore()
      ..values['playback.keepScreenOn'] = false;
    final settings = SettingsStore(store);
    await settings.ready;
    final account = AccountController(
      settings: settings,
      sessions: MemorySessionStore(),
    );
    final repo = PackageRepository(Directory('${dir.path}/library'));
    final installer = PackageInstaller(repo);
    if (withPackage) {
      final a = fakeAudio(1);
      final b = fakeAudio(2);
      final zip = await writeTemp(
        dir,
        'p.zip',
        buildPackageZip(
          manifestJson(
            name: '1. Advent',
            steps: [
              stepJson(
                position: 0,
                kind: 'liturgy',
                label: 'Kyrie',
                title: 'Kyrie eleison',
                audio: a,
              ),
              stepJson(position: 1, label: 'Eingangslied'),
              stepJson(
                position: 2,
                label: 'Wochenlied',
                title: 'Macht hoch die Tür',
                audio: b,
                playbackRate: 0.92,
              ),
            ],
          ),
          [a, b],
        ),
      );
      await installer.install(zip, serverOrigin: 'https://chapel.example.org');
    }
    final library = LibraryController(
      repository: repo,
      installer: installer,
      account: account,
      settings: settings,
    );
    await library.load();
    await account.restore();
    engine = FakeAudioEngine();
    return AppServices(
      settings: settings,
      account: account,
      library: library,
      repository: repo,
      progress: ProgressStore(File('${dir.path}/progress.json')),
      engineFactory: () => engine,
      dataRoot: dir,
    );
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('leere Bibliothek zeigt Empty State mit Handlungsaufforderung', (
    tester,
  ) async {
    final s = (await tester.runAsync(() => services(withPackage: false)))!;
    await tester.pumpWidget(ChakotayApp(services: s));
    await settle(tester);
    expect(find.text('Noch keine Gottesdienste'), findsOneWidget);
    await tester.tap(find.text('Gottesdienste laden'));
    await settle(tester);
    expect(find.text('Mit CHAPEL verbinden'), findsOneWidget);
    await tester.runAsync(() => dir.delete(recursive: true));
  });

  testWidgets('Wiedergabe: Play → Titelende → Stopp, kein Autoplay', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final s = (await tester.runAsync(services))!;
    await tester.pumpWidget(ChakotayApp(services: s));
    await settle(tester);

    expect(find.text('1. Advent'), findsOneWidget);
    expect(find.text('Offline verfügbar'), findsOneWidget);
    await tester.tap(find.text('1. Advent'));
    await settle(tester);

    // Ablauf inkl. leerem Schritt sichtbar.
    expect(find.text('Kein Audio – wird übersprungen'), findsOneWidget);
    expect(find.text('92 %'), findsOneWidget);
    expect(find.text('Gestoppt'), findsOneWidget);

    await tester.tap(find.text('Abspielen'));
    await settle(tester);
    expect(find.text('Läuft'), findsOneWidget);
    expect(engine.playCount, 1);

    engine.complete();
    await settle(tester);
    expect(find.text('Titel beendet – bereit'), findsOneWidget);
    expect(find.text('Abspielen'), findsOneWidget);
    expect(
      engine.playCount,
      1,
      reason: 'nächster Titel startet nicht automatisch',
    );
    // Auswahl steht jetzt auf dem nächsten abspielbaren Schritt.
    expect(find.text('Macht hoch die Tür'), findsNWidgets(2));

    await tester.tap(find.text('Abspielen'));
    await settle(tester);
    expect(engine.playCount, 2);
    expect(engine.rate, 0.92);

    await tester.tap(find.byType(BackButton));
    await settle(tester);
    await tester.runAsync(() async {
      await s.progress.idle;
      await dir.delete(recursive: true);
    });
  });
}
