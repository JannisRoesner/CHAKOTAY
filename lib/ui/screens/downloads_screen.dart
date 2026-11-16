import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/models.dart';
import '../../app/app_scope.dart';
import '../../auth/account_controller.dart';
import '../../core/failures.dart';
import '../../library/library_controller.dart';
import '../../packages/package_repository.dart';
import '../format.dart';
import '../widgets/common.dart';
import '../widgets/server_forms.dart';

/// Verbindung zum CHAPEL-Server und Herunterladen von Gottesdiensten.
class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).account;
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final Widget body = switch (account.state) {
          AccountState.noServer => const _Centered(child: ServerForm()),
          AccountState.signedOut ||
          AccountState.sessionExpired => const _Centered(child: LoginForm()),
          AccountState.passwordChangeRequired => const _Centered(
            child: _PasswordChangeCard(),
          ),
          AccountState.unverified ||
          AccountState.connected ||
          AccountState.offline => const _RemoteList(),
        };
        return Scaffold(body: body);
      },
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        const SliverAppBar.large(title: Text('Laden')),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                child: child,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PasswordChangeCard extends StatelessWidget {
  const _PasswordChangeCard();

  @override
  Widget build(BuildContext context) {
    final account = AppScope.of(context).account;
    final theme = Theme.of(context);
    final uri = account.passwordChangeUri;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.lock_reset_rounded,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          'Passwort ändern erforderlich',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'Ihr CHAPEL-Konto verlangt ein neues Passwort. Bitte melden Sie sich in '
          'der CHAPEL-Weboberfläche an und vergeben Sie dort ein neues Passwort. '
          'Danach können Sie hier Gottesdienste laden.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        if (uri != null)
          FilledButton.icon(
            onPressed: () =>
                launchUrl(uri, mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('CHAPEL im Browser öffnen'),
          ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: account.logout,
          child: const Text('Abmelden und neu anmelden'),
        ),
      ],
    );
  }
}

class _RemoteList extends StatefulWidget {
  const _RemoteList();

  @override
  State<_RemoteList> createState() => _RemoteListState();
}

class _RemoteListState extends State<_RemoteList> {
  final Set<int> _selected = {};
  bool _requested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_requested) {
      _requested = true;
      final library = AppScope.of(context).library;
      if (library.remote == null && !library.loadingRemote) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => library.refreshRemote(),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final library = services.library;
    final account = services.account;
    return ListenableBuilder(
      listenable: Listenable.merge([library, account]),
      builder: (context, _) {
        final remote = library.remote;
        final selectable = <int, PackageSummary>{
          for (final s in remote ?? const <PackageSummary>[])
            if (_isSelectable(library.statusFor(s))) s.serviceId: s,
        };
        _selected.removeWhere((id) => !selectable.containsKey(id));
        final updates = [
          for (final s in remote ?? const <PackageSummary>[])
            if (library.statusFor(s) == PackageStatus.updateAvailable) s,
        ];

        return Scaffold(
          body: RefreshIndicator.adaptive(
            onRefresh: library.refreshRemote,
            edgeOffset: 120,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverAppBar.large(
                  title: const Text('Laden'),
                  actions: [
                    IconButton(
                      tooltip: 'Liste aktualisieren',
                      onPressed: library.loadingRemote
                          ? null
                          : library.refreshRemote,
                      icon: const Icon(Icons.refresh_rounded),
                    ),
                  ],
                ),
                SliverToBoxAdapter(child: _ServerHeader(account: account)),
                if (library.remoteFailure != null)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    sliver: SliverToBoxAdapter(
                      child: FailureBanner(
                        failure: library.remoteFailure!,
                        action: TextButton(
                          onPressed: library.refreshRemote,
                          child: const Text('Erneut versuchen'),
                        ),
                      ),
                    ),
                  ),
                if (remote == null && library.loadingRemote)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  )
                else if (remote != null && remote.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                      icon: Icons.event_busy_rounded,
                      title: 'Keine Gottesdienste',
                      message:
                          'Auf dem Server sind noch keine Gottesdienste angelegt.',
                    ),
                  )
                else if (remote != null) ...[
                  if (updates.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      sliver: SliverToBoxAdapter(
                        child: OutlinedButton.icon(
                          onPressed: () => library.download(updates),
                          icon: const Icon(Icons.arrow_circle_up_rounded),
                          label: Text(
                            updates.length == 1
                                ? '1 Update laden'
                                : '${updates.length} Updates laden',
                          ),
                        ),
                      ),
                    ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                    sliver: SliverList.separated(
                      itemCount: remote.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final s = remote[i];
                        return _RemoteRow(
                          summary: s,
                          status: library.statusFor(s),
                          task: library.taskFor(
                            packageKey(account.server!.origin, s.serviceId),
                          ),
                          selected: _selected.contains(s.serviceId),
                          onToggle: selectable.containsKey(s.serviceId)
                              ? () => setState(() {
                                  if (!_selected.remove(s.serviceId)) {
                                    _selected.add(s.serviceId);
                                  }
                                })
                              : null,
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          bottomNavigationBar: _selected.isEmpty
              ? null
              : SafeArea(
                  minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: FilledButton.icon(
                    onPressed: () {
                      library.download(_selected.map((id) => selectable[id]!));
                      setState(_selected.clear);
                    },
                    icon: const Icon(Icons.download_rounded),
                    label: Text(
                      _selected.length == 1
                          ? '1 Gottesdienst laden'
                          : '${_selected.length} Gottesdienste laden',
                    ),
                  ),
                ),
        );
      },
    );
  }

  static bool _isSelectable(PackageStatus status) =>
      status == PackageStatus.notDownloaded ||
      status == PackageStatus.updateAvailable ||
      status == PackageStatus.failed;
}

class _ServerHeader extends StatelessWidget {
  const _ServerHeader({required this.account});
  final AccountController account;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = account.user;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: [
          Icon(
            account.server?.isSecure ?? false
                ? Icons.lock_rounded
                : Icons.lock_open_rounded,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              [
                account.server?.display,
                if (user != null) user.name,
              ].nonNulls.join(' · '),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _RemoteRow extends StatelessWidget {
  const _RemoteRow({
    required this.summary,
    required this.status,
    required this.task,
    required this.selected,
    required this.onToggle,
  });

  final PackageSummary summary;
  final PackageStatus status;
  final DownloadTask? task;
  final bool selected;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = AppScope.of(context).library;
    final pill = switch (status) {
      PackageStatus.notDownloaded => const StatusPill(
        label: 'Nicht geladen',
        icon: Icons.cloud_outlined,
      ),
      PackageStatus.upToDate => const StatusPill(
        label: 'Aktuell',
        icon: Icons.check_circle_rounded,
        tone: PillTone.accent,
      ),
      PackageStatus.updateAvailable => const StatusPill(
        label: 'Update verfügbar',
        icon: Icons.arrow_circle_up_rounded,
        tone: PillTone.warning,
      ),
      PackageStatus.downloading => StatusPill(
        label: task?.phase == DownloadPhase.verifying
            ? 'Wird geprüft'
            : task?.phase == DownloadPhase.queued
            ? 'Wartet'
            : 'Wird geladen',
        icon: Icons.downloading_rounded,
        tone: PillTone.accent,
      ),
      PackageStatus.failed => const StatusPill(
        label: 'Fehlgeschlagen',
        icon: Icons.error_outline_rounded,
        tone: PillTone.error,
      ),
    };

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 10, 8, 10),
          child: Column(
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 48,
                    child: onToggle == null
                        ? null
                        : Checkbox.adaptive(
                            value: selected,
                            onChanged: (_) => onToggle!(),
                            semanticLabel: '${summary.name} auswählen',
                          ),
                  ),
                  DateTile(date: summary.serviceDate, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          summary.name,
                          style: theme.textTheme.titleMedium,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          '${formatShortDate(summary.serviceDate)} · '
                          '${stepCountLabel(summary.stepCount)} · '
                          '${formatBytes(summary.totalAudioBytes)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 6),
                        pill,
                      ],
                    ),
                  ),
                  if (status == PackageStatus.downloading && task != null)
                    IconButton(
                      tooltip: 'Download abbrechen',
                      onPressed: () => library.cancel(task!.key),
                      icon: const Icon(Icons.cancel_rounded),
                    ),
                ],
              ),
              if (status == PackageStatus.downloading && task != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      LinearProgressIndicator(
                        value: task!.fraction,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _progressText(task!),
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
              if (status == PackageStatus.failed && task?.failure != null) ...[
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.only(left: 12, right: 4),
                  child: FailureBanner(
                    failure: task!.failure!,
                    onDismiss: () => library.dismissFailure(task!.key),
                    action: TextButton(
                      onPressed: () => library.download([summary]),
                      child: const Text('Erneut versuchen'),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _progressText(DownloadTask task) {
    switch (task.phase) {
      case DownloadPhase.queued:
        return 'In Warteschlange';
      case DownloadPhase.downloading:
        final total = task.total ?? task.summary.totalAudioBytes;
        return '${formatBytes(task.received)} von ${formatBytes(total)}';
      case DownloadPhase.verifying:
        return 'Prüfsummen werden kontrolliert …';
    }
  }
}

/// Meldung für einen [AppFailure] als SnackBar.
void showFailureSnackBar(BuildContext context, AppFailure failure) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('${failure.title}. ${failure.message}')),
  );
}
