import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../../app/app_scope.dart';
import '../../packages/package_repository.dart';
import '../../settings/settings_store.dart';
import '../format.dart';
import '../widgets/common.dart';
import 'package_info_sheet.dart';
import 'player_screen.dart';

/// Startansicht: alle lokal gespeicherten Gottesdienste – vollständig offline.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key, required this.onOpenDownloads});

  final VoidCallback onOpenDownloads;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final library = services.library;
    return ListenableBuilder(
      listenable: Listenable.merge([library, services.settings]),
      builder: (context, _) {
        final packages = library.packages;
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar.large(
                title: const Text('Gottesdienste'),
                actions: [
                  if (packages.isNotEmpty)
                    _SortMenu(settings: services.settings),
                  const SizedBox(width: 4),
                ],
              ),
              if (!library.loaded)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else if (packages.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.library_music_outlined,
                    title: 'Noch keine Gottesdienste',
                    message:
                        'Laden Sie Gottesdienste von Ihrem CHAPEL-Server. Danach '
                        'spielt CHAKOTAY sie ohne Internetverbindung ab.',
                    action: FilledButton.icon(
                      onPressed: onOpenDownloads,
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Gottesdienste laden'),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  sliver: SliverList.separated(
                    itemCount: packages.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, i) => _PackageCard(
                      package: packages[i],
                      onOpenDownloads: onOpenDownloads,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _SortMenu extends StatelessWidget {
  const _SortMenu({required this.settings});
  final SettingsStore settings;

  @override
  Widget build(BuildContext context) {
    const labels = {
      LibrarySort.upcomingFirst: 'Nächste zuerst',
      LibrarySort.newestFirst: 'Neueste zuerst',
      LibrarySort.oldestFirst: 'Älteste zuerst',
    };
    return PopupMenuButton<LibrarySort>(
      tooltip: 'Sortierung: ${labels[settings.sort]}',
      icon: const Icon(Icons.swap_vert_rounded),
      initialValue: settings.sort,
      onSelected: settings.setSort,
      itemBuilder: (_) => [
        for (final e in labels.entries)
          CheckedPopupMenuItem(
            value: e.key,
            checked: settings.sort == e.key,
            child: Text(e.value),
          ),
      ],
    );
  }
}

enum _Action { update, info, delete }

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.package, required this.onOpenDownloads});

  final LocalPackage package;
  final VoidCallback onOpenDownloads;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final library = services.library;
    final theme = Theme.of(context);
    final manifest = package.manifest;
    final task = library.taskFor(package.key);
    final hasUpdate = library.hasUpdate(package);

    final Widget status;
    if (task != null && task.isActive) {
      status = const StatusPill(
        label: 'Wird aktualisiert',
        icon: Icons.sync_rounded,
        tone: PillTone.accent,
      );
    } else if (task?.failure != null) {
      status = const StatusPill(
        label: 'Aktualisierung fehlgeschlagen',
        icon: Icons.error_outline_rounded,
        tone: PillTone.error,
      );
    } else if (hasUpdate) {
      status = const StatusPill(
        label: 'Update verfügbar',
        icon: Icons.arrow_circle_up_rounded,
        tone: PillTone.warning,
      );
    } else {
      status = const StatusPill(
        label: 'Offline verfügbar',
        icon: Icons.offline_pin_rounded,
        tone: PillTone.accent,
      );
    }

    return Semantics(
      button: true,
      label:
          '${manifest.service.name}, ${formatServiceDate(manifest.service.serviceDate)}',
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => PlayerScreen(package: package),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DateTile(date: manifest.service.serviceDate),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            manifest.service.name,
                            style: theme.textTheme.titleMedium,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formatServiceDate(manifest.service.serviceDate),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${stepCountLabel(manifest.steps.length)} · '
                            '${formatBytes(manifest.totalAudioBytes)}',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          status,
                        ],
                      ),
                    ),
                    PopupMenuButton<_Action>(
                      tooltip: 'Aktionen',
                      icon: const Icon(Icons.more_horiz_rounded),
                      onSelected: (a) => _onAction(context, a),
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: _Action.update,
                          enabled: task == null || !task.isActive,
                          child: ListTile(
                            leading: const Icon(Icons.refresh_rounded),
                            title: Text(
                              hasUpdate
                                  ? 'Aktualisieren'
                                  : 'Erneut herunterladen',
                            ),
                          ),
                        ),
                        const PopupMenuItem(
                          value: _Action.info,
                          child: ListTile(
                            leading: Icon(Icons.info_outline_rounded),
                            title: Text('Paketinformationen'),
                          ),
                        ),
                        PopupMenuItem(
                          value: _Action.delete,
                          child: ListTile(
                            leading: Icon(
                              Icons.delete_outline_rounded,
                              color: theme.colorScheme.error,
                            ),
                            title: Text(
                              'Löschen',
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (task != null && task.isActive) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: LinearProgressIndicator(
                      value: task.fraction,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onAction(BuildContext context, _Action action) async {
    switch (action) {
      case _Action.info:
        await showPackageInfo(context, package);
      case _Action.update:
        requestPackageDownload(
          context,
          package,
          onOpenDownloads: onOpenDownloads,
        );
      case _Action.delete:
        await confirmDelete(context, package);
    }
  }
}

/// Lädt ein lokales Paket erneut – sofern der passende Server angemeldet ist.
void requestPackageDownload(
  BuildContext context,
  LocalPackage package, {
  VoidCallback? onOpenDownloads,
}) {
  final services = AppScope.of(context);
  final account = services.account;
  final messenger = ScaffoldMessenger.of(context);
  if (account.server?.origin != package.serverOrigin) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Dieser Gottesdienst stammt von ${package.serverOrigin}. '
          'Bitte zuerst mit diesem Server verbinden.',
        ),
      ),
    );
    return;
  }
  if (!account.canDownload) {
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Zum Aktualisieren bitte zuerst anmelden.'),
        action: onOpenDownloads == null
            ? null
            : SnackBarAction(label: 'Anmelden', onPressed: onOpenDownloads),
      ),
    );
    return;
  }
  PackageSummary? summary;
  for (final s in services.library.remote ?? const <PackageSummary>[]) {
    if (s.serviceId == package.serviceId) summary = s;
  }
  final m = package.manifest;
  services.library.download([
    summary ??
        PackageSummary(
          serviceId: m.service.id,
          name: m.service.name,
          serviceDate: m.service.serviceDate,
          version: m.version,
          updatedAt: m.service.updatedAt,
          stepCount: m.steps.length,
          totalAudioBytes: m.totalAudioBytes,
          manifestUrl: '/api/packages/${m.service.id}',
          downloadUrl: '/api/packages/${m.service.id}/download',
        ),
  ]);
}

Future<bool> confirmDelete(BuildContext context, LocalPackage package) async {
  final services = AppScope.of(context);
  final freed = await services.repository.exclusiveBytes(
    package,
    services.library.packages,
  );
  if (!context.mounted) return false;
  final ok = await showAdaptiveDialog<bool>(
    context: context,
    builder: (context) => AlertDialog.adaptive(
      title: Text('„${package.manifest.service.name}“ löschen?'),
      content: Text(
        'Der Gottesdienst wird vom Gerät entfernt (${formatBytes(freed)} werden frei). '
        'Er kann jederzeit erneut vom Server geladen werden.',
      ),
      actions: [
        adaptiveDialogAction(
          context,
          label: 'Abbrechen',
          onPressed: () => Navigator.pop(context, false),
        ),
        adaptiveDialogAction(
          context,
          label: 'Löschen',
          destructive: true,
          onPressed: () => Navigator.pop(context, true),
        ),
      ],
    ),
  );
  if (ok != true) return false;
  await services.library.delete(package);
  return true;
}

Widget adaptiveDialogAction(
  BuildContext context, {
  required String label,
  required VoidCallback onPressed,
  bool destructive = false,
}) {
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return CupertinoDialogAction(
      onPressed: onPressed,
      isDestructiveAction: destructive,
      child: Text(label),
    );
  }
  return TextButton(
    onPressed: onPressed,
    style: destructive
        ? TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          )
        : null,
    child: Text(label),
  );
}
