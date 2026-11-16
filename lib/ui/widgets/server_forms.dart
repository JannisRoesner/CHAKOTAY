import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/app_scope.dart';
import '../../auth/account_controller.dart';
import '../../core/failures.dart';
import '../screens/library_screen.dart' show adaptiveDialogAction;
import 'common.dart';

/// Eingabe der CHAPEL-Serveradresse.
class ServerForm extends StatefulWidget {
  const ServerForm({super.key});

  @override
  State<ServerForm> createState() => _ServerFormState();
}

class _ServerFormState extends State<ServerForm> {
  late final TextEditingController _controller;
  AppFailure? _failure;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_controller.text.isEmpty) {
      _controller.text = AppScope.of(context).account.server?.display ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit({bool allowInsecure = false}) async {
    final account = AppScope.of(context).account;
    setState(() => _failure = null);
    try {
      await account.setServer(
        _controller.text,
        allowInsecure: allowInsecure || account.settings.allowInsecure,
      );
    } on AppFailure catch (e) {
      if (e.kind == FailureKind.insecureConnection && !allowInsecure) {
        if (await _confirmInsecure()) await _submit(allowInsecure: true);
        return;
      }
      if (mounted) setState(() => _failure = e);
    }
  }

  Future<bool> _confirmInsecure() async {
    final ok = await showAdaptiveDialog<bool>(
      context: context,
      builder: (context) => AlertDialog.adaptive(
        title: const Text('Unverschlüsselte Verbindung?'),
        content: const Text(
          'Diese Adresse verwendet HTTP statt HTTPS. Anmeldedaten und Sitzung '
          'würden unverschlüsselt übertragen. Nur in vertrauenswürdigen '
          'Netzwerken (z. B. Testserver im eigenen WLAN) verwenden.',
        ),
        actions: [
          adaptiveDialogAction(
            context,
            label: 'Abbrechen',
            onPressed: () => Navigator.pop(context, false),
          ),
          adaptiveDialogAction(
            context,
            label: 'Trotzdem verbinden',
            destructive: true,
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = AppScope.of(context).account;
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Mit CHAPEL verbinden', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
            'Geben Sie die Adresse Ihres CHAPEL-Servers ein – dieselbe, die Sie '
            'im Browser verwenden.',
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            enabled: !account.busy,
            autofocus: account.server == null,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.go,
            autofillHints: const [AutofillHints.url],
            decoration: const InputDecoration(
              labelText: 'Serveradresse',
              hintText: 'chapel.gemeinde.de',
              prefixIcon: Icon(Icons.dns_outlined),
            ),
            onSubmitted: (_) => _submit(),
          ),
          if (_failure != null) ...[
            const SizedBox(height: 12),
            FailureBanner(failure: _failure!),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: account.busy ? null : _submit,
            child: account.busy
                ? const SizedBox.square(
                    dimension: 22,
                    child: CircularProgressIndicator.adaptive(strokeWidth: 2.5),
                  )
                : const Text('Weiter'),
          ),
          if (account.server != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: account.busy ? null : account.restore,
              child: const Text('Abbrechen'),
            ),
          ],
        ],
      ),
    );
  }
}

/// Anmeldung mit E-Mail und Passwort. Das Passwort wird nie gespeichert.
class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _obscure = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_email.text.isEmpty) {
      _email.text = AppScope.of(context).account.user?.email ?? '';
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final account = AppScope.of(context).account;
    final library = AppScope.of(context).library;
    if (_email.text.trim().isEmpty || _password.text.isEmpty) return;
    try {
      final user = await account.login(_email.text, _password.text);
      _password.clear();
      TextInput.finishAutofillContext();
      if (!user.mustChangePassword) await library.refreshRemote();
    } on AppFailure {
      // Anzeige über account.lastFailure.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final account = AppScope.of(context).account;
    return ListenableBuilder(
      listenable: account,
      builder: (context, _) {
        final expired = account.state == AccountState.sessionExpired;
        return AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Anmelden', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Row(
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
                      account.server?.display ?? '',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: account.busy ? null : account.editServer,
                    child: const Text('Ändern'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (expired && account.lastFailure == null) ...[
                const FailureBanner(
                  failure: AppFailure(FailureKind.sessionExpired),
                ),
                const SizedBox(height: 16),
              ],
              if (account.lastFailure != null) ...[
                FailureBanner(failure: account.lastFailure!),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: _email,
                enabled: !account.busy,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                decoration: const InputDecoration(
                  labelText: 'E-Mail-Adresse',
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
                onSubmitted: (_) => _passwordFocus.requestFocus(),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                focusNode: _passwordFocus,
                enabled: !account.busy,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                decoration: InputDecoration(
                  labelText: 'Passwort',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscure
                        ? 'Passwort anzeigen'
                        : 'Passwort verbergen',
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: account.busy ? null : _submit,
                child: account.busy
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2.5,
                        ),
                      )
                    : const Text('Anmelden'),
              ),
              const SizedBox(height: 12),
              Text(
                'Ihr Passwort wird nicht gespeichert. Heruntergeladene Gottesdienste '
                'bleiben auch nach dem Abmelden auf dem Gerät.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        );
      },
    );
  }
}
