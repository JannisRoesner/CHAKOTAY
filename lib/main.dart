import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app_scope.dart';
import 'app/chakotay_app.dart';
import 'auth/account_controller.dart';
import 'auth/session_store.dart';
import 'library/library_controller.dart';
import 'packages/package_installer.dart';
import 'packages/package_repository.dart';
import 'playback/just_audio_engine.dart';
import 'playback/progress_store.dart';
import 'settings/key_value_store.dart';
import 'settings/settings_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('de');

  final support = await getApplicationSupportDirectory();
  final root = Directory('${support.path}/chakotay');
  await root.create(recursive: true);

  final settings = SettingsStore(SharedPreferencesStore());
  final account = AccountController(
    settings: settings,
    sessions: SecureSessionStore(),
  );
  final repository = PackageRepository(Directory('${root.path}/library'));
  final library = LibraryController(
    repository: repository,
    installer: PackageInstaller(repository),
    account: account,
    settings: settings,
  );

  final services = AppServices(
    settings: settings,
    account: account,
    library: library,
    repository: repository,
    progress: ProgressStore(File('${root.path}/progress.json')),
    engineFactory: JustAudioEngine.new,
    dataRoot: root,
  );

  // Bibliothek zuerst – sie muss unabhängig vom Netzwerk sofort verfügbar sein.
  unawaited(library.load());
  unawaited(account.restore());

  runApp(ChakotayApp(services: services));
}
