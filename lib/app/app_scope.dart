import 'dart:io';

import 'package:flutter/widgets.dart';

import '../auth/account_controller.dart';
import '../library/library_controller.dart';
import '../packages/package_repository.dart';
import '../playback/audio_engine.dart';
import '../playback/progress_store.dart';
import '../settings/settings_store.dart';

/// Bündelt die langlebigen Dienste der App.
class AppServices {
  AppServices({
    required this.settings,
    required this.account,
    required this.library,
    required this.repository,
    required this.progress,
    required this.engineFactory,
    required this.dataRoot,
  });

  final SettingsStore settings;
  final AccountController account;
  final LibraryController library;
  final PackageRepository repository;
  final ProgressStore progress;
  final AudioEngine Function() engineFactory;
  final Directory dataRoot;
}

/// Stellt [AppServices] im Widget-Baum bereit.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'AppScope fehlt im Widget-Baum');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
