import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/app_scope.dart';
import '../../packages/element_type.dart';
import '../../packages/manifest.dart';
import '../../packages/package_repository.dart';
import '../../playback/audio_engine.dart';
import '../../playback/player_controller.dart';
import '../format.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'library_screen.dart' show requestPackageDownload;
import 'package_info_sheet.dart';

/// Wiedergabeansicht eines heruntergeladenen Gottesdienstes.
///
/// Bewusst reduziert: Ablauf + große Bedienelemente. Keine Suchleiste
/// (Scrubbing), keine Warteschlange, kein Autoplay – wie im CHAPEL-Player.
class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.package});

  final LocalPackage package;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen>
    with WidgetsBindingObserver {
  PlayerController? _controller;
  AudioEngine? _engine;
  final Map<int, GlobalKey> _itemKeys = {};
  int? _scrolledTo;
  int _missingAudio = 0;
  bool _wakelock = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller != null) return;
    final services = AppScope.of(context);
    _engine = services.engineFactory();
    _controller = PlayerController(
      package: widget.package,
      engine: _engine!,
      resolveAudio: services.repository.audioFile,
      progressStore: services.progress,
    )..addListener(_onControllerChanged);
    unawaited(_controller!.init());
    unawaited(
      services.repository.missingAudio(widget.package).then((missing) {
        if (mounted) setState(() => _missingAudio = missing.length);
      }),
    );
    if (services.settings.keepScreenOn) {
      _wakelock = true;
      unawaited(WakelockPlus.enable().catchError((Object _) {}));
    }
  }

  void _onControllerChanged() {
    final index = _controller!.currentIndex;
    if (index != _scrolledTo) {
      _scrolledTo = index;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  void _scrollToCurrent() {
    final ctx = _itemKeys[_controller?.currentIndex]?.currentContext;
    if (ctx == null || !mounted) return;
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.3,
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Wiedergabe läuft im Hintergrund / bei gesperrtem Gerät weiter
    // (Background-Audio); der Fortschritt wird vorsorglich gesichert.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _controller?.saveProgress();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final controller = _controller;
    final engine = _engine;
    if (controller != null) {
      controller.removeListener(_onControllerChanged);
      unawaited(
        controller.close().whenComplete(() async {
          controller.dispose();
          await engine?.dispose();
        }),
      );
    }
    if (_wakelock) unawaited(WakelockPlus.disable().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    final service = widget.package.manifest.service;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(service.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              formatServiceDate(service.serviceDate),
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Paketinformationen',
            onPressed: () => showPackageInfo(context, widget.package),
            icon: const Icon(Icons.info_outline_rounded),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final list = _StepList(
              controller: controller,
              itemKeys: _itemKeys,
              header: _missingAudio > 0
                  ? Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MissingAudioBanner(
                        count: _missingAudio,
                        onReload: () =>
                            requestPackageDownload(context, widget.package),
                      ),
                    )
                  : null,
            );
            final panel = _ControlPanel(controller: controller, wide: wide);
            if (wide) {
              return Row(
                children: [
                  Expanded(child: list),
                  SizedBox(
                    width: constraints.maxWidth >= 1000 ? 440 : 380,
                    child: panel,
                  ),
                ],
              );
            }
            return Column(
              children: [
                Expanded(child: list),
                panel,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MissingAudioBanner extends StatelessWidget {
  const _MissingAudioBanner({required this.count, required this.onReload});
  final int count;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    final tokens = ChakotayColors.of(context);
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tokens.warningContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: tokens.warning),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              count == 1
                  ? '1 Audiodatei fehlt auf dem Gerät.'
                  : '$count Audiodateien fehlen auf dem Gerät.',
              style: theme.textTheme.bodyMedium,
            ),
          ),
          TextButton(onPressed: onReload, child: const Text('Neu laden')),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Ablauf

class _StepList extends StatelessWidget {
  const _StepList({
    required this.controller,
    required this.itemKeys,
    this.header,
  });

  final PlayerController controller;
  final Map<int, GlobalKey> itemKeys;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final steps = controller.steps;
    if (steps.isEmpty) {
      return const EmptyState(
        icon: Icons.format_list_bulleted_rounded,
        title: 'Leerer Ablauf',
        message: 'Dieser Gottesdienst enthält keine Schritte.',
      );
    }
    // Ein Gottesdienst hat überschaubar viele Schritte – alle Einträge werden
    // gebaut, damit der aktuelle Schritt zuverlässig in den Blick scrollt.
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ?header,
          for (var i = 0; i < steps.length; i++)
            Padding(
              key: itemKeys.putIfAbsent(i, GlobalKey.new),
              padding: const EdgeInsets.only(bottom: 8),
              child: _StepTile(
                index: i,
                step: steps[i],
                elementType: controller.package.elementTypeOf(steps[i].kind),
                isCurrent: i == controller.currentIndex,
                isPlaying: i == controller.currentIndex && controller.isPlaying,
                played: controller.playedIndices.contains(i),
                onTap: () {
                  HapticFeedback.selectionClick();
                  controller.select(i);
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.step,
    required this.elementType,
    required this.isCurrent,
    required this.isPlaying,
    required this.played,
    required this.onTap,
  });

  final int index;
  final PackageStep step;
  final ElementType elementType;
  final bool isCurrent;
  final bool isPlaying;
  final bool played;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = ChakotayColors.of(context);
    final kindColor = elementType.toneColor(context);
    final kindLabel = elementType.label;
    final empty = !step.isPlayable;
    final duration = step.durationMs == null
        ? null
        : Duration(milliseconds: step.durationMs!);

    final semantics = [
      'Schritt ${index + 1}',
      kindLabel,
      step.label,
      if (step.title != null) step.title!,
      if (empty) 'ohne Audio, wird übersprungen',
      if (duration != null) 'Dauer ${formatDuration(duration)}',
      if (step.playbackRate != 1) 'Tempo ${formatRate(step.playbackRate)}',
      if (played) 'bereits gespielt',
      if (isCurrent) 'ausgewählt',
    ].join(', ');

    return Semantics(
      button: true,
      selected: isCurrent,
      label: semantics,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: MediaQuery.of(context).disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isCurrent ? tokens.songContainer : tokens.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCurrent ? theme.colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 72),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
                child: Row(
                  children: [
                    _StepMarker(
                      number: index + 1,
                      isCurrent: isCurrent,
                      isPlaying: isPlaying,
                      played: played,
                      color: kindColor,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Opacity(
                        opacity: empty || (played && !isCurrent) ? 0.62 : 1,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: '${kindLabel.toUpperCase()} · ',
                                    style: TextStyle(
                                      color: kindColor,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                  TextSpan(text: step.label),
                                ],
                              ),
                              style: theme.textTheme.bodySmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              empty
                                  ? 'Kein Audio – wird übersprungen'
                                  : (step.title ?? '—'),
                              style: empty
                                  ? theme.textTheme.bodyLarge?.copyWith(
                                      fontStyle: FontStyle.italic,
                                      color: theme.colorScheme.onSurfaceVariant,
                                    )
                                  : theme.textTheme.titleMedium,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (step.composer != null &&
                                step.composer!.isNotEmpty)
                              Text(
                                step.composer!,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (!empty) ...[
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatDuration(duration),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          if (step.playbackRate != 1) ...[
                            const SizedBox(height: 4),
                            StatusPill(
                              label: formatRate(step.playbackRate),
                              icon: Icons.speed_rounded,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StepMarker extends StatelessWidget {
  const _StepMarker({
    required this.number,
    required this.isCurrent,
    required this.isPlaying,
    required this.played,
    required this.color,
  });

  final int number;
  final bool isCurrent;
  final bool isPlaying;
  final bool played;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Widget child;
    if (isPlaying) {
      child = Icon(Icons.graphic_eq_rounded, size: 20, color: scheme.onPrimary);
    } else if (played && !isCurrent) {
      child = Icon(Icons.check_rounded, size: 20, color: color);
    } else {
      child = Text(
        '$number',
        textScaler: TextScaler.noScaling,
        style: TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 15,
          color: isCurrent ? scheme.onPrimary : color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
    }
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isCurrent ? scheme.primary : Colors.transparent,
        border: Border.all(
          color: isCurrent ? scheme.primary : color,
          width: 1.5,
        ),
      ),
      child: child,
    );
  }
}

// ------------------------------------------------------------- Bedienung

class _ControlPanel extends StatelessWidget {
  const _ControlPanel({required this.controller, required this.wide});

  final PlayerController controller;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = ChakotayColors.of(context);
    final step = controller.currentStep;
    final status = controller.status;

    final pill = switch (status) {
      PlaybackStatus.playing => const StatusPill(
        label: 'Läuft',
        icon: Icons.graphic_eq_rounded,
        tone: PillTone.accent,
      ),
      PlaybackStatus.paused => const StatusPill(
        label: 'Pausiert',
        icon: Icons.pause_rounded,
        tone: PillTone.warning,
      ),
      PlaybackStatus.loading => const StatusPill(
        label: 'Wird vorbereitet',
        icon: Icons.hourglass_top_rounded,
      ),
      PlaybackStatus.finishedLast => const StatusPill(
        label: 'Letzter Titel beendet',
        icon: Icons.flag_rounded,
        tone: PillTone.accent,
      ),
      PlaybackStatus.idle =>
        controller.justFinished
            ? const StatusPill(
                label: 'Titel beendet – bereit',
                icon: Icons.check_circle_rounded,
                tone: PillTone.accent,
              )
            : const StatusPill(label: 'Gestoppt', icon: Icons.stop_rounded),
    };

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 6,
          children: [
            Semantics(liveRegion: true, child: pill),
            Text(
              'Schritt ${controller.currentIndex + 1} von ${controller.steps.length}',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          step?.label ?? '—',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: step == null
                ? tokens.song
                : controller.package
                      .elementTypeOf(step.kind)
                      .toneColor(context),
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          step == null
              ? '—'
              : step.isPlayable
              ? (step.title ?? 'Ohne Titel')
              : 'Kein Audio',
          style: theme.textTheme.headlineSmall,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (step?.composer != null && step!.composer!.isNotEmpty)
          Text(
            step.composer!,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        const SizedBox(height: 14),
        if (step?.isPlayable ?? false)
          _ProgressRow(controller: controller)
        else
          Text(
            'Dieser Schritt hat kein Audio. „Nächster“ startet den nächsten Titel.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        if (controller.notice != null) ...[
          const SizedBox(height: 10),
          _InlineNote(
            icon: Icons.phone_paused_rounded,
            text: '${controller.notice!}. Zum Fortsetzen „Abspielen“ tippen.',
            color: tokens.warning,
          ),
        ],
        if (controller.failure != null) ...[
          const SizedBox(height: 10),
          _InlineNote(
            icon: Icons.error_outline_rounded,
            text:
                '${controller.failure!.title}: ${controller.failure!.message}',
            color: theme.colorScheme.error,
          ),
        ],
        const SizedBox(height: 16),
        _Controls(controller: controller),
      ],
    );

    return Material(
      color: tokens.card,
      elevation: wide ? 0 : 8,
      shadowColor: Colors.black26,
      shape: wide
          ? Border(left: BorderSide(color: tokens.separator))
          : const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: wide
            ? SingleChildScrollView(child: content)
            : ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.62,
                ),
                child: SingleChildScrollView(child: content),
              ),
      ),
    );
  }
}

class _InlineNote extends StatelessWidget {
  const _InlineNote({
    required this.icon,
    required this.text,
    required this.color,
  });
  final IconData icon;
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = controller.currentDuration;
    final finished =
        controller.status == PlaybackStatus.finishedLast &&
        controller.lastFinishedIndex == controller.currentIndex;
    return ValueListenableBuilder<Duration>(
      valueListenable: controller.position,
      builder: (context, position, _) {
        final elapsed = finished ? (total ?? position) : position;
        final value = total == null || total.inMilliseconds == 0
            ? 0.0
            : (elapsed.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        final style = theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontFeatures: const [FontFeature.tabularFigures()],
        );
        return Semantics(
          label:
              'Fortschritt ${formatDuration(elapsed)} von ${formatDuration(total)}',
          excludeSemantics: true,
          child: Column(
            children: [
              LinearProgressIndicator(
                value: value,
                minHeight: 6,
                borderRadius: BorderRadius.circular(3),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(formatDuration(elapsed), style: style),
                  const Spacer(),
                  Text(
                    total == null
                        ? '–:––'
                        : '−${formatDuration(total - elapsed < Duration.zero ? Duration.zero : total - elapsed)}',
                    style: style,
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final playing = controller.isPlaying;
    final loading = controller.status == PlaybackStatus.loading;
    final canStop =
        controller.status == PlaybackStatus.playing ||
        controller.status == PlaybackStatus.paused;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 72,
                child: FilledButton(
                  onPressed: controller.canPlay || playing
                      ? () {
                          HapticFeedback.mediumImpact();
                          controller.togglePlay();
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                  child: loading
                      ? SizedBox.square(
                          dimension: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              playing
                                  ? Icons.pause_rounded
                                  : Icons.play_arrow_rounded,
                              size: 36,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                playing ? 'Pause' : 'Abspielen',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 72,
                child: OutlinedButton(
                  onPressed: controller.hasNext
                      ? () {
                          HapticFeedback.mediumImpact();
                          controller.next();
                        }
                      : null,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    side: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 1.5,
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.skip_next_rounded, size: 32),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'Nächster',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextButton.icon(
                onPressed: controller.hasPrevious ? controller.previous : null,
                icon: const Icon(Icons.skip_previous_rounded),
                label: const Text('Vorheriger'),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextButton.icon(
                onPressed: canStop ? controller.stop : null,
                icon: const Icon(Icons.stop_rounded),
                label: const Text('Stopp'),
                style: TextButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
