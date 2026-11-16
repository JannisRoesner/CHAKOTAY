import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_scope.dart';
import '../../auth/account_controller.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'library_screen.dart' show adaptiveDialogAction;

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.onOpenDownloads});

  final VoidCallback onOpenDownloads;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Future<PackageInfo> _info;
  Future<int>? _storage;

  @override
  void initState() {
    super.initState();
    _info = PackageInfo.fromPlatform();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _storage ??= AppScope.of(context).library.storageBytes();
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final account = services.account;
    final settings = services.settings;
    final theme = Theme.of(context);
    final tokens = ChakotayColors.of(context);

    return Scaffold(
      body: ListenableBuilder(
        listenable: Listenable.merge([account, settings, services.library]),
        builder: (context, _) {
          final (statusLabel, statusIcon, statusColor) = _status(
            account.state,
            tokens,
            theme,
          );
          final user = account.user;
          final signedIn =
              account.state == AccountState.connected ||
              account.state == AccountState.unverified ||
              account.state == AccountState.offline ||
              account.state == AccountState.passwordChangeRequired;
          return CustomScrollView(
            slivers: [
              const SliverAppBar.large(title: Text('Einstellungen')),
              SliverList.list(
                children: [
                  GroupedSection(
                    header: 'CHAPEL-Server',
                    footer:
                        'Die Wiedergabe heruntergeladener Gottesdienste funktioniert '
                        'unabhängig von Verbindung und Anmeldung.',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.dns_outlined),
                        title: const Text('Adresse'),
                        subtitle: Text(
                          account.server?.origin ?? 'Nicht eingerichtet',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          account.editServer();
                          widget.onOpenDownloads();
                        },
                      ),
                      ListTile(
                        leading: Icon(statusIcon, color: statusColor),
                        title: const Text('Verbindung'),
                        trailing: Text(
                          statusLabel,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: statusColor,
                          ),
                        ),
                        onTap: account.server == null ? null : account.verify,
                      ),
                    ],
                  ),
                  GroupedSection(
                    header: 'Konto',
                    children: [
                      if (user != null && signedIn)
                        ListTile(
                          leading: const Icon(Icons.person_outline_rounded),
                          title: Text(user.name),
                          subtitle: Text(user.email),
                        ),
                      if (signedIn)
                        ListTile(
                          leading: Icon(
                            Icons.logout_rounded,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            'Abmelden',
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
                          onTap: () => _confirmLogout(context),
                        )
                      else
                        ListTile(
                          leading: const Icon(Icons.login_rounded),
                          title: const Text('Anmelden'),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: widget.onOpenDownloads,
                        ),
                    ],
                  ),
                  GroupedSection(
                    header: 'Darstellung',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SegmentedButton<ThemeMode>(
                          showSelectedIcon: false,
                          expandedInsets: EdgeInsets.zero,
                          style: SegmentedButton.styleFrom(
                            selectedBackgroundColor: tokens.songContainer,
                            selectedForegroundColor: theme.colorScheme.primary,
                          ),
                          segments: const [
                            ButtonSegment(
                              value: ThemeMode.system,
                              label: Text('System'),
                              icon: Icon(Icons.brightness_auto_outlined),
                            ),
                            ButtonSegment(
                              value: ThemeMode.light,
                              label: Text('Hell'),
                              icon: Icon(Icons.light_mode_outlined),
                            ),
                            ButtonSegment(
                              value: ThemeMode.dark,
                              label: Text('Dunkel'),
                              icon: Icon(Icons.dark_mode_outlined),
                            ),
                          ],
                          selected: {settings.themeMode},
                          onSelectionChanged: (s) =>
                              settings.setThemeMode(s.first),
                        ),
                      ),
                    ],
                  ),
                  GroupedSection(
                    header: 'Wiedergabe',
                    footer:
                        'Verhindert, dass sich der Bildschirm während eines '
                        'Gottesdienstes in der Wiedergabeansicht sperrt.',
                    children: [
                      SwitchListTile.adaptive(
                        secondary: const Icon(
                          Icons.screen_lock_portrait_outlined,
                        ),
                        title: const Text('Bildschirm aktiv halten'),
                        value: settings.keepScreenOn,
                        onChanged: settings.setKeepScreenOn,
                      ),
                    ],
                  ),
                  GroupedSection(
                    header: 'Speicher',
                    children: [
                      ListTile(
                        leading: const Icon(Icons.library_music_outlined),
                        title: const Text('Gottesdienste'),
                        trailing: Text(
                          '${services.library.packages.length}',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      FutureBuilder<int>(
                        future: _storage,
                        builder: (context, snap) => ListTile(
                          leading: const Icon(Icons.sd_storage_outlined),
                          title: const Text('Belegter Speicher'),
                          trailing: Text(
                            snap.hasData ? formatBytes(snap.data!) : '…',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          onTap: () => setState(() {
                            _storage = services.library.storageBytes();
                          }),
                        ),
                      ),
                    ],
                  ),
                  FutureBuilder<PackageInfo>(
                    future: _info,
                    builder: (context, snap) => GroupedSection(
                      header: 'Über CHAKOTAY',
                      footer:
                          'Cross-platform Hymn Audio Kiosk for Offline Track Access '
                          'and PlaYback – Offline-Wiedergabe für CHAPEL.',
                      children: [
                        ListTile(
                          leading: const Icon(Icons.info_outline_rounded),
                          title: const Text('Version'),
                          trailing: Text(
                            snap.hasData
                                ? '${snap.data!.version} (${snap.data!.buildNumber})'
                                : '…',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.code_rounded),
                          title: const Text('Quellcode'),
                          subtitle: const Text(
                            'github.com/JannisRoesner/CHAKOTAY',
                          ),
                          trailing: const Icon(
                            Icons.open_in_new_rounded,
                            size: 20,
                          ),
                          onTap: () => launchUrl(
                            Uri.parse(
                              'https://github.com/JannisRoesner/CHAKOTAY',
                            ),
                            mode: LaunchMode.externalApplication,
                          ),
                        ),
                        ListTile(
                          leading: const Icon(Icons.gavel_rounded),
                          title: const Text('Lizenzen'),
                          subtitle: const Text(
                            'GNU AGPL v3.0 und verwendete Bibliotheken',
                          ),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => showLicensePage(
                            context: context,
                            applicationName: 'CHAKOTAY',
                            applicationVersion: snap.data?.version,
                            applicationLegalese:
                                '© Jannis Rösner · GNU AGPL v3.0',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  (String, IconData, Color) _status(
    AccountState state,
    ChakotayColors tokens,
    ThemeData theme,
  ) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return switch (state) {
      AccountState.noServer => ('Kein Server', Icons.cloud_off_rounded, muted),
      AccountState.signedOut => (
        'Nicht angemeldet',
        Icons.cloud_outlined,
        muted,
      ),
      AccountState.unverified => (
        'Angemeldet',
        Icons.cloud_queue_rounded,
        muted,
      ),
      AccountState.connected => (
        'Verbunden',
        Icons.cloud_done_rounded,
        tokens.success,
      ),
      AccountState.sessionExpired => (
        'Sitzung abgelaufen',
        Icons.timer_off_outlined,
        tokens.warning,
      ),
      AccountState.passwordChangeRequired => (
        'Passwort ändern',
        Icons.lock_reset_rounded,
        tokens.warning,
      ),
      AccountState.offline => (
        'Offline',
        Icons.cloud_off_rounded,
        tokens.warning,
      ),
    };
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final account = AppScope.of(context).account;
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('Abmelden?'),
        content: const Text(
          'Heruntergeladene Gottesdienste bleiben auf dem Gerät und abspielbar.',
        ),
        actions: [
          adaptiveDialogAction(
            context,
            label: 'Abbrechen',
            onPressed: () => Navigator.pop(context, false),
          ),
          adaptiveDialogAction(
            context,
            label: 'Abmelden',
            destructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (ok == true) {
      await account.logout();
      if (context.mounted) AppScope.of(context).library.clearRemote();
    }
  }
}
