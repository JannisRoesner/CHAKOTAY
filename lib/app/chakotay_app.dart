import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../ui/screens/downloads_screen.dart';
import '../ui/screens/library_screen.dart';
import '../ui/screens/settings_screen.dart';
import '../ui/theme.dart';
import 'app_scope.dart';

class ChakotayApp extends StatelessWidget {
  const ChakotayApp({super.key, required this.services});

  final AppServices services;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      services: services,
      child: ListenableBuilder(
        listenable: services.settings,
        builder: (context, _) => MaterialApp(
          title: 'CHAKOTAY',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light, services.settings.colorScheme),
          darkTheme: buildTheme(Brightness.dark, services.settings.colorScheme),
          themeMode: services.settings.themeMode,
          locale: const Locale('de'),
          supportedLocales: const [Locale('de')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const HomeShell(),
        ),
      ),
    );
  }
}

/// Drei Hauptbereiche mit Tab-Leiste (Telefon) bzw. Navigation Rail (Tablet,
/// Querformat). Die Bereiche behalten ihren Zustand beim Wechseln.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  void _select(int index) => setState(() => _index = index);

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    final pages = [
      LibraryScreen(onOpenDownloads: () => _select(1)),
      const DownloadsScreen(),
      SettingsScreen(onOpenDownloads: () => _select(1)),
    ];
    final body = IndexedStack(index: _index, children: pages);

    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final downloadIcon = Badge(
          isLabelVisible: library.hasActiveDownloads,
          smallSize: 8,
          child: const Icon(Icons.download_outlined),
        );
        final downloadIconSelected = Badge(
          isLabelVisible: library.hasActiveDownloads,
          smallSize: 8,
          child: const Icon(Icons.download_rounded),
        );
        final wide = MediaQuery.sizeOf(context).width >= 840;
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  right: false,
                  child: NavigationRail(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    labelType: NavigationRailLabelType.all,
                    destinations: [
                      const NavigationRailDestination(
                        icon: Icon(Icons.library_music_outlined),
                        selectedIcon: Icon(Icons.library_music_rounded),
                        label: Text('Gottesdienste'),
                      ),
                      NavigationRailDestination(
                        icon: downloadIcon,
                        selectedIcon: downloadIconSelected,
                        label: const Text('Laden'),
                      ),
                      const NavigationRailDestination(
                        icon: Icon(Icons.settings_outlined),
                        selectedIcon: Icon(Icons.settings_rounded),
                        label: Text('Einstellungen'),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 0.5),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _select,
            destinations: [
              const NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                selectedIcon: Icon(Icons.library_music_rounded),
                label: 'Gottesdienste',
              ),
              NavigationDestination(
                icon: downloadIcon,
                selectedIcon: downloadIconSelected,
                label: 'Laden',
              ),
              const NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings_rounded),
                label: 'Einstellungen',
              ),
            ],
          ),
        );
      },
    );
  }
}
