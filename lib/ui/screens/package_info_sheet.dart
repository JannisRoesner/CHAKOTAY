import 'package:flutter/material.dart';

import '../../app/app_scope.dart';
import '../../packages/package_repository.dart';
import '../format.dart';
import '../widgets/common.dart';

/// Zeigt den lokalen Paketstand als Bottom Sheet.
Future<void> showPackageInfo(BuildContext context, LocalPackage package) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (context, controller) =>
          _PackageInfo(package: package, controller: controller),
    ),
  );
}

class _PackageInfo extends StatelessWidget {
  const _PackageInfo({required this.package, required this.controller});

  final LocalPackage package;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final m = package.manifest;
    final theme = Theme.of(context);
    final remoteVersion = services.settings.remoteVersions[package.key];
    final empty = m.steps.where((s) => !s.isPlayable).length;

    Widget row(String label, String value) => ListTile(
      title: Text(label),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: Text(
          value,
          textAlign: TextAlign.end,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );

    return ListView(
      controller: controller,
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(
            children: [
              DateTile(date: m.service.serviceDate, size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(m.service.name, style: theme.textTheme.titleLarge),
                    Text(
                      formatServiceDate(m.service.serviceDate),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        GroupedSection(
          header: 'Paketstand',
          children: [
            row(
              'Version',
              m.version.substring(0, m.version.length.clamp(0, 12)),
            ),
            row(
              'Status',
              remoteVersion == null
                  ? 'Nicht geprüft'
                  : remoteVersion == m.version
                  ? 'Aktuell'
                  : 'Update verfügbar',
            ),
            row('Heruntergeladen', formatDateTime(package.installedAt)),
            if (m.generatedAt != null)
              row('Erstellt', formatDateTime(m.generatedAt!)),
            row('Formatversion', '${m.formatVersion}'),
          ],
        ),
        GroupedSection(
          header: 'Inhalt',
          children: [
            row('Ablaufschritte', '${m.steps.length}'),
            row('Mit Audio', '${m.playableStepCount}'),
            if (empty > 0) row('Ohne Audio', '$empty'),
            row('Audiodateien', '${m.distinctAudio.length}'),
            row('Größe', formatBytes(m.totalAudioBytes)),
          ],
        ),
        GroupedSection(
          header: 'Herkunft',
          footer:
              'Alle Audiodateien wurden beim Herunterladen per SHA-256 geprüft.',
          children: [row('Server', package.serverOrigin)],
        ),
        if (m.service.notes != null && m.service.notes!.trim().isNotEmpty)
          GroupedSection(
            header: 'Notizen',
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(m.service.notes!, style: theme.textTheme.bodyLarge),
              ),
            ],
          ),
      ],
    );
  }
}
