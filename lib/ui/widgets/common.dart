import 'package:flutter/material.dart';

import '../../core/failures.dart';
import '../format.dart';
import '../theme.dart';

/// Signaturelement: Kalenderblatt mit Tag und Monat des Gottesdienstes.
class DateTile extends StatelessWidget {
  const DateTile({super.key, required this.date, this.size = 56});

  final DateTime date;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = ChakotayColors.of(context);
    final day = serviceDay(date);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tokens.liturgyContainer,
          borderRadius: BorderRadius.circular(size * 0.24),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            Container(
              height: size * 0.3,
              width: double.infinity,
              color: tokens.song,
              alignment: Alignment.center,
              child: FittedBox(
                child: Text(
                  formatMonthShort(date),
                  textScaler: TextScaler.noScaling,
                  style: TextStyle(
                    fontSize: size * 0.18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.6,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
            Expanded(
              child: Center(
                child: FittedBox(
                  child: Text(
                    '${day.day}',
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      fontSize: size * 0.4,
                      fontWeight: FontWeight.w700,
                      height: 1,
                      color: Theme.of(context).colorScheme.onSurface,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum PillTone { neutral, accent, warning, error }

/// Kompakter Status mit Symbol **und** Text (nie nur Farbe).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.icon,
    this.tone = PillTone.neutral,
  });

  final String label;
  final IconData icon;
  final PillTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = ChakotayColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (fg, bg) = switch (tone) {
      PillTone.neutral => (
        scheme.onSurfaceVariant,
        scheme.surfaceContainerHigh,
      ),
      PillTone.accent => (tokens.song, tokens.songContainer),
      PillTone.warning => (tokens.warning, tokens.warningContainer),
      PillTone.error => (scheme.error, scheme.error.withValues(alpha: 0.12)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: ChakotayColors.of(context).songContainer,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 40, color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (action != null) ...[const SizedBox(height: 24), action!],
            ],
          ),
        ),
      ),
    );
  }
}

/// Hinweisfläche für Fehler mit optionaler Aktion.
class FailureBanner extends StatelessWidget {
  const FailureBanner({
    super.key,
    required this.failure,
    this.action,
    this.onDismiss,
  });

  final AppFailure failure;
  final Widget? action;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final tokens = ChakotayColors.of(context);
    final theme = Theme.of(context);
    final isWarning =
        failure.kind == FailureKind.offline ||
        failure.kind == FailureKind.sessionExpired;
    final fg = isWarning ? tokens.warning : theme.colorScheme.error;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
        decoration: BoxDecoration(
          color: isWarning
              ? tokens.warningContainer
              : theme.colorScheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                isWarning
                    ? Icons.info_outline_rounded
                    : Icons.error_outline_rounded,
                color: fg,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    failure.title,
                    style: theme.textTheme.titleMedium?.copyWith(color: fg),
                  ),
                  const SizedBox(height: 2),
                  Text(failure.message, style: theme.textTheme.bodyMedium),
                  if (action != null) ...[const SizedBox(height: 8), action!],
                ],
              ),
            ),
            if (onDismiss != null)
              IconButton(
                tooltip: 'Hinweis schließen',
                onPressed: onDismiss,
                icon: const Icon(Icons.close_rounded),
              ),
          ],
        ),
      ),
    );
  }
}

/// Gruppierte Liste im Stil der iOS-„Inset Grouped“-Tabellen.
class GroupedSection extends StatelessWidget {
  const GroupedSection({
    super.key,
    this.header,
    this.footer,
    required this.children,
  });

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = ChakotayColors.of(context);
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) items.add(const Divider(indent: 16));
      items.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (header != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Semantics(
                header: true,
                child: Text(
                  header!.toUpperCase(),
                  style: theme.textTheme.bodySmall?.copyWith(
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          Material(
            color: tokens.card,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: Column(children: items),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(footer!, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}
